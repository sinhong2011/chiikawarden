use crate::crypto::{CryptoError, CryptoResult};
use crate::debug_config::CorrelationId;
use base64::Engine;
use aws_lc_rs::rand::SystemRandom;
use std::fmt;
use std::ops::{Deref, DerefMut};
use tracing::{debug, warn};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Secure byte container that automatically zeroizes memory on drop
/// This prevents sensitive data from remaining in memory after use
#[derive(Clone, ZeroizeOnDrop)]
pub struct SecureBytes {
    data: Vec<u8>,
    #[zeroize(skip)]
    label: String,
    #[zeroize(skip)]
    created_at: std::time::Instant,
}

impl SecureBytes {
    /// Create a new SecureBytes container with the given data
    pub fn new(data: Vec<u8>, label: &str) -> Self {
        debug!(
            label = label,
            size = data.len(),
            "[secure_memory] Creating SecureBytes container"
        );

        Self {
            data,
            label: label.to_string(),
            created_at: std::time::Instant::now(),
        }
    }

    /// Create a SecureBytes container with random data
    pub fn random(size: usize, label: &str) -> CryptoResult<Self> {
        let rng = SystemRandom::new();
        let mut data = vec![0u8; size];

        aws_lc_rs::rand::SecureRandom::fill(&rng, &mut data)
            .map_err(|e| CryptoError::KeyOperation(format!("Random generation failed: {:?}", e)))?;

        debug!(
            label = label,
            size = size,
            "[secure_memory] Generated random SecureBytes"
        );

        Ok(Self::new(data, label))
    }

    /// Create an empty SecureBytes container
    pub fn empty(label: &str) -> Self {
        Self::new(Vec::new(), label)
    }

    /// Get the length of the data
    pub fn len(&self) -> usize {
        self.data.len()
    }

    /// Check if the container is empty
    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }

    /// Get a reference to the underlying data
    /// Use with caution - the caller must ensure the data is not leaked
    pub fn as_bytes(&self) -> &[u8] {
        &self.data
    }

    /// Get a mutable reference to the underlying data
    /// Use with extreme caution - the caller must ensure the data is not leaked
    pub fn as_bytes_mut(&mut self) -> &mut [u8] {
        &mut self.data
    }

    /// Extend the container with additional data
    pub fn extend_from_slice(&mut self, other: &[u8]) {
        self.data.extend_from_slice(other);
    }

    /// Clear the container and zeroize the memory
    pub fn clear(&mut self) {
        self.data.zeroize();
        self.data.clear();

        debug!(
            label = self.label,
            "[secure_memory] SecureBytes container cleared and zeroized"
        );
    }

    /// Get the label for this container
    pub fn label(&self) -> &str {
        &self.label
    }

    /// Get the age of this container
    pub fn age(&self) -> std::time::Duration {
        self.created_at.elapsed()
    }

    /// Clone the data into a new Vec<u8>
    /// WARNING: The returned Vec will not be automatically zeroized
    pub fn to_vec(&self) -> Vec<u8> {
        warn!(
            label = self.label,
            "[secure_memory] Converting SecureBytes to Vec<u8> - caller must handle zeroization"
        );
        self.data.clone()
    }

    /// Convert to base64 string
    /// WARNING: The returned string will not be automatically zeroized
    pub fn to_base64(&self) -> String {
        warn!(
            label = self.label,
            "[secure_memory] Converting SecureBytes to base64 - caller must handle zeroization"
        );
        base64::engine::general_purpose::STANDARD.encode(&self.data)
    }

    /// Create from base64 string
    pub fn from_base64(data: &str, label: &str) -> CryptoResult<Self> {
        let decoded = base64::engine::general_purpose::STANDARD
            .decode(data)
            .map_err(|e| CryptoError::KeyOperation(format!("Base64 decode failed: {}", e)))?;

        Ok(Self::new(decoded, label))
    }
}

impl Deref for SecureBytes {
    type Target = [u8];

    fn deref(&self) -> &Self::Target {
        &self.data
    }
}

impl DerefMut for SecureBytes {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.data
    }
}

impl fmt::Debug for SecureBytes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SecureBytes")
            .field("label", &self.label)
            .field("len", &self.data.len())
            .field("age_ms", &self.age().as_millis())
            .field("data", &"[REDACTED]")
            .finish()
    }
}

// Drop implementation is handled by ZeroizeOnDrop derive macro

