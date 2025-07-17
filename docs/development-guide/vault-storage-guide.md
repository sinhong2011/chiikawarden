# Tauri Vault Storage Architecture Guide

## Overview

This guide provides comprehensive recommendations for storing cipher and vault data in Tauri applications, specifically for password managers like Bitwarden. The architecture balances security, performance, and scalability requirements.

## Recommended Architecture: Hybrid Approach

For maximum security and performance, we recommend a **hybrid storage architecture** that combines:

1. **Tauri Stronghold** - For critical secrets and keys
2. **Encrypted SQLite** - For vault data and metadata
3. **Memory Cache** - For decrypted data during active sessions

### Architecture Diagram

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Stronghold    │    │  Encrypted SQLite │    │  Memory Cache   │
│                 │    │                  │    │                 │
│ • Master Key    │    │ • Cipher Data    │    │ • Decrypted     │
│ • User Key      │    │ • Metadata       │    │   CipherViews   │
│ • Device Keys   │    │ • Search Indices │    │ • Session Data  │
│ • API Tokens    │    │ • Sync State     │    │ • UI State      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
        │                        │                        │
        └────────────────────────┼────────────────────────┘
                                 │
                    ┌─────────────────────┐
                    │   Encryption Layer  │
                    │                     │
                    │ • Key Management    │
                    │ • Encrypt/Decrypt   │
                    │ • Security Policies │
                    └─────────────────────┘
```

## Security Principles

### Confidentiality
- **AES-256-CBC with HMAC-SHA256** for all cipher data encryption
- **Stronghold** provides military-grade key protection
- **Zero-knowledge architecture** - keys never stored unencrypted

### Integrity
- **HMAC verification** for all encrypted data
- **Database constraints** and foreign key relationships
- **Atomic transactions** for data consistency

### Availability
- **Local-first architecture** with offline capability
- **Incremental sync** for efficient data updates
- **Backup and recovery** mechanisms

## Implementation Guide

### 1. Stronghold Configuration

```rust
// src-tauri/src/storage/stronghold.rs
use tauri_plugin_stronghold::{Stronghold, StrongholdBuilder};
use std::path::PathBuf;

pub struct SecureKeyStore {
    stronghold: Stronghold,
}

impl SecureKeyStore {
    pub async fn new(vault_path: PathBuf, password: &str) -> Result<Self, String> {
        let stronghold = Stronghold::load(vault_path, password.to_string())
            .await
            .map_err(|e| format!("Failed to load stronghold: {}", e))?;

        Ok(Self { stronghold })
    }

    pub async fn store_master_key(&self, user_id: &str, key: &[u8]) -> Result<(), String> {
        let client = self.stronghold.create_client("master_keys").await?;
        let store = client.get_store();
        store.insert(user_id, key.to_vec()).await?;
        self.stronghold.save().await?;
        Ok(())
    }

    pub async fn get_master_key(&self, user_id: &str) -> Result<Vec<u8>, String> {
        let client = self.stronghold.load_client("master_keys").await?;
        let store = client.get_store();
        store.get(user_id).await
            .map_err(|e| format!("Key not found: {}", e))
    }
}
```

### 2. SQLite Database Schema

```sql
-- Database schema for encrypted vault data
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    encrypted_user_key TEXT NOT NULL,  -- Encrypted with master key
    kdf_type INTEGER NOT NULL,
    kdf_iterations INTEGER NOT NULL,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE ciphers (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    organization_id TEXT,
    type INTEGER NOT NULL,
    name TEXT NOT NULL,           -- Encrypted
    notes TEXT,                   -- Encrypted
    login_data TEXT,              -- Encrypted JSON
    card_data TEXT,               -- Encrypted JSON
    identity_data TEXT,           -- Encrypted JSON
    secure_note_data TEXT,        -- Encrypted JSON
    ssh_key_data TEXT,            -- Encrypted JSON
    fields TEXT,                  -- Encrypted JSON array
    attachments TEXT,             -- Encrypted JSON array
    password_history TEXT,        -- Encrypted JSON array
    revision_date DATETIME NOT NULL,
    creation_date DATETIME NOT NULL,
    deleted_date DATETIME,
    favorite BOOLEAN DEFAULT 0,
    folder_id TEXT,
    collection_ids TEXT,          -- JSON array of collection IDs
    reprompt INTEGER DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL
);

