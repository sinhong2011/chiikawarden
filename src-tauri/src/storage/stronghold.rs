use crate::error::{AppError, AppResult};
use ring::{
    aead::{Aad, LessSafeKey, Nonce, UnboundKey, AES_256_GCM},
    pbkdf2,
    rand::{SecureRandom, SystemRandom},
};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::RwLock;
use zeroize::ZeroizeOnDrop;

/// Secure key store using ring for encryption
pub struct SecureKeyStore {
    storage: Arc<RwLock<HashMap<String, Vec<u8>>>>,
    vault_path: PathBuf,
    master_key: Option<LessSafeKey>,
    rng: SystemRandom,
}

#[derive(ZeroizeOnDrop)]
struct SecretData {
    data: Vec<u8>,
}

impl SecureKeyStore {
    pub async fn new(app_handle: &tauri::AppHandle) -> AppResult<Self> {
        use tauri::Manager;
        let app_dir = app_handle
            .path()
            .app_data_dir()
            .map_err(|e| AppError::StorageError {
                message: format!("Failed to get app data dir: {}", e),
            })?;

        let vault_path = app_dir.join("secure_vault.dat");

        // Create directory if it doesn't exist
        if let Some(parent) = vault_path.parent() {
            fs::create_dir_all(parent).map_err(|e| AppError::StorageError {
                message: format!("Failed to create vault directory: {}", e),
            })?;
        }

        let storage = Arc::new(RwLock::new(HashMap::new()));

        Ok(Self {
            storage,
            vault_path,
            master_key: None,
            rng: SystemRandom::new(),
        })
    }

    /// Initialize the vault with a password
    pub async fn initialize(&mut self, password: &str) -> AppResult<()> {
        let salt = self.generate_salt()?;
        let key = self.derive_key(password, &salt)?;

        let unbound_key =
            UnboundKey::new(&AES_256_GCM, &key).map_err(|_| AppError::CryptographyError {
                operation: "Failed to create encryption key".to_string(),
            })?;

        self.master_key = Some(LessSafeKey::new(unbound_key));
        Ok(())
    }

    /// Store a secret securely
    pub async fn store_secret(&self, key: &str, secret: &[u8]) -> AppResult<()> {
        if self.master_key.is_none() {
            return Err(AppError::StorageError {
                message: "Vault not initialized".to_string(),
            });
        }

        let encrypted_data = self.encrypt_data(secret)?;
        let mut storage = self.storage.write().await;
        storage.insert(key.to_string(), encrypted_data);

        // Persist to disk
        self.save_to_disk(&storage).await?;
        Ok(())
    }

    /// Retrieve a secret
    pub async fn get_secret(&self, key: &str) -> AppResult<Vec<u8>> {
        if self.master_key.is_none() {
            return Err(AppError::StorageError {
                message: "Vault not initialized".to_string(),
            });
        }

        let storage = self.storage.read().await;
        let encrypted_data = storage.get(key).ok_or_else(|| AppError::StorageError {
            message: format!("Secret not found: {}", key),
        })?;

        self.decrypt_data(encrypted_data)
    }

    /// Store master key for a user
    pub async fn store_master_key(&self, user_id: &str, master_key: &[u8]) -> AppResult<()> {
        let key = format!("master_key:{}", user_id);
        self.store_secret(&key, master_key).await
    }

    /// Get master key for a user
    pub async fn get_master_key(&self, user_id: &str) -> AppResult<Vec<u8>> {
        let key = format!("master_key:{}", user_id);
        self.get_secret(&key).await
    }

    /// Store device key
    pub async fn store_device_key(&self, device_id: &str, device_key: &[u8]) -> AppResult<()> {
        let key = format!("device_key:{}", device_id);
        self.store_secret(&key, device_key).await
    }

    /// Get device key
    pub async fn get_device_key(&self, device_id: &str) -> AppResult<Vec<u8>> {
        let key = format!("device_key:{}", device_id);
        self.get_secret(&key).await
    }

