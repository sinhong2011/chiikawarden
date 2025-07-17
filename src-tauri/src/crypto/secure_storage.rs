use super::{CryptoError, CryptoResult};
use keyring::{Entry, Error as KeyringError};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

const SERVICE_NAME: &str = "Chiikawarden";
const BIOMETRIC_KEY_PREFIX: &str = "biometric_key_";
const USER_KEY_PREFIX: &str = "user_key_";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredKeyData {
    pub key_data: Vec<u8>,
    pub created_at: u64,
    pub key_type: StoredKeyType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum StoredKeyType {
    BiometricKey,
    UserKey,
    MasterKeyHash,
    EncryptedUserKey,
}

pub struct SecureStorageService;

impl SecureStorageService {
    /// Store a key in the system keychain
    pub fn store_key(user_id: &str, key_type: StoredKeyType, key_data: &[u8]) -> CryptoResult<()> {
        let key_name = Self::get_key_name(user_id, &key_type);
        let entry = Entry::new(SERVICE_NAME, &key_name)
            .map_err(|e| CryptoError::Storage(format!("Failed to create keyring entry: {}", e)))?;

        let stored_data = StoredKeyData {
            key_data: key_data.to_vec(),
            created_at: Self::current_timestamp(),
            key_type,
        };

        let serialized = serde_json::to_string(&stored_data)
            .map_err(|e| CryptoError::Storage(format!("Failed to serialize key data: {}", e)))?;

        entry
            .set_password(&serialized)
            .map_err(|e| CryptoError::Storage(format!("Failed to store key: {}", e)))?;

        Ok(())
    }

    /// Retrieve a key from the system keychain
    pub fn retrieve_key(user_id: &str, key_type: StoredKeyType) -> CryptoResult<Option<Vec<u8>>> {
        let key_name = Self::get_key_name(user_id, &key_type);
        let entry = Entry::new(SERVICE_NAME, &key_name)
            .map_err(|e| CryptoError::Storage(format!("Failed to create keyring entry: {}", e)))?;

        match entry.get_password() {
            Ok(serialized) => {
                let stored_data: StoredKeyData =
                    serde_json::from_str(&serialized).map_err(|e| {
                        CryptoError::Storage(format!("Failed to deserialize key data: {}", e))
                    })?;

                Ok(Some(stored_data.key_data))
            }
            Err(KeyringError::NoEntry) => Ok(None),
            Err(e) => Err(CryptoError::Storage(format!(
                "Failed to retrieve key: {}",
                e
            ))),
        }
    }

    /// Delete a key from the system keychain
    pub fn delete_key(user_id: &str, key_type: StoredKeyType) -> CryptoResult<()> {
        let key_name = Self::get_key_name(user_id, &key_type);
        let entry = Entry::new(SERVICE_NAME, &key_name)
            .map_err(|e| CryptoError::Storage(format!("Failed to create keyring entry: {}", e)))?;

        match entry.delete_credential() {
            Ok(()) => Ok(()),
            Err(KeyringError::NoEntry) => Ok(()), // Already deleted
            Err(e) => Err(CryptoError::Storage(format!("Failed to delete key: {}", e))),
        }
    }

    /// Check if a key exists in the keychain
    pub fn has_key(user_id: &str, key_type: StoredKeyType) -> CryptoResult<bool> {
        match Self::retrieve_key(user_id, key_type)? {
            Some(_) => Ok(true),
            None => Ok(false),
        }
    }

    /// Store biometric key for user
    pub fn store_biometric_key(user_id: &str, key: &[u8]) -> CryptoResult<()> {
        Self::store_key(user_id, StoredKeyType::BiometricKey, key)
    }

    /// Retrieve biometric key for user
    pub fn retrieve_biometric_key(user_id: &str) -> CryptoResult<Option<Vec<u8>>> {
        Self::retrieve_key(user_id, StoredKeyType::BiometricKey)
    }

    /// Delete biometric key for user
    pub fn delete_biometric_key(user_id: &str) -> CryptoResult<()> {
        Self::delete_key(user_id, StoredKeyType::BiometricKey)
    }

    /// Store encrypted user key
    pub fn store_encrypted_user_key(user_id: &str, encrypted_key: &[u8]) -> CryptoResult<()> {
        Self::store_key(user_id, StoredKeyType::EncryptedUserKey, encrypted_key)
    }

    /// Retrieve encrypted user key
    pub fn retrieve_encrypted_user_key(user_id: &str) -> CryptoResult<Option<Vec<u8>>> {
        Self::retrieve_key(user_id, StoredKeyType::EncryptedUserKey)
    }

    /// Store master key hash for local verification
    pub fn store_master_key_hash(user_id: &str, hash: &str) -> CryptoResult<()> {
        Self::store_key(user_id, StoredKeyType::MasterKeyHash, hash.as_bytes())
    }

    /// Retrieve master key hash
    pub fn retrieve_master_key_hash(user_id: &str) -> CryptoResult<Option<String>> {
        match Self::retrieve_key(user_id, StoredKeyType::MasterKeyHash)? {
            Some(hash_bytes) => {
                let hash = String::from_utf8(hash_bytes)
                    .map_err(|e| CryptoError::Storage(format!("Invalid hash format: {}", e)))?;
                Ok(Some(hash))
            }
            None => Ok(None),
        }
    }

    /// Clear all stored keys for a user
    pub fn clear_user_keys(user_id: &str) -> CryptoResult<()> {
        let key_types = [
            StoredKeyType::BiometricKey,
            StoredKeyType::UserKey,
            StoredKeyType::MasterKeyHash,
            StoredKeyType::EncryptedUserKey,
        ];

        for key_type in &key_types {
            // Ignore errors for keys that don't exist
            let _ = Self::delete_key(user_id, key_type.clone());
        }

        Ok(())
    }

    /// Get application data directory
    pub fn get_app_data_dir() -> CryptoResult<PathBuf> {
        let mut path = dirs::data_dir()
            .ok_or_else(|| CryptoError::Storage("Failed to get data directory".to_string()))?;

        path.push("Chiikawarden");

        if !path.exists() {
            fs::create_dir_all(&path).map_err(|e| {
                CryptoError::Storage(format!("Failed to create app directory: {}", e))
            })?;
        }

        Ok(path)
    }

    /// Store data to local file (for non-sensitive data)
    pub fn store_local_data(filename: &str, data: &[u8]) -> CryptoResult<()> {
        let mut path = Self::get_app_data_dir()?;
        path.push(filename);

        fs::write(&path, data)
            .map_err(|e| CryptoError::Storage(format!("Failed to write local data: {}", e)))?;

        Ok(())
    }

    /// Retrieve data from local file
    pub fn retrieve_local_data(filename: &str) -> CryptoResult<Option<Vec<u8>>> {
        let mut path = Self::get_app_data_dir()?;
        path.push(filename);

        if !path.exists() {
            return Ok(None);
        }

        let data = fs::read(&path)
            .map_err(|e| CryptoError::Storage(format!("Failed to read local data: {}", e)))?;

        Ok(Some(data))
    }

    /// Delete local data file
    pub fn delete_local_data(filename: &str) -> CryptoResult<()> {
        let mut path = Self::get_app_data_dir()?;
        path.push(filename);

        if path.exists() {
            fs::remove_file(&path)
                .map_err(|e| CryptoError::Storage(format!("Failed to delete local data: {}", e)))?;
        }

        Ok(())
    }

    /// Generate key name for keychain storage
    fn get_key_name(user_id: &str, key_type: &StoredKeyType) -> String {
        let prefix = match key_type {
            StoredKeyType::BiometricKey => BIOMETRIC_KEY_PREFIX,
            StoredKeyType::UserKey => USER_KEY_PREFIX,
            StoredKeyType::MasterKeyHash => "master_hash_",
            StoredKeyType::EncryptedUserKey => "enc_user_key_",
        };

        format!("{}{}", prefix, user_id)
    }

    /// Get current timestamp
    fn current_timestamp() -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_storage_and_retrieval() {
        let user_id = "test_user_123";
        let test_key = b"test_key_data_12345678901234567890";

        // Store key
        SecureStorageService::store_biometric_key(user_id, test_key).unwrap();

        // Retrieve key
        let retrieved = SecureStorageService::retrieve_biometric_key(user_id).unwrap();
        assert_eq!(retrieved, Some(test_key.to_vec()));

        // Check key exists
        assert!(SecureStorageService::has_key(user_id, StoredKeyType::BiometricKey).unwrap());

        // Delete key
        SecureStorageService::delete_biometric_key(user_id).unwrap();

        // Verify deletion
        let retrieved_after_delete = SecureStorageService::retrieve_biometric_key(user_id).unwrap();
        assert_eq!(retrieved_after_delete, None);
    }

    #[test]
    fn test_master_key_hash_storage() {
        let user_id = "test_user_hash";
        let test_hash = "test_hash_value_123456789";

        SecureStorageService::store_master_key_hash(user_id, test_hash).unwrap();
        let retrieved = SecureStorageService::retrieve_master_key_hash(user_id).unwrap();

        assert_eq!(retrieved, Some(test_hash.to_string()));

        SecureStorageService::delete_key(user_id, StoredKeyType::MasterKeyHash).unwrap();
    }

    #[test]
    fn test_local_data_storage() {
        let filename = "test_data.json";
        let test_data = b"test local data content";

        SecureStorageService::store_local_data(filename, test_data).unwrap();
        let retrieved = SecureStorageService::retrieve_local_data(filename).unwrap();

        assert_eq!(retrieved, Some(test_data.to_vec()));

        SecureStorageService::delete_local_data(filename).unwrap();
        let retrieved_after_delete = SecureStorageService::retrieve_local_data(filename).unwrap();
        assert_eq!(retrieved_after_delete, None);
    }
}