/// Secure key container for cryptographic keys with automatic zeroization
#[derive(ZeroizeOnDrop)]
pub struct SecureKey {
    key_data: SecureBytes,
    #[zeroize(skip)]
    key_type: KeyType,
    #[zeroize(skip)]
    key_id: String,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum KeyType {
    MasterKey,
    UserKey,
    DeviceKey,
    OrganizationKey,
    PrivateKey,
    SymmetricKey,
}

impl SecureKey {
    /// Create a new SecureKey
    pub fn new(key_data: Vec<u8>, key_type: KeyType, key_id: &str) -> Self {
        let label = format!("{:?}:{}", key_type, key_id);

        debug!(
            key_type = ?key_type,
            key_id = key_id,
            key_size = key_data.len(),
            "[secure_memory] Creating SecureKey"
        );

        Self {
            key_data: SecureBytes::new(key_data, &label),
            key_type,
            key_id: key_id.to_string(),
        }
    }

    /// Generate a random key of the specified size
    pub fn generate_random(size: usize, key_type: KeyType, key_id: &str) -> CryptoResult<Self> {
        let label = format!("{:?}:{}", key_type, key_id);
        let key_data = SecureBytes::random(size, &label)?;

        debug!(
            key_type = ?key_type,
            key_id = key_id,
            key_size = size,
            "[secure_memory] Generated random SecureKey"
        );

        Ok(Self {
            key_data,
            key_type,
            key_id: key_id.to_string(),
        })
    }

    /// Get the key type
    pub fn key_type(&self) -> KeyType {
        self.key_type
    }

    /// Get the key ID
    pub fn key_id(&self) -> &str {
        &self.key_id
    }

    /// Get the key size in bytes
    pub fn size(&self) -> usize {
        self.key_data.len()
    }

    /// Get a reference to the key data
    pub fn as_bytes(&self) -> &[u8] {
        self.key_data.as_bytes()
    }

    /// Get the age of this key
    pub fn age(&self) -> std::time::Duration {
        self.key_data.age()
    }

    /// Clone the key data into a new SecureBytes
    pub fn clone_data(&self) -> SecureBytes {
        SecureBytes::new(self.key_data.to_vec(), &self.key_data.label())
    }

    /// Convert to base64 string
    /// WARNING: The returned string will not be automatically zeroized
    pub fn to_base64(&self) -> String {
        self.key_data.to_base64()
    }

    /// Create from base64 string
    pub fn from_base64(data: &str, key_type: KeyType, key_id: &str) -> CryptoResult<Self> {
        let label = format!("{:?}:{}", key_type, key_id);
        let key_data = SecureBytes::from_base64(data, &label)?;

        Ok(Self {
            key_data,
            key_type,
            key_id: key_id.to_string(),
        })
    }

    /// Derive a new key from this key using HKDF
    pub fn derive_key(
        &self,
        info: &[u8],
        length: usize,
        new_key_type: KeyType,
        new_key_id: &str,
    ) -> CryptoResult<SecureKey> {
        use aws_lc_rs::hkdf::{Salt, HKDF_SHA256};

        let salt = Salt::new(HKDF_SHA256, &[]);
        let prk = salt.extract(self.as_bytes());
        let info_slice = [info];
        let okm = prk
            .expand(&info_slice, HKDF_SHA256)
            .map_err(|e| CryptoError::KeyOperation(format!("HKDF expand failed: {:?}", e)))?;

        let mut derived_key = vec![0u8; length];
        okm.fill(&mut derived_key)
            .map_err(|e| CryptoError::KeyOperation(format!("HKDF fill failed: {:?}", e)))?;

        debug!(
            source_key_type = ?self.key_type,
            source_key_id = self.key_id,
            derived_key_type = ?new_key_type,
            derived_key_id = new_key_id,
            derived_length = length,
            "[secure_memory] Derived new key using HKDF"
        );

        Ok(SecureKey::new(derived_key, new_key_type, new_key_id))
    }
}

impl fmt::Debug for SecureKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SecureKey")
            .field("key_type", &self.key_type)
            .field("key_id", &self.key_id)
            .field("size", &self.size())
            .field("age_ms", &self.age().as_millis())
            .field("data", &"[REDACTED]")
            .finish()
    }
}

// Drop implementation is handled by ZeroizeOnDrop derive macro

/// Memory security utilities
pub struct MemorySecurity;

impl MemorySecurity {
    /// Securely compare two byte slices in constant time
    pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
        use subtle::ConstantTimeEq;

        if a.len() != b.len() {
            return false;
        }

        a.ct_eq(b).into()
    }

    /// Zeroize a mutable byte slice
    pub fn zeroize_bytes(data: &mut [u8]) {
        data.zeroize();
    }

    /// Create a secure random salt
    pub fn generate_salt(size: usize, correlation_id: &CorrelationId) -> CryptoResult<SecureBytes> {
        debug!(
            size = size,
            correlation_id = %correlation_id,
            "[secure_memory] Generating secure salt"
        );

        SecureBytes::random(size, "salt")
    }

    /// Validate that sensitive data has been properly zeroized
    /// This is primarily for testing purposes
    pub fn validate_zeroized(data: &[u8]) -> bool {
        data.iter().all(|&b| b == 0)
    }
}
