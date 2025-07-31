pub mod audit_logger;
pub mod biometrics;
pub mod cache;
pub mod cipher_crypto;
pub mod constant_time;
pub mod device_trust;
pub mod encryption;
pub mod kdf;
pub mod key_validation;
pub mod keys;
pub mod organization_keys;
pub mod secure_memory;
pub mod token_manager;

#[cfg(test)]
pub mod key_derivation_tests;

#[cfg(test)]
pub mod consolidation_tests;

// Re-export main services
pub use cipher_crypto::CipherCrypto;
pub use device_trust::{DeviceIdentifier, DeviceTrustService};
pub use encryption::{EncryptionService, KeyDerivationService};
pub use kdf::KdfService;
pub use key_validation::KeyValidationService;
pub use keys::KeyService;
// Secure memory types will be re-exported when used
// pub use secure_memory::{KeyType, MemorySecurity, SecureBytes, SecureKey};

/// Main crypto service that combines all crypto functionality
pub struct CryptoService;

impl CryptoService {
    pub fn new() -> Self {
        Self
    }

    /// Derive master key from password and email
    pub fn derive_master_key(
        &self,
        password: &str,
        email: &str,
        iterations: u32,
    ) -> CryptoResult<MasterKey> {
        let kdf_config = KdfConfig {
            kdf_type: KdfType::Pbkdf2Sha256,
            iterations,
            memory: None,
            parallelism: None,
        };
        KdfService::derive_master_key(password, email, &kdf_config)
    }

    /// Hash master key for authentication
    pub fn hash_master_key(&self, master_key: &MasterKey, password: &str) -> CryptoResult<String> {
        KdfService::hash_master_key(password, master_key, kdf::HashPurpose::LocalAuthorization)
    }

    /// Generate a new user key
    pub fn generate_user_key(&self) -> CryptoResult<UserKey> {
        KeyService::generate_user_key()
    }

    /// Encrypt user key with master key
    pub fn encrypt_user_key(
        &self,
        user_key: &UserKey,
        master_key: &MasterKey,
    ) -> CryptoResult<EncryptedData> {
        EncryptionService::encrypt_user_key(user_key, master_key)
    }
}

impl Default for CryptoService {
    fn default() -> Self {
        Self::new()
    }
}

use serde::{Deserialize, Serialize};
use specta::Type;
use thiserror::Error;
use zeroize::Zeroize;

#[derive(Error, Debug)]
pub enum CryptoError {
    #[error("Key derivation failed: {0}")]
    KeyDerivation(String),

    #[error("Encryption failed: {0}")]
    Encryption(String),

    #[error("Decryption failed: {0}")]
    Decryption(String),

    #[error("Key generation failed: {0}")]
    KeyGeneration(String),

    #[error("Invalid parameters: {0}")]
    InvalidParameters(String),

    #[error("Storage error: {0}")]
    Storage(String),

    #[error("Invalid format: {0}")]
    InvalidFormat(String),

    #[error("Database error: {0}")]
    Database(String),

    #[error("Key operation error: {0}")]
    KeyOperation(String),
}

pub type CryptoResult<T> = Result<T, CryptoError>;

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub enum KdfType {
    Pbkdf2Sha256,
    Argon2id,
}

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct KdfConfig {
    pub kdf_type: KdfType,
    pub iterations: u32,
    pub memory: Option<u32>,      // For Argon2
    pub parallelism: Option<u32>, // For Argon2
}

impl Default for KdfConfig {
    fn default() -> Self {
        Self {
            kdf_type: KdfType::Pbkdf2Sha256,
            iterations: 600_000,
            memory: None,
            parallelism: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Zeroize)]
#[zeroize(drop)]
pub struct MasterKey {
    pub key: Vec<u8>,
}

impl MasterKey {
    pub fn new(key: Vec<u8>) -> Self {
        Self { key }
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.key
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Zeroize)]
#[zeroize(drop)]
pub struct UserKey {
    pub key: Vec<u8>,
}

impl UserKey {
    pub fn new(key: Vec<u8>) -> Self {
        Self { key }
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.key
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct EncryptedData {
    pub iv: Vec<u8>,
    pub data: Vec<u8>,
    pub mac: Option<Vec<u8>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Type)]
pub enum EncryptionType {
    AesCbc256B64,
    AesCbc256HmacSha256B64,
}

impl Default for EncryptionType {
    fn default() -> Self {
        Self::AesCbc256HmacSha256B64
    }
}
