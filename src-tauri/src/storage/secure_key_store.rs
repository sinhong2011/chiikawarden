use crate::error::{AppError, AppResult};
use aes_gcm::{
    aead::{Aead, KeyInit, OsRng},
    Aes256Gcm, Key, Nonce,
};

use rand::RngCore;

use aws_lc_rs::pbkdf2::{derive, PBKDF2_HMAC_SHA256};
use keyring::Entry;

use serde::{Deserialize, Serialize};

use std::num::NonZeroU32;
use std::path::PathBuf;
use tracing::debug;
use zeroize::Zeroize;

/// Hybrid secure key store that uses:
/// - OS keyring (keyring-rs) for refresh tokens
/// - AES-GCM encrypted vault for sensitive data (master keys, device keys, etc.)
#[derive(Clone)]
pub struct SecureKeyStore {
    service_name: String,
    vault_path: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct EncryptedVaultData {
    /// Encrypted data using AES-256-GCM
    ciphertext: Vec<u8>,
    /// Nonce used for encryption (96 bits for GCM)
    nonce: Vec<u8>,
    /// Salt used for key derivation (256 bits)
    salt: Vec<u8>,
    /// Timestamp when the data was encrypted
    created_at: u64,
    /// Version for future compatibility
    version: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VaultSecret {
    data: Vec<u8>,
    created_at: u64,
}

impl SecureKeyStore {
    /// Create a new secure key store
    pub fn new(service_name: String, app_data_dir: PathBuf) -> Self {
        let vault_path = app_data_dir.join("encrypted_vault");

        Self {
            service_name,
            vault_path,
        }
    }

    /// Derive encryption key from password using PBKDF2
    fn derive_key(&self, password: &str, salt: &[u8]) -> [u8; 32] {
        let mut key = [0u8; 32];
        let iterations = NonZeroU32::new(100_000).unwrap();
        derive(
            PBKDF2_HMAC_SHA256,
            iterations,
            salt,
            password.as_bytes(),
            &mut key,
        );
        key
    }

    /// Generate a random salt for key derivation
    fn generate_salt(&self) -> [u8; 32] {
        let mut salt = [0u8; 32];
        OsRng.fill_bytes(&mut salt);
        salt
    }

    /// Generate a random nonce for AES-GCM
    fn generate_nonce(&self) -> [u8; 12] {
        let mut nonce = [0u8; 12];
        OsRng.fill_bytes(&mut nonce);
        nonce
    }

    /// Encrypt data using AES-256-GCM
    fn encrypt_data(&self, data: &[u8], password: &str) -> AppResult<EncryptedVaultData> {
        let salt = self.generate_salt();
        let mut key_bytes = self.derive_key(password, &salt);
        let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
        let cipher = Aes256Gcm::new(key);

        let nonce_bytes = self.generate_nonce();
        let nonce = Nonce::from_slice(&nonce_bytes);

        let ciphertext = cipher
            .encrypt(nonce, data)
            .map_err(|e| AppError::CryptoError {
                message: format!("Failed to encrypt data: {}", e),
            })?;

        // Clear sensitive data from memory
        key_bytes.zeroize();

        Ok(EncryptedVaultData {
            ciphertext,
            nonce: nonce_bytes.to_vec(),
            salt: salt.to_vec(),
            created_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
            version: 1,
        })
    }

    /// Decrypt data using AES-256-GCM
    fn decrypt_data(&self, encrypted: &EncryptedVaultData, password: &str) -> AppResult<Vec<u8>> {
        let mut key_bytes = self.derive_key(password, &encrypted.salt);
        let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
        let cipher = Aes256Gcm::new(key);

        let nonce = Nonce::from_slice(&encrypted.nonce);

        let plaintext = cipher
            .decrypt(nonce, encrypted.ciphertext.as_ref())
            .map_err(|e| AppError::CryptoError {
                message: format!("Failed to decrypt data: {}", e),
            })?;

        // Clear sensitive data from memory
        key_bytes.zeroize();

        Ok(plaintext)
    }

    /// Get a keyring entry for the given key (for refresh tokens)
    fn get_keyring_entry(&self, key: &str) -> AppResult<Entry> {
        Entry::new(&self.service_name, key).map_err(|e| AppError::CryptoError {
            message: format!("Failed to create keyring entry: {}", e),
        })
    }

    /// Store refresh token in OS keyring
    pub async fn store_refresh_token(&self, user_id: &str, token: &str) -> AppResult<()> {
        let key = format!("refresh_token_{}", user_id);
        let entry = self.get_keyring_entry(&key)?;

        entry
            .set_password(token)
            .map_err(|e| AppError::CryptoError {
                message: format!("Failed to store refresh token in keyring: {}", e),
            })?;

        debug!(
            user_id = user_id,
            service = self.service_name,
            "[secure_key_store] Refresh token stored in keyring successfully"
        );

        Ok(())
    }

    /// Store encrypted user key in vault (for session restoration)
    pub async fn store_encrypted_user_key(
        &self,
        user_id: &str,
        encrypted_user_key: &[u8],
    ) -> AppResult<()> {
        let key = format!("encrypted_user_key_{}", user_id);
        self.store_vault_data(&key, encrypted_user_key).await?;

        debug!(
            user_id = user_id,
            "[secure_key_store] Encrypted user key stored in vault successfully"
        );

        Ok(())
    }

    /// Retrieve refresh token from OS keyring
    pub async fn get_refresh_token(&self, user_id: &str) -> AppResult<String> {
        let key = format!("refresh_token_{}", user_id);
        let entry = self.get_keyring_entry(&key)?;

        match entry.get_password() {
            Ok(token) => {
                debug!(
                    user_id = user_id,
                    service = self.service_name,
                    "[secure_key_store] Refresh token retrieved from keyring successfully"
                );
                Ok(token)
            }
            Err(e) => {
                debug!(
                    user_id = user_id,
                    service = self.service_name,
                    error = %e,
                    "[secure_key_store] Refresh token not found in keyring"
                );
                Err(AppError::CryptoError {
                    message: format!("Refresh token not found: {}", user_id),
                })
            }
        }
    }

    /// Retrieve encrypted user key from vault
    pub async fn get_encrypted_user_key(&self, user_id: &str) -> AppResult<Option<Vec<u8>>> {
        let key = format!("encrypted_user_key_{}", user_id);
        match self.get_vault_data(&key).await {
            Ok(data) => {
                debug!(
                    user_id = user_id,
                    "[secure_key_store] Encrypted user key retrieved from vault successfully"
                );
                Ok(Some(data))
            }
            Err(AppError::CryptoError { message }) if message.contains("not found") => {
                debug!(
                    user_id = user_id,
                    "[secure_key_store] No encrypted user key found in vault for user"
                );
                Ok(None)
            }
            Err(e) => Err(e),
        }
    }

    /// Remove encrypted user key from vault
    pub async fn remove_encrypted_user_key(&self, user_id: &str) -> AppResult<()> {
        let key = format!("encrypted_user_key_{}", user_id);
        // Try to remove the vault file
        let file_path = self.vault_path.join(format!("{}.vault", key));
        if file_path.exists() {
            tokio::fs::remove_file(&file_path)
                .await
                .map_err(|e| AppError::CryptoError {
                    message: format!("Failed to remove encrypted user key file: {}", e),
                })?;
            debug!(
                user_id = user_id,
                "[secure_key_store] Encrypted user key removed from vault successfully"
            );
        } else {
            debug!(
                user_id = user_id,
                "[secure_key_store] No encrypted user key file found to remove"
            );
        }
        Ok(())
    }

    /// Remove refresh token from OS keyring
    pub async fn remove_refresh_token(&self, user_id: &str) -> AppResult<()> {
        let key = format!("refresh_token_{}", user_id);
        let entry = self.get_keyring_entry(&key)?;

        match entry.delete_credential() {
            Ok(_) => {
                debug!(
                    user_id = user_id,
                    service = self.service_name,
                    "[secure_key_store] Refresh token removed from keyring successfully"
                );
                Ok(())
            }
            Err(_) => {
                // If the key doesn't exist, that's fine - it's already "removed"
                debug!(
                    user_id = user_id,
                    service = self.service_name,
                    "[secure_key_store] Refresh token not found in keyring (already removed)"
                );
                Ok(())
            }
        }
    }

    /// Store vault data with AES-256-GCM encryption
    /// Uses a default password derived from the service name for now
    /// TODO: In production, use user-provided master password
    pub async fn store_vault_data(&self, key: &str, data: &[u8]) -> AppResult<()> {
        let secret = VaultSecret {
            data: data.to_vec(),
            created_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
        };

        let serialized_data = serde_json::to_vec(&secret).map_err(|e| AppError::CryptoError {
            message: format!("Failed to serialize vault data: {}", e),
        })?;

        // Use service name as password for now - in production, use proper master password
        let password = format!("{}_{}", self.service_name, "vault_key_2024");
        let encrypted_data = self.encrypt_data(&serialized_data, &password)?;

        let encrypted_json =
            serde_json::to_vec(&encrypted_data).map_err(|e| AppError::CryptoError {
                message: format!("Failed to serialize encrypted data: {}", e),
            })?;

        let file_path = self.vault_path.join(format!("{}.vault", key));

        // Ensure directory exists
        if let Some(parent) = file_path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| AppError::CryptoError {
                    message: format!("Failed to create vault directory: {}", e),
                })?;
        }

        tokio::fs::write(&file_path, encrypted_json)
            .await
            .map_err(|e| AppError::CryptoError {
                message: format!("Failed to write encrypted vault data: {}", e),
            })?;

        debug!(
            key = key,
            vault_path = ?self.vault_path,
            "[secure_key_store] Encrypted vault data stored successfully"
        );

        Ok(())
    }

