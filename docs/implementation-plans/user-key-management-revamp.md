# ChiikaWarden User Key Management System Revamp

## Overview

This document outlines a comprehensive implementation plan to revamp ChiikaWarden's user key management system to follow Bitwarden desktop client patterns and eliminate MAC verification failures. This is a **breaking change implementation** that will require users to re-authenticate and potentially re-sync their vault data.

## Current Issues

1. **MAC Verification Failures**: The `derive_user_key_consistently` function falls back to stretching the master key when server-provided encrypted user keys fail to decrypt, creating incompatible "User Key B" instead of proper "User Key A"
2. **Missing Device Trust**: No device trust system with RSA key pairs for trusted devices
3. **No WebAuthn PRF Support**: Missing WebAuthn Pseudo-Random Function key handling
4. **Incomplete Key Hierarchy**: Lacks proper Master Key → User Key → Device Key → Organization Key hierarchy
5. **Limited Security Features**: Missing key rotation, memory clearing, and comprehensive audit logging

## Implementation Plan

### Phase 1: Fix MAC Verification & Core Key Management (Week 1-2)

#### Database Schema Breaking Changes

**New Migration: `002_breaking_key_management_revamp.sql`**

```sql
-- Drop existing problematic columns and add new key management structure
ALTER TABLE users DROP COLUMN encrypted_private_key;
ALTER TABLE users DROP COLUMN encrypted_user_key;

-- Add new key management columns
ALTER TABLE users ADD COLUMN encrypted_private_key_new TEXT;
ALTER TABLE users ADD COLUMN encrypted_user_key_new TEXT;
ALTER TABLE users ADD COLUMN key_derivation_method TEXT DEFAULT 'server_provided';
ALTER TABLE users ADD COLUMN device_trust_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN webauthn_enabled BOOLEAN DEFAULT FALSE;

-- Trusted devices table
CREATE TABLE trusted_devices (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_identifier TEXT NOT NULL UNIQUE,
    device_name TEXT,
    device_type TEXT DEFAULT 'desktop',
    encrypted_device_public_key TEXT NOT NULL,
    encrypted_device_private_key TEXT NOT NULL,
    encrypted_user_key TEXT NOT NULL,
    device_key_encrypted TEXT NOT NULL,
    trust_established_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_used_at DATETIME,
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- WebAuthn credentials table
CREATE TABLE webauthn_credentials (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    credential_id TEXT NOT NULL UNIQUE,
    public_key TEXT NOT NULL,
    counter INTEGER DEFAULT 0,
    prf_salt TEXT,
    name TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_used_at DATETIME,
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Key operation audit log
CREATE TABLE key_operations_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    operation_type TEXT NOT NULL, -- 'derive', 'rotate', 'validate', 'device_trust', 'webauthn'
    operation_method TEXT NOT NULL, -- 'server_key', 'device_trust', 'webauthn_prf'
    success BOOLEAN NOT NULL,
    error_code TEXT,
    error_message TEXT,
    correlation_id TEXT NOT NULL,
    duration_ms INTEGER,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Organization keys table
CREATE TABLE organization_keys (
    id TEXT PRIMARY KEY,
    organization_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    encrypted_organization_key TEXT NOT NULL,
    key_type TEXT DEFAULT 'organization', -- 'organization', 'collection'
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Indexes
CREATE INDEX idx_trusted_devices_user_id ON trusted_devices(user_id);
CREATE INDEX idx_trusted_devices_device_identifier ON trusted_devices(device_identifier);
CREATE INDEX idx_webauthn_credentials_user_id ON webauthn_credentials(user_id);
CREATE INDEX idx_webauthn_credentials_credential_id ON webauthn_credentials(credential_id);
CREATE INDEX idx_key_operations_log_user_id ON key_operations_log(user_id);
CREATE INDEX idx_key_operations_log_timestamp ON key_operations_log(timestamp);
CREATE INDEX idx_organization_keys_user_id ON organization_keys(user_id);
CREATE INDEX idx_organization_keys_org_id ON organization_keys(organization_id);
```

#### Core Files to Rewrite

**1. `src-tauri/src/crypto/encryption.rs` - Complete Rewrite**