    /// Store user key
    pub async fn store_user_key(&self, user_id: &str, user_key: &[u8]) -> AppResult<()> {
        let key = format!("user_key:{}", user_id);
        self.store_secret(&key, user_key).await
    }

    /// Get user key
    pub async fn get_user_key(&self, user_id: &str) -> AppResult<Vec<u8>> {
        let key = format!("user_key:{}", user_id);
        self.get_secret(&key).await
    }

    /// Delete all data for a user
    pub async fn delete_user_data(&self, user_id: &str) -> AppResult<()> {
        let mut storage = self.storage.write().await;
        let keys_to_remove: Vec<String> = storage
            .keys()
            .filter(|k| k.contains(&format!(":{}", user_id)))
            .cloned()
            .collect();

        for key in keys_to_remove {
            storage.remove(&key);
        }

        self.save_to_disk(&storage).await?;
        Ok(())
    }

    /// Generate a random salt
    fn generate_salt(&self) -> AppResult<[u8; 32]> {
        let mut salt = [0u8; 32];
        self.rng
            .fill(&mut salt)
            .map_err(|_| AppError::CryptographyError {
                operation: "Failed to generate salt".to_string(),
            })?;
        Ok(salt)
    }

    /// Derive encryption key from password
    fn derive_key(&self, password: &str, salt: &[u8]) -> AppResult<[u8; 32]> {
        let mut key = [0u8; 32];
        pbkdf2::derive(
            pbkdf2::PBKDF2_HMAC_SHA256,
            std::num::NonZeroU32::new(100_000).unwrap(),
            salt,
            password.as_bytes(),
            &mut key,
        );
        Ok(key)
    }

    /// Encrypt data using AES-256-GCM
    fn encrypt_data(&self, data: &[u8]) -> AppResult<Vec<u8>> {
        let key = self
            .master_key
            .as_ref()
            .ok_or_else(|| AppError::StorageError {
                message: "Vault not initialized".to_string(),
            })?;

        let mut nonce_bytes = [0u8; 12];
        self.rng
            .fill(&mut nonce_bytes)
            .map_err(|_| AppError::CryptographyError {
                operation: "Failed to generate nonce".to_string(),
            })?;

        let nonce = Nonce::assume_unique_for_key(nonce_bytes);
        let mut in_out = data.to_vec();

        key.seal_in_place_append_tag(nonce, Aad::empty(), &mut in_out)
            .map_err(|_| AppError::CryptographyError {
                operation: "Failed to encrypt data".to_string(),
            })?;

        // Prepend nonce to encrypted data
        let mut result = nonce_bytes.to_vec();
        result.extend_from_slice(&in_out);
        Ok(result)
    }

    /// Decrypt data using AES-256-GCM
    fn decrypt_data(&self, encrypted_data: &[u8]) -> AppResult<Vec<u8>> {
        let key = self
            .master_key
            .as_ref()
            .ok_or_else(|| AppError::StorageError {
                message: "Vault not initialized".to_string(),
            })?;

        if encrypted_data.len() < 12 {
            return Err(AppError::CryptographyError {
                operation: "Invalid encrypted data length".to_string(),
            });
        }

        let (nonce_bytes, ciphertext) = encrypted_data.split_at(12);
        let nonce = Nonce::try_assume_unique_for_key(nonce_bytes).map_err(|_| {
            AppError::CryptographyError {
                operation: "Invalid nonce".to_string(),
            }
        })?;

        let mut in_out = ciphertext.to_vec();
        let plaintext = key
            .open_in_place(nonce, Aad::empty(), &mut in_out)
            .map_err(|_| AppError::CryptographyError {
                operation: "Failed to decrypt data".to_string(),
            })?;

        Ok(plaintext.to_vec())
    }

    /// Save storage to disk (placeholder - in production, this would be encrypted)
    async fn save_to_disk(&self, _storage: &HashMap<String, Vec<u8>>) -> AppResult<()> {
        // In a real implementation, you would serialize and encrypt the storage
        // before writing to disk. For now, we keep it in memory only.
        Ok(())
    }
}