    /// Retrieve and decrypt vault data from encrypted file
    pub async fn get_vault_data(&self, key: &str) -> AppResult<Vec<u8>> {
        let file_path = self.vault_path.join(format!("{}.vault", key));

        match tokio::fs::read(&file_path).await {
            Ok(encrypted_json) => {
                let encrypted_data: EncryptedVaultData = serde_json::from_slice(&encrypted_json)
                    .map_err(|e| AppError::CryptoError {
                        message: format!("Failed to deserialize encrypted data: {}", e),
                    })?;

                // Use service name as password for now - in production, use proper master password
                let password = format!("{}_{}", self.service_name, "vault_key_2024");
                let decrypted_data = self.decrypt_data(&encrypted_data, &password)?;

                let secret: VaultSecret =
                    serde_json::from_slice(&decrypted_data).map_err(|e| AppError::CryptoError {
                        message: format!("Failed to deserialize vault secret: {}", e),
                    })?;

                debug!(
                    key = key,
                    vault_path = ?self.vault_path,
                    "[secure_key_store] Encrypted vault data retrieved successfully"
                );

                Ok(secret.data)
            }
            Err(e) => {
                debug!(
                    key = key,
                    vault_path = ?self.vault_path,
                    error = %e,
                    "[secure_key_store] Encrypted vault data not found"
                );
                Err(AppError::CryptoError {
                    message: format!("Vault data not found: {}", key),
                })
            }
        }
    }