```rust
use crate::crypto::{CryptoResult, CryptoError, UserKey, MasterKey};
use crate::crypto::cipher_crypto::EncryptedString;
use crate::models::CorrelationId;
use tracing::{debug, info, error, warn};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Secure key derivation service following Bitwarden desktop client patterns
pub struct KeyDerivationService;

impl KeyDerivationService {
    /// Derive user key from server-provided encrypted user key (BREAKING CHANGE)
    /// This function no longer falls back to master key stretching
    pub fn derive_user_key_from_server(
        encrypted_user_key_b64: &str,
        master_key: &MasterKey,
        user_id: &str,
        correlation_id: &CorrelationId,
    ) -> CryptoResult<UserKey> {
        debug!(
            user_id = user_id,
            correlation_id = %correlation_id,
            encrypted_key_preview = &encrypted_user_key_b64[..std::cmp::min(50, encrypted_user_key_b64.len())],
            "[key_derivation] Starting server-provided user key derivation"
        );

        // Parse encrypted string with strict validation
        let encrypted_string = EncryptedString::from_string(encrypted_user_key_b64)
            .map_err(|e| {
                error!(
                    user_id = user_id,
                    correlation_id = %correlation_id,
                    error = %e,
                    "[key_derivation] Invalid encrypted user key format from server"
                );
                CryptoError::InvalidFormat(format!("Invalid encrypted user key format: {}", e))
            })?;

        // Decrypt with comprehensive error handling
        let user_key = Self::decrypt_user_key_with_master_key(&encrypted_string, master_key)
            .map_err(|e| {
                error!(
                    user_id = user_id,
                    correlation_id = %correlation_id,
                    error = %e,
                    "[key_derivation] Failed to decrypt server-provided user key - MAC verification failed"
                );
                e
            })?;

        info!(
            user_id = user_id,
            correlation_id = %correlation_id,
            user_key_len = user_key.as_bytes().len(),
            "[key_derivation] Successfully derived user key from server"
        );

        Ok(user_key)
    }

    /// Decrypt user key using master key with proper MAC verification
    fn decrypt_user_key_with_master_key(
        encrypted_string: &EncryptedString,
        master_key: &MasterKey,
    ) -> CryptoResult<UserKey> {
        let decrypted_bytes = crate::crypto::cipher_crypto::CipherCrypto::decrypt_bytes(
            encrypted_string,
            master_key.as_bytes(),
        )?;

        Ok(UserKey::new(decrypted_bytes))
    }

    /// Generate new user key (for new accounts)
    pub fn generate_new_user_key() -> CryptoResult<UserKey> {
        crate::crypto::keys::KeyService::generate_user_key()
    }
}
```

**2. `src-tauri/src/models/user.rs` - Breaking Changes**

```rust
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use specta::Type;

/// User model with new key management structure (BREAKING CHANGE)
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct User {
    pub id: String,
    pub email: String,
    pub master_key_hash: Option<String>,
    // BREAKING: Removed old encrypted_private_key and encrypted_user_key
    pub encrypted_private_key_new: Option<String>,
    pub encrypted_user_key_new: Option<String>,
    pub key_derivation_method: String, // 'server_provided', 'device_trust', 'webauthn_prf'
    pub device_trust_enabled: bool,
    pub webauthn_enabled: bool,
    pub server_provider_id: String,
    pub kdf_type: i32,
    pub kdf_iterations: i32,
    pub kdf_memory: Option<i32>,
    pub kdf_parallelism: Option<i32>,
    pub created_date: DateTime<Utc>,
    pub revision_date: DateTime<Utc>,
}

/// Device trust information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct TrustedDevice {
    pub id: String,
    pub user_id: String,
    pub device_identifier: String,
    pub device_name: Option<String>,
    pub device_type: String,
    pub encrypted_device_public_key: String,
    pub encrypted_device_private_key: String,
    pub encrypted_user_key: String,
    pub device_key_encrypted: String,
    pub trust_established_at: DateTime<Utc>,
    pub last_used_at: Option<DateTime<Utc>>,
    pub is_active: bool,
}

/// WebAuthn credential information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct WebAuthnCredential {
    pub id: String,
    pub user_id: String,
    pub credential_id: String,
    pub public_key: String,
    pub counter: i32,
    pub prf_salt: Option<String>,
    pub name: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_used_at: Option<DateTime<Utc>>,
    pub is_active: bool,
}
```

### Phase 2: Device Trust System Implementation (Week 3-4)

#### New Files to Create

**1. `src-tauri/src/crypto/device_trust.rs`**

