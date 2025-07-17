use crate::crypto::{CryptoService, MasterKey, UserKey};
use crate::error::{AppError, AppResult};
use crate::storage::SecureKeyStore;
use std::sync::Arc;

/// Authentication service for handling login/logout operations
pub struct AuthService {
    secure_storage: Arc<SecureKeyStore>,
    crypto_service: Arc<CryptoService>,
}

impl AuthService {
    pub fn new(secure_storage: Arc<SecureKeyStore>, crypto_service: Arc<CryptoService>) -> Self {
        Self {
            secure_storage,
            crypto_service,
        }
    }

    /// Store master key securely
    pub async fn store_master_key(&self, user_id: &str, master_key: &MasterKey) -> AppResult<()> {
        self.secure_storage
            .store_master_key(user_id, master_key.as_bytes())
            .await
            .map_err(|_| AppError::CryptographyError {
                operation: "store_master_key".to_string(),
            })
    }

    /// Retrieve master key
    pub async fn get_master_key(&self, user_id: &str) -> AppResult<Option<MasterKey>> {
        match self.secure_storage.get_master_key(user_id).await {
            Ok(key_bytes) => Ok(Some(MasterKey::new(key_bytes))),
            Err(_) => Ok(None),
        }
    }

    /// Delete stored master key
    pub async fn delete_master_key(&self, user_id: &str) -> AppResult<()> {
        self.secure_storage
            .delete_user_data(user_id)
            .await
            .map_err(|_| AppError::CryptographyError {
                operation: "delete_master_key".to_string(),
            })
    }

    /// Derive master key from password
    pub async fn derive_master_key(
        &self,
        password: &str,
        email: &str,
        iterations: u32,
    ) -> AppResult<MasterKey> {
        self.crypto_service
            .derive_master_key(password, email, iterations)
            .map_err(|_| AppError::CryptographyError {
                operation: "derive_master_key".to_string(),
            })
    }

    /// Hash master key for authentication
    pub async fn hash_master_key(
        &self,
        master_key: &MasterKey,
        password: &str,
    ) -> AppResult<String> {
        self.crypto_service
            .hash_master_key(master_key, password)
            .map_err(|_| AppError::CryptographyError {
                operation: "hash_master_key".to_string(),
            })
    }

    /// Generate and encrypt user key
    pub async fn generate_user_key(&self, master_key: &MasterKey) -> AppResult<(UserKey, Vec<u8>)> {
        let user_key =
            self.crypto_service
                .generate_user_key()
                .map_err(|_| AppError::CryptographyError {
                    operation: "generate_user_key".to_string(),
                })?;

        let encrypted_user_key = self
            .crypto_service
            .encrypt_user_key(&user_key, master_key)
            .map_err(|_| AppError::CryptographyError {
                operation: "encrypt_user_key".to_string(),
            })?;

        // Convert encrypted data to bytes for storage
        let encrypted_bytes =
            serde_json::to_vec(&encrypted_user_key).map_err(|_| AppError::CryptographyError {
                operation: "serialize_encrypted_user_key".to_string(),
            })?;

        Ok((user_key, encrypted_bytes))
    }

    /// Store encrypted user key
    pub async fn store_encrypted_user_key(
        &self,
        user_id: &str,
        encrypted_user_key: &[u8],
    ) -> AppResult<()> {
        self.secure_storage
            .store_device_key(user_id, encrypted_user_key)
            .await
            .map_err(|_| AppError::CryptographyError {
                operation: "store_encrypted_user_key".to_string(),
            })
    }
}
