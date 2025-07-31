use super::{CryptoError, CryptoResult, KdfConfig, KdfType, MasterKey};
use argon2::{Algorithm, Argon2, Params, Version};
use aws_lc_rs::pbkdf2::{derive, PBKDF2_HMAC_SHA256};
use sha2::Sha256;
use std::num::NonZeroU32;
use zeroize::Zeroize;

pub struct KdfService;

impl KdfService {
    /// Derive a master key from password and email using the specified KDF configuration
    pub fn derive_master_key(
        password: &str,
        email: &str,
        kdf_config: &KdfConfig,
    ) -> CryptoResult<MasterKey> {
        use tracing::debug;

        let salt = email.to_lowercase().into_bytes();

        // DEBUG STEP 4: Log KDF parameters and salt
        debug!(
            email = email,
            normalized_email = email.to_lowercase(),
            kdf_type = ?kdf_config.kdf_type,
            iterations = kdf_config.iterations,
            memory = ?kdf_config.memory,
            parallelism = ?kdf_config.parallelism,
            salt_len = salt.len(),
            salt_preview = format!("{:02x?}", &salt[..std::cmp::min(8, salt.len())]),
            "[DEBUG_MAC] Step 4a: KDF parameters for master key derivation"
        );

        let result = match kdf_config.kdf_type {
            KdfType::Pbkdf2Sha256 => {
                debug!("[DEBUG_MAC] Step 4b: Using PBKDF2-SHA256 derivation");
                Self::derive_pbkdf2(password.as_bytes(), &salt, kdf_config.iterations)
            }
            KdfType::Argon2id => {
                let memory = kdf_config.memory.unwrap_or(64 * 1024); // 64 MB default
                let parallelism = kdf_config.parallelism.unwrap_or(4); // 4 threads default
                debug!(
                    memory = memory,
                    parallelism = parallelism,
                    "[DEBUG_MAC] Step 4b: Using Argon2id derivation"
                );
                Self::derive_argon2(
                    password.as_bytes(),
                    &salt,
                    kdf_config.iterations,
                    memory,
                    parallelism,
                )
            }
        };

        // DEBUG STEP 4: Log derivation result
        match &result {
            Ok(master_key) => {
                debug!(
                    master_key_len = master_key.as_bytes().len(),
                    master_key_preview = format!("{:02x?}", &master_key.as_bytes()[..8]),
                    "[DEBUG_MAC] Step 4c: Master key derivation successful"
                );
            }
            Err(e) => {
                debug!(
                    error = %e,
                    "[DEBUG_MAC] Step 4c: Master key derivation failed"
                );
            }
        }

        result
    }

    /// PBKDF2-SHA256 key derivation using AWS-LC-RS
    fn derive_pbkdf2(password: &[u8], salt: &[u8], iterations: u32) -> CryptoResult<MasterKey> {
        let mut key = [0u8; 32];

        let iterations_nz = NonZeroU32::new(iterations)
            .ok_or_else(|| CryptoError::KeyDerivation("Iterations must be non-zero".to_string()))?;

        derive(PBKDF2_HMAC_SHA256, iterations_nz, salt, password, &mut key);

        Ok(MasterKey::new(key.to_vec()))
    }

    /// Argon2id key derivation
    fn derive_argon2(
        password: &[u8],
        salt: &[u8],
        iterations: u32,
        memory: u32,
        parallelism: u32,
    ) -> CryptoResult<MasterKey> {
        // Hash the salt with SHA-256 as Chiikawarden does
        let mut hasher = sha2::Sha256::new();
        use sha2::Digest;
        hasher.update(salt);
        let salt_hash = hasher.finalize();

        let params = Params::new(
            memory,
            iterations,
            parallelism,
            Some(32), // Output length
        )
        .map_err(|e| CryptoError::KeyDerivation(format!("Invalid Argon2 parameters: {}", e)))?;

        let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

        let mut output = [0u8; 32];
        argon2
            .hash_password_into(password, &salt_hash, &mut output)
            .map_err(|e| CryptoError::KeyDerivation(format!("Argon2 hashing failed: {}", e)))?;

        // Clear stack memory (security measure from Chiikawarden)
        Self::clear_stack();

        Ok(MasterKey::new(output.to_vec()))
    }