```rust
use crate::crypto::{CryptoResult, CryptoError, UserKey, MasterKey};
use crate::models::user::TrustedDevice;
use crate::models::CorrelationId;
use ring::signature::{RsaKeyPair, RSA_PKCS1_SHA256};
use ring::rand::SystemRandom;
use tracing::{debug, info, error};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Device trust service following Bitwarden desktop client patterns
pub struct DeviceTrustService;

impl DeviceTrustService {
    /// Generate RSA key pair for device trust (2048-bit)
    pub fn generate_device_key_pair() -> CryptoResult<(Vec<u8>, Vec<u8>)> {
        let rng = SystemRandom::new();
        let key_pair = RsaKeyPair::generate_pkcs8(&rng, 2048)
            .map_err(|e| CryptoError::KeyGeneration(format!("RSA key generation failed: {:?}", e)))?;

        let private_key = key_pair.private_key().as_ref().to_vec();
        let public_key = key_pair.public_key().as_ref().to_vec();

        Ok((private_key, public_key))
    }

    /// Establish device trust following Bitwarden patterns
    pub async fn establish_device_trust(
        user_id: &str,
        user_key: &UserKey,
        device_name: Option<String>,
        correlation_id: &CorrelationId,
    ) -> CryptoResult<TrustedDevice> {
        info!(
            user_id = user_id,
            correlation_id = %correlation_id,
            "[device_trust] Starting device trust establishment"
        );

        // 1. Generate device key (512-bit symmetric key)
        let device_key = crate::crypto::encryption::EncryptionService::generate_key(64)?;

        // 2. Generate RSA key pair (2048-bit)
        let (device_private_key, device_public_key) = Self::generate_device_key_pair()?;

        // 3. Encrypt user key with device public key (encapsulation)
        let encrypted_user_key = Self::encapsulate_user_key_with_public_key(
            user_key,
            &device_public_key,
        )?;

        // 4. Encrypt device public key with user key
        let encrypted_device_public_key = crate::crypto::encryption::EncryptionService::encrypt(
            &device_public_key,
            user_key.as_bytes(),
            crate::crypto::EncryptionType::AesCbc256HmacSha256B64,
        )?;

        // 5. Encrypt device private key with device key
        let encrypted_device_private_key = crate::crypto::encryption::EncryptionService::encrypt(
            &device_private_key,
            &device_key,
            crate::crypto::EncryptionType::AesCbc256HmacSha256B64,
        )?;

        // 6. Create device identifier
        let device_identifier = Self::generate_device_identifier()?;

        let trusted_device = TrustedDevice {
            id: uuid::Uuid::new_v4().to_string(),
            user_id: user_id.to_string(),
            device_identifier,
            device_name,
            device_type: "desktop".to_string(),
            encrypted_device_public_key: serde_json::to_string(&encrypted_device_public_key)?,
            encrypted_device_private_key: serde_json::to_string(&encrypted_device_private_key)?,
            encrypted_user_key: encrypted_user_key,
            device_key_encrypted: base64::encode(&device_key),
            trust_established_at: chrono::Utc::now(),
            last_used_at: None,
            is_active: true,
        };

        info!(
            user_id = user_id,
            device_id = trusted_device.id,
            correlation_id = %correlation_id,
            "[device_trust] Device trust established successfully"
        );

        Ok(trusted_device)
    }

    /// Decrypt user key using device trust
    pub async fn decrypt_user_key_with_device_key(
        device: &TrustedDevice,
        device_key: &[u8],
        correlation_id: &CorrelationId,
    ) -> CryptoResult<UserKey> {
        debug!(
            user_id = device.user_id,
            device_id = device.id,
            correlation_id = %correlation_id,
            "[device_trust] Starting user key decryption with device key"
        );

        // 1. Decrypt device private key using device key
        let encrypted_device_private_key: crate::crypto::EncryptedData =
            serde_json::from_str(&device.encrypted_device_private_key)?;

        let device_private_key = crate::crypto::encryption::EncryptionService::decrypt(
            &encrypted_device_private_key,
            device_key,
            crate::crypto::EncryptionType::AesCbc256HmacSha256B64,
        )?;

        // 2. Decapsulate user key using device private key
        let user_key = Self::decapsulate_user_key_with_private_key(
            &device.encrypted_user_key,
            &device_private_key,
        )?;

        info!(
            user_id = device.user_id,
            device_id = device.id,
            correlation_id = %correlation_id,
            "[device_trust] User key decrypted successfully using device trust"
        );

        Ok(user_key)
    }

    /// Rotate device trust keys when master password changes
    pub async fn rotate_device_trust_keys(
        device: &mut TrustedDevice,
        old_user_key: &UserKey,
        new_user_key: &UserKey,
        correlation_id: &CorrelationId,
    ) -> CryptoResult<()> {
        info!(
            user_id = device.user_id,
            device_id = device.id,
            correlation_id = %correlation_id,
            "[device_trust] Starting device trust key rotation"
        );

        // 1. Decrypt device public key with old user key
        let encrypted_device_public_key: crate::crypto::EncryptedData =
            serde_json::from_str(&device.encrypted_device_public_key)?;

        let device_public_key = crate::crypto::encryption::EncryptionService::decrypt(
            &encrypted_device_public_key,
            old_user_key.as_bytes(),
            crate::crypto::EncryptionType::AesCbc256HmacSha256B64,
        )?;

        // 2. Encrypt new user key with device public key
        device.encrypted_user_key = Self::encapsulate_user_key_with_public_key(
            new_user_key,
            &device_public_key,
        )?;

        // 3. Re-encrypt device public key with new user key
        let new_encrypted_device_public_key = crate::crypto::encryption::EncryptionService::encrypt(
            &device_public_key,
            new_user_key.as_bytes(),
            crate::crypto::EncryptionType::AesCbc256HmacSha256B64,
        )?;

        device.encrypted_device_public_key = serde_json::to_string(&new_encrypted_device_public_key)?;

        info!(
            user_id = device.user_id,
            device_id = device.id,
            correlation_id = %correlation_id,
            "[device_trust] Device trust key rotation completed successfully"
        );

        Ok(())
    }

    // Private helper methods
    fn generate_device_identifier() -> CryptoResult<String> {
        // Generate unique device identifier
        Ok(format!("chiikawarden-{}", uuid::Uuid::new_v4()))
    }

    fn encapsulate_user_key_with_public_key(
        user_key: &UserKey,
        device_public_key: &[u8],
    ) -> CryptoResult<String> {
        // Implementation for RSA key encapsulation
        todo!("Implement RSA key encapsulation")
    }

    fn decapsulate_user_key_with_private_key(
        encrypted_user_key: &str,
        device_private_key: &[u8],
    ) -> CryptoResult<UserKey> {
        // Implementation for RSA key decapsulation
        todo!("Implement RSA key decapsulation")
    }
}
```

