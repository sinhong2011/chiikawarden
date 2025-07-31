// Future implementation: AES-GCM replacement with aws-lc-rs
// This file shows how to replace aes-gcm with aws-lc-rs when ready

use crate::error::{AppError, AppResult};
use aws_lc_rs::aead::{RandomizedNonceKey, Nonce, AES_256_GCM, Aad};
use aws_lc_rs::pbkdf2::{derive, PBKDF2_HMAC_SHA256};
use aws_lc_rs::rand::{SecureRandom, SystemRandom};
use keyring::Entry;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::num::NonZeroU32;
use std::path::PathBuf;
use tracing::debug;
use zeroize::Zeroize;

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

/// Future implementation of SecureKeyStore using aws-lc-rs for AES-GCM
pub struct SecureKeyStoreAwsLcRs {
    service_name: String,
    vault_path: PathBuf,
}

impl SecureKeyStoreAwsLcRs {
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

    /// Generate a random salt for key derivation using aws-lc-rs
    fn generate_salt(&self) -> [u8; 32] {
        let rng = SystemRandom::new();
        let mut salt = [0u8; 32];
        rng.fill(&mut salt).expect("Failed to generate salt");
        salt
    }

    /// Encrypt data using AES-256-GCM with aws-lc-rs RandomizedNonceKey
    fn encrypt_data(&self, data: &[u8], password: &str) -> AppResult<EncryptedVaultData> {
        let salt = self.generate_salt();
        let mut key_bytes = self.derive_key(password, &salt);
        
        // Create RandomizedNonceKey - handles nonce generation automatically
        let key = RandomizedNonceKey::new(&AES_256_GCM, &key_bytes)
            .map_err(|e| AppError::CryptoError {
                message: format!("Failed to create encryption key: {:?}", e),
            })?;

        let mut in_out = data.to_vec();
        
        // Seal with automatic nonce generation
        let nonce = key.seal_in_place_append_tag(Aad::empty(), &mut in_out)
            .map_err(|e| AppError::CryptoError {
                message: format!("Failed to encrypt data: {:?}", e),
            })?;

        // Clear sensitive data from memory
        key_bytes.zeroize();

        Ok(EncryptedVaultData {
            ciphertext: in_out,
            nonce: nonce.as_ref().to_vec(),
            salt: salt.to_vec(),
            created_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
            version: 1,
        })
    }

    /// Decrypt data using AES-256-GCM with aws-lc-rs RandomizedNonceKey
    fn decrypt_data(&self, encrypted: &EncryptedVaultData, password: &str) -> AppResult<Vec<u8>> {
        let mut key_bytes = self.derive_key(password, &encrypted.salt);
        
        // Create RandomizedNonceKey for decryption
        let key = RandomizedNonceKey::new(&AES_256_GCM, &key_bytes)
            .map_err(|e| AppError::CryptoError {
                message: format!("Failed to create decryption key: {:?}", e),
            })?;

        // Convert nonce bytes back to Nonce
        let nonce_bytes: [u8; 12] = encrypted.nonce.as_slice().try_into()
            .map_err(|_| AppError::CryptoError {
                message: "Invalid nonce length".to_string(),
            })?;
        let nonce = Nonce::assume_unique_for_key(nonce_bytes);
        
        let mut in_out = encrypted.ciphertext.clone();
        
        // Open (decrypt and verify)
        let plaintext = key.open_in_place(nonce, Aad::empty(), &mut in_out)
            .map_err(|e| AppError::CryptoError {
                message: format!("Failed to decrypt data: {:?}", e),
            })?;

        // Clear sensitive data from memory
        key_bytes.zeroize();

        Ok(plaintext.to_vec())
    }

    /// Store encrypted data in vault
    pub async fn store_vault_data(&self, key: &str, data: &[u8]) -> AppResult<()> {
        // Use a fixed password for vault encryption (in real implementation, 
        // this would be derived from user's master password or device key)
        let vault_password = "vault_encryption_key"; // TODO: Use proper key derivation
        
        let encrypted = self.encrypt_data(data, vault_password)?;
        
        // Store encrypted data to file
        let key_path = self.vault_path.join(format!("{}.vault", key));
        
        if let Some(parent) = key_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| AppError::CryptoError {
                message: format!("Failed to create vault directory: {}", e),
            })?;
        }
        
        let serialized = serde_json::to_vec(&encrypted).map_err(|e| AppError::CryptoError {
            message: format!("Failed to serialize encrypted data: {}", e),
        })?;
        
        std::fs::write(&key_path, serialized).map_err(|e| AppError::CryptoError {
            message: format!("Failed to write encrypted data to file: {}", e),
        })?;
        
        debug!(
            key = key,
            path = ?key_path,
            "[secure_key_store_aws_lc_rs] Data stored in vault successfully"
        );
        
        Ok(())
    }

    /// Retrieve encrypted data from vault
    pub async fn get_vault_data(&self, key: &str) -> AppResult<Vec<u8>> {
        let vault_password = "vault_encryption_key"; // TODO: Use proper key derivation
        
        let key_path = self.vault_path.join(format!("{}.vault", key));
        
        let serialized = std::fs::read(&key_path).map_err(|e| AppError::CryptoError {
            message: format!("Failed to read encrypted data from file: {}", e),
        })?;
        
        let encrypted: EncryptedVaultData = serde_json::from_slice(&serialized)
            .map_err(|e| AppError::CryptoError {
                message: format!("Failed to deserialize encrypted data: {}", e),
            })?;
        
        let plaintext = self.decrypt_data(&encrypted, vault_password)?;
        
        debug!(
            key = key,
            path = ?key_path,
            "[secure_key_store_aws_lc_rs] Data retrieved from vault successfully"
        );
        
        Ok(plaintext)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_aws_lc_rs_aes_gcm_encryption() {
        let temp_dir = TempDir::new().unwrap();
        let store = SecureKeyStoreAwsLcRs::new(
            "test_service".to_string(),
            temp_dir.path().to_path_buf(),
        );

        let test_data = b"Hello, aws-lc-rs AES-GCM!";
        let password = "test_password";

        // Test encryption
        let encrypted = store.encrypt_data(test_data, password).unwrap();
        
        // Verify encrypted data is different from original
        assert_ne!(encrypted.ciphertext, test_data);
        assert_eq!(encrypted.nonce.len(), 12); // GCM nonce is 96 bits
        assert_eq!(encrypted.salt.len(), 32); // Salt is 256 bits
        
        // Test decryption
        let decrypted = store.decrypt_data(&encrypted, password).unwrap();
        assert_eq!(decrypted, test_data);
    }

    #[test]
    fn test_different_passwords_fail() {
        let temp_dir = TempDir::new().unwrap();
        let store = SecureKeyStoreAwsLcRs::new(
            "test_service".to_string(),
            temp_dir.path().to_path_buf(),
        );

        let test_data = b"Secret data";
        let correct_password = "correct_password";
        let wrong_password = "wrong_password";

        let encrypted = store.encrypt_data(test_data, correct_password).unwrap();
        
        // Wrong password should fail
        let result = store.decrypt_data(&encrypted, wrong_password);
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_vault_storage() {
        let temp_dir = TempDir::new().unwrap();
        let store = SecureKeyStoreAwsLcRs::new(
            "test_service".to_string(),
            temp_dir.path().to_path_buf(),
        );

        let test_data = b"Vault test data";
        let key = "test_key";

        // Store data
        store.store_vault_data(key, test_data).await.unwrap();
        
        // Retrieve data
        let retrieved = store.get_vault_data(key).await.unwrap();
        assert_eq!(retrieved, test_data);
    }
}