CREATE TABLE folders (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,           -- Encrypted
    revision_date DATETIME NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE sync_state (
    user_id TEXT PRIMARY KEY,
    last_sync DATETIME,
    sync_token TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Indices for performance
CREATE INDEX idx_ciphers_user_type ON ciphers(user_id, type);
CREATE INDEX idx_ciphers_user_folder ON ciphers(user_id, folder_id);
CREATE INDEX idx_ciphers_revision ON ciphers(revision_date);
CREATE INDEX idx_ciphers_deleted ON ciphers(deleted_date) WHERE deleted_date IS NOT NULL;
CREATE INDEX idx_folders_user ON folders(user_id);
```

### 3. Encryption Service

```rust
// src-tauri/src/crypto/encryption.rs
use aes::Aes256;
use block_modes::{BlockMode, Cbc};
use block_modes::block_padding::Pkcs7;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use rand::{RngCore, OsRng};

type Aes256Cbc = Cbc<Aes256, Pkcs7>;
type HmacSha256 = Hmac<Sha256>;

pub struct EncryptionService {
    key_store: SecureKeyStore,
}

#[derive(Debug, Clone)]
pub struct EncryptedData {
    pub iv: Vec<u8>,
    pub data: Vec<u8>,
    pub mac: Vec<u8>,
}

impl EncryptionService {
    pub fn new(key_store: SecureKeyStore) -> Self {
        Self { key_store }
    }

    pub async fn encrypt_string(
        &self,
        plaintext: &str,
        user_id: &str
    ) -> Result<EncryptedData, String> {
        let user_key = self.key_store.get_user_key(user_id).await?;
        let (enc_key, auth_key) = self.derive_keys(&user_key)?;

        // Generate random IV
        let mut iv = vec![0u8; 16];
        OsRng.fill_bytes(&mut iv);

        // Encrypt data
        let cipher = Aes256Cbc::new_from_slices(&enc_key, &iv)
            .map_err(|e| format!("Cipher creation failed: {}", e))?;
        let ciphertext = cipher.encrypt_vec(plaintext.as_bytes());

        // Calculate HMAC
        let mut mac_data = Vec::new();
        mac_data.extend_from_slice(&iv);
        mac_data.extend_from_slice(&ciphertext);

        let mut mac = HmacSha256::new_from_slice(&auth_key)
            .map_err(|e| format!("HMAC creation failed: {}", e))?;
        mac.update(&mac_data);
        let mac_result = mac.finalize().into_bytes().to_vec();

        Ok(EncryptedData {
            iv,
            data: ciphertext,
            mac: mac_result,
        })
    }

    pub async fn decrypt_string(
        &self,
        encrypted: &EncryptedData,
        user_id: &str
    ) -> Result<String, String> {
        let user_key = self.key_store.get_user_key(user_id).await?;
        let (enc_key, auth_key) = self.derive_keys(&user_key)?;

        // Verify HMAC
        let mut mac_data = Vec::new();
        mac_data.extend_from_slice(&encrypted.iv);
        mac_data.extend_from_slice(&encrypted.data);

        let mut mac = HmacSha256::new_from_slice(&auth_key)
            .map_err(|e| format!("HMAC creation failed: {}", e))?;
        mac.update(&mac_data);

        if mac.verify_slice(&encrypted.mac).is_err() {
            return Err("MAC verification failed".to_string());
        }

        // Decrypt data
        let cipher = Aes256Cbc::new_from_slices(&enc_key, &encrypted.iv)
            .map_err(|e| format!("Cipher creation failed: {}", e))?;
        let plaintext = cipher.decrypt_vec(&encrypted.data)
            .map_err(|e| format!("Decryption failed: {}", e))?;

        String::from_utf8(plaintext)
            .map_err(|e| format!("UTF-8 conversion failed: {}", e))
    }

    fn derive_keys(&self, user_key: &[u8]) -> Result<([u8; 32], [u8; 32]), String> {
        if user_key.len() != 64 {
            return Err("User key must be 64 bytes".to_string());
        }

        let mut enc_key = [0u8; 32];
        let mut auth_key = [0u8; 32];

        enc_key.copy_from_slice(&user_key[0..32]);
        auth_key.copy_from_slice(&user_key[32..64]);

        Ok((enc_key, auth_key))
    }
}

### 4. Vault Storage Service

```rust
// src-tauri/src/storage/vault.rs
use sqlx::{SqlitePool, Row};
use serde::{Serialize, Deserialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, Serialize, Deserialize)]
pub struct CipherData {
    pub id: String,
    pub user_id: String,
    pub organization_id: Option<String>,
    pub cipher_type: i32,
    pub name: String,
    pub notes: Option<String>,
    pub login_data: Option<String>,
    pub card_data: Option<String>,
    pub identity_data: Option<String>,
    pub secure_note_data: Option<String>,
    pub ssh_key_data: Option<String>,
    pub fields: Option<String>,
    pub attachments: Option<String>,
    pub password_history: Option<String>,
    pub revision_date: DateTime<Utc>,
    pub creation_date: DateTime<Utc>,
    pub deleted_date: Option<DateTime<Utc>>,
    pub favorite: bool,
    pub folder_id: Option<String>,
    pub collection_ids: Option<String>,
    pub reprompt: i32,
}

pub struct VaultStorage {
    db: SqlitePool,
    encryption: EncryptionService,
}

impl VaultStorage {
    pub async fn new(database_url: &str, encryption: EncryptionService) -> Result<Self, String> {
        let db = SqlitePool::connect(database_url).await
            .map_err(|e| format!("Database connection failed: {}", e))?;

        // Run migrations
        sqlx::migrate!("./migrations").run(&db).await
            .map_err(|e| format!("Migration failed: {}", e))?;

        Ok(Self { db, encryption })
    }

    pub async fn save_cipher(&self, cipher: &CipherData) -> Result<(), String> {
        let mut tx = self.db.begin().await
            .map_err(|e| format!("Transaction start failed: {}", e))?;

        // Encrypt sensitive fields
        let encrypted_name = self.encryption.encrypt_string(&cipher.name, &cipher.user_id).await?;
        let encrypted_notes = if let Some(notes) = &cipher.notes {
            Some(self.encryption.encrypt_string(notes, &cipher.user_id).await?)
        } else {
            None
        };

        // Convert encrypted data to storage format
        let name_blob = serde_json::to_string(&encrypted_name)
            .map_err(|e| format!("Name serialization failed: {}", e))?;
        let notes_blob = if let Some(enc_notes) = encrypted_notes {
            Some(serde_json::to_string(&enc_notes)
                .map_err(|e| format!("Notes serialization failed: {}", e))?)
        } else {
            None
        };

        sqlx::query!(
            r#"
            INSERT OR REPLACE INTO ciphers (
                id, user_id, organization_id, type, name, notes,
                login_data, card_data, identity_data, secure_note_data, ssh_key_data,
                fields, attachments, password_history,
                revision_date, creation_date, deleted_date,
                favorite, folder_id, collection_ids, reprompt
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14,
                ?15, ?16, ?17, ?18, ?19, ?20, ?21
            )
            "#,
            cipher.id,
            cipher.user_id,
            cipher.organization_id,
            cipher.cipher_type,
            name_blob,
            notes_blob,
            cipher.login_data,
            cipher.card_data,
            cipher.identity_data,
            cipher.secure_note_data,
            cipher.ssh_key_data,
            cipher.fields,
            cipher.attachments,
            cipher.password_history,
            cipher.revision_date,
            cipher.creation_date,
            cipher.deleted_date,
            cipher.favorite,
            cipher.folder_id,
            cipher.collection_ids,
            cipher.reprompt
        )
        .execute(&mut *tx)
        .await
        .map_err(|e| format!("Cipher insert failed: {}", e))?;

        tx.commit().await
            .map_err(|e| format!("Transaction commit failed: {}", e))?;

        Ok(())
    }

    pub async fn get_ciphers(&self, user_id: &str) -> Result<Vec<CipherData>, String> {
        let rows = sqlx::query!(
            "SELECT * FROM ciphers WHERE user_id = ?1 AND deleted_date IS NULL ORDER BY name",
            user_id
        )
        .fetch_all(&self.db)
        .await
        .map_err(|e| format!("Cipher query failed: {}", e))?;

        let mut ciphers = Vec::new();

        for row in rows {
            // Decrypt sensitive fields
            let encrypted_name: EncryptedData = serde_json::from_str(&row.name)
                .map_err(|e| format!("Name deserialization failed: {}", e))?;
            let decrypted_name = self.encryption.decrypt_string(&encrypted_name, user_id).await?;

            let decrypted_notes = if let Some(notes_blob) = row.notes {
                let encrypted_notes: EncryptedData = serde_json::from_str(&notes_blob)
                    .map_err(|e| format!("Notes deserialization failed: {}", e))?;
                Some(self.encryption.decrypt_string(&encrypted_notes, user_id).await?)
            } else {
                None
            };

            ciphers.push(CipherData {
                id: row.id,
                user_id: row.user_id,
                organization_id: row.organization_id,
                cipher_type: row.r#type,
                name: decrypted_name,
                notes: decrypted_notes,
                login_data: row.login_data,
                card_data: row.card_data,
                identity_data: row.identity_data,
                secure_note_data: row.secure_note_data,
                ssh_key_data: row.ssh_key_data,
                fields: row.fields,
                attachments: row.attachments,
                password_history: row.password_history,
                revision_date: row.revision_date,
                creation_date: row.creation_date,
                deleted_date: row.deleted_date,
                favorite: row.favorite,
                folder_id: row.folder_id,
                collection_ids: row.collection_ids,
                reprompt: row.reprompt,
            });
        }

        Ok(ciphers)
    }

    pub async fn delete_cipher(&self, cipher_id: &str, user_id: &str) -> Result<(), String> {
        sqlx::query!(
            "UPDATE ciphers SET deleted_date = CURRENT_TIMESTAMP WHERE id = ?1 AND user_id = ?2",
            cipher_id,
            user_id
        )
        .execute(&self.db)
        .await
        .map_err(|e| format!("Cipher deletion failed: {}", e))?;

        Ok(())
    }
}
```

### 5. Tauri Commands

```rust
// src-tauri/src/commands/vault.rs
use tauri::State;
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct AppState {
    pub vault_storage: Arc<Mutex<VaultStorage>>,
}

#[tauri::command]
pub async fn save_cipher(
    cipher: CipherData,
    state: State<'_, AppState>
) -> Result<(), String> {
    let storage = state.vault_storage.lock().await;
    storage.save_cipher(&cipher).await
}

#[tauri::command]
pub async fn get_ciphers(
    user_id: String,
    state: State<'_, AppState>
) -> Result<Vec<CipherData>, String> {
    let storage = state.vault_storage.lock().await;
    storage.get_ciphers(&user_id).await
}

#[tauri::command]
pub async fn delete_cipher(
    cipher_id: String,
    user_id: String,
    state: State<'_, AppState>
) -> Result<(), String> {
    let storage = state.vault_storage.lock().await;
    storage.delete_cipher(&cipher_id, &user_id).await
}

#[tauri::command]
pub async fn search_ciphers(
    user_id: String,
    query: String,
    state: State<'_, AppState>
) -> Result<Vec<CipherData>, String> {
    let storage = state.vault_storage.lock().await;
    let all_ciphers = storage.get_ciphers(&user_id).await?;

    // Simple text search (can be enhanced with full-text search)
    let filtered: Vec<CipherData> = all_ciphers
        .into_iter()
        .filter(|cipher| {
            cipher.name.to_lowercase().contains(&query.to_lowercase()) ||
            cipher.notes.as_ref()
                .map(|notes| notes.to_lowercase().contains(&query.to_lowercase()))
                .unwrap_or(false)
        })
        .collect();

    Ok(filtered)
}
```

### 6. Frontend Integration (SolidJS)

```typescript
// src/services/vault.service.ts
import { invoke } from '@tauri-apps/api/tauri';

export interface CipherData {
  id: string;
  user_id: string;
  organization_id?: string;
  cipher_type: number;
  name: string;
  notes?: string;
  login_data?: string;
  card_data?: string;
  identity_data?: string;
  secure_note_data?: string;
  ssh_key_data?: string;
  fields?: string;
  attachments?: string;
  password_history?: string;
  revision_date: string;
  creation_date: string;
  deleted_date?: string;
  favorite: boolean;
  folder_id?: string;
  collection_ids?: string;
  reprompt: number;
}

export class VaultService {
  async saveCipher(cipher: CipherData): Promise<void> {
    return await invoke('save_cipher', { cipher });
  }

  async getCiphers(userId: string): Promise<CipherData[]> {
    return await invoke('get_ciphers', { userId });
  }

  async deleteCipher(cipherId: string, userId: string): Promise<void> {
    return await invoke('delete_cipher', { cipherId, userId });
  }

  async searchCiphers(userId: string, query: string): Promise<CipherData[]> {
    return await invoke('search_ciphers', { userId, query });
  }
}
```

## Security Best Practices

### 1. Key Management
- **Never store master keys unencrypted**
- **Use Stronghold for all critical secrets**
- **Implement key rotation policies**
- **Use hardware security modules when available**

### 2. Data Protection
- **Encrypt all sensitive data at rest**
- **Use authenticated encryption (AES-GCM or AES-CBC + HMAC)**
- **Implement secure memory handling**
- **Clear sensitive data from memory after use**

### 3. Access Control
- **Implement proper user authentication**
- **Use session management with timeouts**
- **Implement vault locking mechanisms**
- **Audit all access attempts**

### 4. Database Security
- **Use parameterized queries to prevent SQL injection**
- **Implement database-level encryption**
- **Regular database backups with encryption**
- **Monitor for unauthorized access**

## Performance Considerations

### 1. Caching Strategy
- **Cache decrypted data in memory during active sessions**
- **Implement LRU cache for frequently accessed items**
- **Clear cache on vault lock/logout**

### 2. Database Optimization
- **Use appropriate indices for common queries**
- **Implement pagination for large datasets**
- **Use connection pooling**
- **Regular database maintenance**

### 3. Encryption Performance
- **Use hardware acceleration when available**
- **Batch encrypt/decrypt operations**
- **Consider async encryption for large datasets**

## Backup and Recovery

### 1. Data Backup
- **Encrypted database backups**
- **Stronghold vault backups**
- **Incremental backup strategies**
- **Cross-platform backup compatibility**

### 2. Disaster Recovery
- **Key recovery mechanisms**
- **Data integrity verification**
- **Rollback procedures**
- **Emergency access protocols**

## Migration and Upgrades

### 1. Schema Migrations
- **Version-controlled database migrations**
- **Backward compatibility considerations**
- **Data validation after migrations**
- **Rollback capabilities**

### 2. Encryption Upgrades
- **Support for multiple encryption versions**
- **Gradual migration strategies**
- **Key format upgrades**
- **Algorithm transitions**

## Conclusion

This hybrid architecture provides the optimal balance of security, performance, and functionality for a Tauri-based password manager. By leveraging Stronghold for critical key management and SQLite for efficient data storage, you achieve enterprise-grade security while maintaining excellent user experience.

The implementation follows Bitwarden's proven security model while adapting it for the Tauri ecosystem's unique capabilities and constraints.