**2. `src-tauri/src/crypto/webauthn.rs`**

```rust
use crate::crypto::{CryptoResult, CryptoError, UserKey};
use crate::models::user::WebAuthnCredential;
use crate::models::CorrelationId;
use tracing::{debug, info, error};

/// WebAuthn service with PRF support following Bitwarden patterns
pub struct WebAuthnService;

impl WebAuthnService {
    /// Derive user key from WebAuthn PRF
    pub async fn derive_user_key_from_prf(
        prf_key: &[u8],
        encrypted_private_key: &str,
        encrypted_user_key: &str,
        correlation_id: &CorrelationId,
    ) -> CryptoResult<UserKey> {
        debug!(
            correlation_id = %correlation_id,
            prf_key_len = prf_key.len(),
            "[webauthn] Starting user key derivation from PRF"
        );

        // 1. Decrypt private key using PRF key
        let encrypted_private_key_data: crate::crypto::EncryptedData =
            serde_json::from_str(encrypted_private_key)?;

        let private_key = crate::crypto::encryption::EncryptionService::decrypt(
            &encrypted_private_key_data,
            prf_key,
            crate::crypto::EncryptionType::AesCbc256HmacSha256B64,
        )?;

        // 2. Decapsulate user key using private key
        let user_key = Self::decapsulate_user_key_unsigned(&encrypted_user_key, &private_key)?;

        info!(
            correlation_id = %correlation_id,
            "[webauthn] User key derived successfully from WebAuthn PRF"
        );

        Ok(user_key)
    }

    /// Setup WebAuthn credential with PRF
    pub async fn setup_webauthn_credential(
        user_id: &str,
        challenge: &[u8],
        credential_name: String,
        correlation_id: &CorrelationId,
    ) -> CryptoResult<WebAuthnCredential> {
        info!(
            user_id = user_id,
            correlation_id = %correlation_id,
            "[webauthn] Starting WebAuthn credential setup"
        );

        // Implementation for WebAuthn credential creation
        // This would integrate with system WebAuthn APIs
        todo!("Implement WebAuthn credential setup with PRF")
    }

    /// Authenticate using WebAuthn and derive PRF key
    pub async fn authenticate_and_get_prf_key(
        credential: &WebAuthnCredential,
        challenge: &[u8],
        correlation_id: &CorrelationId,
    ) -> CryptoResult<Vec<u8>> {
        debug!(
            user_id = credential.user_id,
            credential_id = credential.credential_id,
            correlation_id = %correlation_id,
            "[webauthn] Starting WebAuthn authentication for PRF key"
        );

        // Implementation for WebAuthn authentication and PRF key extraction
        todo!("Implement WebAuthn authentication with PRF key extraction")
    }

    // Private helper methods
    fn decapsulate_user_key_unsigned(
        encrypted_user_key: &str,
        private_key: &[u8],
    ) -> CryptoResult<UserKey> {
        // Implementation for unsigned key decapsulation
        todo!("Implement unsigned key decapsulation")
    }
}
```