    /// Hash master key for verification purposes
    pub fn hash_master_key(
        password: &str,
        master_key: &MasterKey,
        purpose: HashPurpose,
    ) -> CryptoResult<String> {
        let iterations = match purpose {
            HashPurpose::LocalAuthorization => 2,
            HashPurpose::ServerAuthorization => 1,
        };

        let mut hash = [0u8; 32];
        let iterations_nz = NonZeroU32::new(iterations)
            .ok_or_else(|| CryptoError::KeyDerivation("Iterations must be non-zero".to_string()))?;

        derive(
            PBKDF2_HMAC_SHA256,
            iterations_nz,
            password.as_bytes(),
            master_key.as_bytes(),
            &mut hash,
        );

        use base64::{engine::general_purpose, Engine as _};
        Ok(general_purpose::STANDARD.encode(hash))
    }

    /// Validate KDF configuration for security
    pub fn validate_kdf_config(config: &KdfConfig) -> CryptoResult<()> {
        match config.kdf_type {
            KdfType::Pbkdf2Sha256 => {
                if config.iterations < 5000 {
                    return Err(CryptoError::InvalidParameters(
                        "PBKDF2 iterations must be at least 5000".to_string(),
                    ));
                }
                if config.iterations > 2_000_000 {
                    return Err(CryptoError::InvalidParameters(
                        "PBKDF2 iterations must not exceed 2,000,000".to_string(),
                    ));
                }
            }
            KdfType::Argon2id => {
                if config.iterations < 2 {
                    return Err(CryptoError::InvalidParameters(
                        "Argon2 iterations must be at least 2".to_string(),
                    ));
                }
                if let Some(memory) = config.memory {
                    if memory < 16 * 1024 {
                        return Err(CryptoError::InvalidParameters(
                            "Argon2 memory must be at least 16 MB".to_string(),
                        ));
                    }
                }
                if let Some(parallelism) = config.parallelism {
                    if parallelism < 1 {
                        return Err(CryptoError::InvalidParameters(
                            "Argon2 parallelism must be at least 1".to_string(),
                        ));
                    }
                }
            }
        }
        Ok(())
    }

    /// Force stack memory to be zeroed (security measure)
    #[inline(never)]
    fn clear_stack() {
        let mut stack_data = [0u8; 4096];
        stack_data.zeroize();
        std::hint::black_box(stack_data);
    }
}

#[derive(Debug, Clone, Copy)]
pub enum HashPurpose {
    LocalAuthorization,
    ServerAuthorization,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pbkdf2_derivation() {
        let password = "supersecurepassword";
        let email = "test@example.com";
        let config = KdfConfig {
            kdf_type: KdfType::Pbkdf2Sha256,
            iterations: 600_000,
            memory: None,
            parallelism: None,
        };

        let master_key = KdfService::derive_master_key(password, email, &config).unwrap();
        assert_eq!(master_key.as_bytes().len(), 32);
    }

    #[test]
    fn test_argon2_derivation() {
        let password = "supersecurepassword";
        let email = "test@example.com";
        let config = KdfConfig {
            kdf_type: KdfType::Argon2id,
            iterations: 3,
            memory: Some(64 * 1024),
            parallelism: Some(4),
        };

        let master_key = KdfService::derive_master_key(password, email, &config).unwrap();
        assert_eq!(master_key.as_bytes().len(), 32);
    }

    #[test]
    fn test_master_key_hashing() {
        let password = "password123";
        let master_key = MasterKey::new(vec![1u8; 32]);

        let local_hash =
            KdfService::hash_master_key(password, &master_key, HashPurpose::LocalAuthorization)
                .unwrap();

        let server_hash =
            KdfService::hash_master_key(password, &master_key, HashPurpose::ServerAuthorization)
                .unwrap();

        assert_ne!(local_hash, server_hash);
        assert!(!local_hash.is_empty());
        assert!(!server_hash.is_empty());
    }
}