    /// Remove vault data (master password hash/vault key) from encrypted file
    pub async fn remove_vault_data(&self, key: &str) -> AppResult<()> {
        let file_path = self.vault_path.join(format!("{}.vault", key));

        match tokio::fs::remove_file(&file_path).await {
            Ok(_) => {
                debug!(
                    key = key,
                    vault_path = ?self.vault_path,
                    "[secure_key_store] Vault data removed successfully"
                );
                Ok(())
            }
            Err(_) => {
                // If the key doesn't exist, that's fine - it's already "removed"
                debug!(
                    key = key,
                    vault_path = ?self.vault_path,
                    "[secure_key_store] Vault data not found (already removed)"
                );
                Ok(())
            }
        }
    }

    /// Check if vault data exists
    pub async fn has_vault_data(&self, key: &str) -> AppResult<bool> {
        match self.get_vault_data(key).await {
            Ok(_) => Ok(true),
            Err(_) => Ok(false),
        }
    }

    // Compatibility methods for AuthService

    /// Store master key in vault (compatibility method)
    pub async fn store_master_key(&self, user_id: &str, master_key: &[u8]) -> AppResult<()> {
        let key = format!("master_key_{}", user_id);
        self.store_vault_data(&key, master_key).await
    }

    /// Get master key from vault (compatibility method)
    pub async fn get_master_key(&self, user_id: &str) -> AppResult<Vec<u8>> {
        let key = format!("master_key_{}", user_id);
        self.get_vault_data(&key).await
    }

    /// Delete user data (compatibility method)
    pub async fn delete_user_data(&self, user_id: &str) -> AppResult<()> {
        // Remove refresh token from keyring
        let _ = self.remove_refresh_token(user_id).await; // Ignore errors for non-existent keys

        // Remove vault data
        let vault_keys = [
            format!("master_key_{}", user_id),
            format!("device_key_{}", user_id),
            format!("biometric_key_{}", user_id),
        ];

        for key in &vault_keys {
            let _ = self.remove_vault_data(key).await; // Ignore errors for non-existent keys
        }

        Ok(())
    }

    /// Store device key in vault (compatibility method)
    pub async fn store_device_key(&self, user_id: &str, device_key: &[u8]) -> AppResult<()> {
        let key = format!("device_key_{}", user_id);
        self.store_vault_data(&key, device_key).await
    }

    // Auto-unlock key management methods