### Phase 3: Security & Memory Management (Week 5-6)

#### Enhanced Security Features

**1. `src-tauri/src/crypto/secure_memory.rs`**

```rust
use zeroize::{Zeroize, ZeroizeOnDrop};
use std::ops::{Deref, DerefMut};

/// Secure wrapper for sensitive data that automatically zeroizes on drop
#[derive(ZeroizeOnDrop)]
pub struct SecureBytes(Vec<u8>);

impl SecureBytes {
    pub fn new(data: Vec<u8>) -> Self {
        Self(data)
    }

    pub fn from_slice(data: &[u8]) -> Self {
        Self(data.to_vec())
    }

    pub fn as_slice(&self) -> &[u8] {
        &self.0
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// Constant-time comparison for security
    pub fn constant_time_eq(&self, other: &Self) -> bool {
        use subtle::ConstantTimeEq;
        self.0.ct_eq(&other.0).into()
    }
}

impl Deref for SecureBytes {
    type Target = [u8];

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for SecureBytes {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

/// Secure wrapper for keys that implements proper zeroization
#[derive(ZeroizeOnDrop)]
pub struct SecureKey {
    key_data: SecureBytes,
    key_type: String,
}

impl SecureKey {
    pub fn new(key_data: Vec<u8>, key_type: String) -> Self {
        Self {
            key_data: SecureBytes::new(key_data),
            key_type,
        }
    }

    pub fn as_bytes(&self) -> &[u8] {
        self.key_data.as_slice()
    }

    pub fn key_type(&self) -> &str {
        &self.key_type
    }

    pub fn len(&self) -> usize {
        self.key_data.len()
    }
}

/// Trait for secure key operations
pub trait SecureKeyOps {
    fn zeroize_on_drop(&mut self);
    fn constant_time_eq(&self, other: &Self) -> bool;
}

impl SecureKeyOps for SecureKey {
    fn zeroize_on_drop(&mut self) {
        // Zeroization is handled by ZeroizeOnDrop derive
    }

    fn constant_time_eq(&self, other: &Self) -> bool {
        self.key_data.constant_time_eq(&other.key_data)
    }
}
```

**2. `src-tauri/src/crypto/key_validation.rs`**

```rust
use crate::crypto::{CryptoResult, CryptoError, UserKey};
use crate::storage::Database;
use crate::models::CorrelationId;
use tracing::{debug, info, warn, error};

/// Key validation service for ensuring key compatibility
pub struct KeyValidationService;

impl KeyValidationService {
    /// Validate user key against existing ciphers (BREAKING CHANGE)
    /// This function now requires ALL sample ciphers to decrypt successfully
    pub async fn validate_user_key_against_ciphers(
        user_key: &UserKey,
        user_id: &str,
        database: &Database,
        correlation_id: &CorrelationId,
    ) -> CryptoResult<bool> {
        debug!(
            user_id = user_id,
            correlation_id = %correlation_id,
            "[key_validation] Starting user key validation against existing ciphers"
        );

        // Get sample of existing ciphers for validation
        let sample_ciphers = database
            .get_sample_ciphers_for_user(user_id, 10)
            .await
            .map_err(|e| CryptoError::Database(format!("Failed to get sample ciphers: {}", e)))?;

        if sample_ciphers.is_empty() {
            info!(
                user_id = user_id,
                correlation_id = %correlation_id,
                "[key_validation] No existing ciphers found - key validation passed"
            );
            return Ok(true);
        }

        let mut successful_decryptions = 0;
        let total_ciphers = sample_ciphers.len();

        for (index, cipher) in sample_ciphers.iter().enumerate() {
            match crate::crypto::cipher_crypto::CipherCrypto::decrypt_string(
                &cipher.encrypted_data,
                user_key,
            ) {
                Ok(_) => {
                    successful_decryptions += 1;
                    debug!(
                        user_id = user_id,
                        cipher_id = cipher.id,
                        cipher_index = index,
                        correlation_id = %correlation_id,
                        "[key_validation] Cipher decryption successful"
                    );
                }
                Err(e) => {
                    error!(
                        user_id = user_id,
                        cipher_id = cipher.id,
                        cipher_index = index,
                        error = %e,
                        correlation_id = %correlation_id,
                        "[key_validation] Cipher decryption failed - key validation failed"
                    );
                    return Ok(false);
                }
            }
        }

        let validation_success = successful_decryptions == total_ciphers;

        if validation_success {
            info!(
                user_id = user_id,
                successful_decryptions = successful_decryptions,
                total_ciphers = total_ciphers,
                correlation_id = %correlation_id,
                "[key_validation] User key validation passed - all ciphers decrypt successfully"
            );
        } else {
            warn!(
                user_id = user_id,
                successful_decryptions = successful_decryptions,
                total_ciphers = total_ciphers,
                correlation_id = %correlation_id,
                "[key_validation] User key validation failed - not all ciphers decrypt"
            );
        }

        Ok(validation_success)
    }

    /// Validate organization key against organization ciphers
    pub async fn validate_organization_key(
        organization_key: &[u8],
        organization_id: &str,
        user_id: &str,
        database: &Database,
        correlation_id: &CorrelationId,
    ) -> CryptoResult<bool> {
        debug!(
            user_id = user_id,
            organization_id = organization_id,
            correlation_id = %correlation_id,
            "[key_validation] Starting organization key validation"
        );

        // Get sample organization ciphers
        let org_ciphers = database
            .get_sample_organization_ciphers(organization_id, 5)
            .await
            .map_err(|e| CryptoError::Database(format!("Failed to get org ciphers: {}", e)))?;

        if org_ciphers.is_empty() {
            info!(
                user_id = user_id,
                organization_id = organization_id,
                correlation_id = %correlation_id,
                "[key_validation] No organization ciphers found - validation passed"
            );
            return Ok(true);
        }

        for cipher in org_ciphers {
            match crate::crypto::cipher_crypto::CipherCrypto::decrypt_string(
                &cipher.encrypted_data,
                &crate::crypto::UserKey::new(organization_key.to_vec()),
            ) {
                Ok(_) => continue,
                Err(_) => {
                    error!(
                        user_id = user_id,
                        organization_id = organization_id,
                        cipher_id = cipher.id,
                        correlation_id = %correlation_id,
                        "[key_validation] Organization cipher decryption failed"
                    );
                    return Ok(false);
                }
            }
        }

        info!(
            user_id = user_id,
            organization_id = organization_id,
            correlation_id = %correlation_id,
            "[key_validation] Organization key validation passed"
        );

        Ok(true)
    }
}
```

### Phase 4: API Integration & Commands (Week 7-8)

#### Breaking Changes to Authentication Commands

**1. `src-tauri/src/commands/auth.rs` - Major Rewrite**