    /// Store auto-unlock key for "never timeout" scenarios
    pub async fn store_auto_unlock_key(
        &self,
        user_id: &str,
        user_key: &crate::crypto::UserKey,
    ) -> AppResult<()> {
        use tracing::{debug, info};

        debug!(
            user_id = user_id,
            "[secure_key_store] Storing auto-unlock key for user"
        );

        let key = format!("auto_unlock_key_{}", user_id);
        let key_data = user_key.as_bytes();

        self.store_vault_data(&key, key_data).await?;

        info!(
            user_id = user_id,
            "[secure_key_store] Auto-unlock key stored successfully"
        );

        Ok(())
    }

    /// Retrieve auto-unlock key for automatic vault unlock
    pub async fn get_auto_unlock_key(
        &self,
        user_id: &str,
    ) -> AppResult<Option<crate::crypto::UserKey>> {
        use tracing::{debug, info};

        debug!(
            user_id = user_id,
            "[secure_key_store] Retrieving auto-unlock key for user"
        );

        let key = format!("auto_unlock_key_{}", user_id);

        match self.get_vault_data(&key).await {
            Ok(key_data) => {
                let user_key = crate::crypto::UserKey::new(key_data);
                info!(
                    user_id = user_id,
                    "[secure_key_store] Auto-unlock key retrieved successfully"
                );
                Ok(Some(user_key))
            }
            Err(_) => {
                debug!(
                    user_id = user_id,
                    "[secure_key_store] No auto-unlock key found for user"
                );
                Ok(None)
            }
        }
    }

    /// Clear auto-unlock key (called when timeout setting changes)
    pub async fn clear_auto_unlock_key(&self, user_id: &str) -> AppResult<()> {
        use tracing::{debug, info, warn};

        debug!(
            user_id = user_id,
            "[secure_key_store] Clearing auto-unlock key for user"
        );

        let key = format!("auto_unlock_key_{}", user_id);

        match self.remove_vault_data(&key).await {
            Ok(()) => {
                info!(
                    user_id = user_id,
                    "[secure_key_store] Auto-unlock key cleared successfully"
                );
                Ok(())
            }
            Err(e) => {
                warn!(
                    user_id = user_id,
                    error = %e,
                    "[secure_key_store] Failed to clear auto-unlock key (may not exist)"
                );
                // Don't treat missing key as an error
                Ok(())
            }
        }
    }

    /// Check if auto-unlock key exists for a user
    pub async fn has_auto_unlock_key(&self, user_id: &str) -> AppResult<bool> {
        let key = format!("auto_unlock_key_{}", user_id);
        match self.get_vault_data(&key).await {
            Ok(_) => Ok(true),
            Err(_) => Ok(false),
        }
    }

    // Generic methods for backward compatibility

    /// Store secret (routes to appropriate storage based on key type)
    pub async fn store_secret(&self, key: &str, data: &[u8]) -> AppResult<()> {
        if key.contains("refresh_token") {
            // Extract user_id from key like "refresh_token_user123"
            if let Some(user_id) = key.strip_prefix("refresh_token_") {
                let token_str =
                    String::from_utf8(data.to_vec()).map_err(|e| AppError::CryptoError {
                        message: format!("Invalid UTF-8 in refresh token: {}", e),
                    })?;
                self.store_refresh_token(user_id, &token_str).await
            } else {
                Err(AppError::CryptoError {
                    message: "Invalid refresh token key format".to_string(),
                })
            }
        } else {
            // Store in vault for other data
            self.store_vault_data(key, data).await
        }
    }

    /// Get secret (routes to appropriate storage based on key type)
    pub async fn get_secret(&self, key: &str) -> AppResult<Vec<u8>> {
        if key.contains("refresh_token") {
            // Extract user_id from key like "refresh_token_user123"
            if let Some(user_id) = key.strip_prefix("refresh_token_") {
                let token = self.get_refresh_token(user_id).await?;
                Ok(token.into_bytes())
            } else {
                Err(AppError::CryptoError {
                    message: "Invalid refresh token key format".to_string(),
                })
            }
        } else {
            // Get from vault for other data
            self.get_vault_data(key).await
        }
    }

    /// Remove secret (routes to appropriate storage based on key type)
    pub async fn remove_secret(&self, key: &str) -> AppResult<()> {
        if key.contains("refresh_token") {
            // Extract user_id from key like "refresh_token_user123"
            if let Some(user_id) = key.strip_prefix("refresh_token_") {
                self.remove_refresh_token(user_id).await
            } else {
                Err(AppError::CryptoError {
                    message: "Invalid refresh token key format".to_string(),
                })
            }
        } else {
            // Remove from vault for other data
            self.remove_vault_data(key).await
        }
    }

    /// Check if secret exists (routes to appropriate storage based on key type)
    pub async fn has_secret(&self, key: &str) -> AppResult<bool> {
        match self.get_secret(key).await {
            Ok(_) => Ok(true),
            Err(_) => Ok(false),
        }
    }
}