```rust
use tauri::{command, State};
use specta::specta;
use serde::{Deserialize, Serialize};
use crate::models::{CorrelationId, user::{User, TrustedDevice, WebAuthnCredential}};
use crate::error::{AppError, AppResult};
use crate::AppState;
use tracing::{debug, info, error, warn};

/// Enhanced login request supporting multiple authentication methods
#[derive(Debug, Serialize, Deserialize, specta::Type)]
pub struct EnhancedLoginRequest {
    pub email: String,
    pub password: Option<String>, // Optional for device trust/WebAuthn flows
    pub authentication_method: AuthenticationMethod,
    pub device_identifier: Option<String>, // For device trust
    pub webauthn_assertion: Option<WebAuthnAssertion>, // For WebAuthn PRF
    pub kdf_config: crate::crypto::KdfConfig,
}

/// Authentication methods (BREAKING CHANGE)
#[derive(Debug, Serialize, Deserialize, specta::Type)]
pub enum AuthenticationMethod {
    Password,
    DeviceTrust,
    WebAuthnPrf,
    Hybrid, // Combination of methods
}

/// WebAuthn assertion data
#[derive(Debug, Serialize, Deserialize, specta::Type)]
pub struct WebAuthnAssertion {
    pub credential_id: String,
    pub assertion_response: String,
    pub prf_key: Vec<u8>,
}

/// Enhanced login response with multiple key sources
#[derive(Debug, Serialize, Deserialize, specta::Type)]
pub struct EnhancedLoginResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub user_id: String,
    pub authentication_method_used: AuthenticationMethod,
    pub device_trust_available: bool,
    pub webauthn_available: bool,
    pub requires_key_rotation: bool,
}

/// Enhanced login command (BREAKING CHANGE)
#[command]
#[specta]
pub async fn enhanced_login(
    request: EnhancedLoginRequest,
    state: State<'_, AppState>,
) -> Result<EnhancedLoginResponse, AppError> {
    let correlation_id = CorrelationId::new();

    info!(
        email = request.email,
        auth_method = ?request.authentication_method,
        correlation_id = %correlation_id,
        "[auth_flow] Starting enhanced login with new key management system"
    );

    match request.authentication_method {
        AuthenticationMethod::Password => {
            handle_password_authentication(request, &state, &correlation_id).await
        }
        AuthenticationMethod::DeviceTrust => {
            handle_device_trust_authentication(request, &state, &correlation_id).await
        }
        AuthenticationMethod::WebAuthnPrf => {
            handle_webauthn_prf_authentication(request, &state, &correlation_id).await
        }
        AuthenticationMethod::Hybrid => {
            handle_hybrid_authentication(request, &state, &correlation_id).await
        }
    }
}

/// Handle traditional password authentication (BREAKING CHANGE)
async fn handle_password_authentication(
    request: EnhancedLoginRequest,
    state: &State<'_, AppState>,
    correlation_id: &CorrelationId,
) -> Result<EnhancedLoginResponse, AppError> {
    let password = request.password.ok_or_else(|| AppError::AuthenticationError {
        message: "Password required for password authentication".to_string(),
    })?;

    debug!(
        email = request.email,
        correlation_id = %correlation_id,
        "[auth_flow] Processing password authentication with new key derivation"
    );

    // Step 1: Derive master key
    let master_key = state
        .auth_service()
        .derive_master_key(&password, &request.email, request.kdf_config.iterations)
        .await?;

    // Step 2: Authenticate with API
    let api_response = authenticate_with_api(&request, &master_key, state).await?;

    // Step 3: Derive user key using NEW method (no fallback)
    let user_key = crate::crypto::encryption::KeyDerivationService::derive_user_key_from_server(
        &api_response.encrypted_user_key.ok_or_else(|| AppError::AuthenticationError {
            message: "Server did not provide encrypted user key".to_string(),
        })?,
        &master_key,
        &api_response.user_id,
        correlation_id,
    ).map_err(|e| {
        error!(
            email = request.email,
            user_id = api_response.user_id,
            error = %e,
            correlation_id = %correlation_id,
            "[auth_flow] CRITICAL: User key derivation failed - this is a breaking change"
        );
        AppError::AuthenticationError {
            message: "Failed to derive user key from server response. Please contact support.".to_string(),
        }
    })?;

    // Step 4: Validate user key against existing ciphers (BREAKING CHANGE)
    let key_validation_passed = crate::crypto::key_validation::KeyValidationService::validate_user_key_against_ciphers(
        &user_key,
        &api_response.user_id,
        &state.database,
        correlation_id,
    ).await?;

    if !key_validation_passed {
        error!(
            email = request.email,
            user_id = api_response.user_id,
            correlation_id = %correlation_id,
            "[auth_flow] CRITICAL: User key validation failed - existing ciphers cannot be decrypted"
        );
        return Err(AppError::AuthenticationError {
            message: "User key validation failed. Your vault data may be inaccessible.".to_string(),
        });
    }

    // Step 5: Store user and cache user key
    store_authenticated_user(&api_response, &request, &user_key, state, correlation_id).await?;

    info!(
        email = request.email,
        user_id = api_response.user_id,
        correlation_id = %correlation_id,
        "[auth_flow] Password authentication completed successfully with new key management"
    );

    Ok(EnhancedLoginResponse {
        access_token: api_response.access_token,
        refresh_token: api_response.refresh_token,
        user_id: api_response.user_id,
        authentication_method_used: AuthenticationMethod::Password,
        device_trust_available: false, // Will be enabled in device trust setup
        webauthn_available: false,     // Will be enabled in WebAuthn setup
        requires_key_rotation: false,
    })
}
```

## Breaking Changes Summary

### Database Schema Changes
- **BREAKING**: Drop `encrypted_private_key` and `encrypted_user_key` columns from users table
- **NEW**: Add `encrypted_private_key_new`, `encrypted_user_key_new`, `key_derivation_method`, `device_trust_enabled`, `webauthn_enabled` columns
- **NEW**: Add `trusted_devices`, `webauthn_credentials`, `key_operations_log`, `organization_keys` tables

### API Changes
- **BREAKING**: `derive_user_key_consistently` function removed - no more fallback to master key stretching
- **BREAKING**: Login commands now require server-provided encrypted user key
- **BREAKING**: User model structure changed with new key management fields
- **NEW**: Enhanced authentication methods (Password, DeviceTrust, WebAuthnPrf, Hybrid)
- **NEW**: Device trust establishment and management APIs
- **NEW**: WebAuthn PRF authentication support

### Security Changes
- **BREAKING**: All key operations now require successful MAC verification
- **BREAKING**: Key validation against existing ciphers is mandatory
- **NEW**: Comprehensive memory zeroization for all sensitive data
- **NEW**: Constant-time comparisons for security-critical operations
- **NEW**: Enhanced audit logging for all cryptographic operations

### User Impact
- **BREAKING**: Users must re-authenticate after upgrade
- **BREAKING**: Existing vault data must be accessible with server-provided user keys
- **NEW**: Optional device trust for passwordless authentication
- **NEW**: Optional WebAuthn PRF for enhanced security
- **NEW**: Improved security with proper key hierarchy

## Migration Strategy

### Pre-Migration Validation
1. **Backup Verification**: Ensure all users have recent vault backups
2. **Key Compatibility Check**: Validate that server-provided encrypted user keys can decrypt existing ciphers
3. **Server Compatibility**: Verify Bitwarden server supports required key management features

### Migration Steps
1. **Database Migration**: Run `002_breaking_key_management_revamp.sql`
2. **Code Deployment**: Deploy new key management system
3. **User Re-authentication**: Force all users to log in again
4. **Key Validation**: Validate user keys against existing vault data
5. **Feature Rollout**: Gradually enable device trust and WebAuthn features

### Rollback Plan
- **Database Rollback**: Revert to previous schema if critical issues occur
- **Code Rollback**: Deploy previous version if key derivation fails
- **User Communication**: Clear communication about breaking changes and required actions

## Testing Strategy

### Phase 1 Testing
- **Unit Tests**: New key derivation functions with various encrypted key formats
- **Integration Tests**: Login flow with real Bitwarden server responses
- **MAC Verification Tests**: Comprehensive MAC validation scenarios
- **Cipher Compatibility Tests**: Existing vault data decryption validation

### Phase 2 Testing
- **Device Trust Tests**: RSA key pair generation and device trust establishment
- **WebAuthn Tests**: PRF key derivation and authentication workflows
- **Key Rotation Tests**: Master password change scenarios with device trust
- **Cross-Device Tests**: Authentication across multiple trusted devices

### Phase 3 Testing
- **Memory Security Tests**: Zeroization verification and memory leak detection
- **Performance Tests**: Cryptographic operation benchmarks
- **Security Tests**: Constant-time operation validation
- **Audit Tests**: Comprehensive logging coverage verification

### Phase 4 Testing
- **API Integration Tests**: All new authentication endpoints
- **Multi-Method Tests**: Hybrid authentication scenarios
- **Organization Tests**: Multi-organization key management
- **Backward Compatibility Tests**: Existing Bitwarden server compatibility

## Implementation Timeline

- **Week 1-2**: Phase 1 - Core MAC verification fixes and database schema
- **Week 3-4**: Phase 2 - Device trust system implementation
- **Week 5-6**: Phase 3 - Security enhancements and memory management
- **Week 7-8**: Phase 4 - API integration and enhanced authentication
- **Week 9**: Testing and validation
- **Week 10**: Deployment and user migration

## Success Criteria

1. **MAC Verification**: Zero MAC verification failures with server-provided keys
2. **Device Trust**: Successful passwordless authentication using device trust
3. **WebAuthn PRF**: Working WebAuthn authentication with PRF key derivation
4. **Security**: No memory leaks, proper zeroization, comprehensive audit logs
5. **Compatibility**: Full compatibility with official Bitwarden servers
6. **Performance**: No significant performance degradation in key operations
7. **User Experience**: Smooth migration with minimal user disruption

This implementation plan provides a complete overhaul of ChiikaWarden's key management system, eliminating MAC verification failures while implementing modern security features following Bitwarden desktop client patterns.
```
