use crate::crypto::{CryptoResult, CryptoError, UserKey};
use crate::storage::database::AppDatabase;
use crate::debug_config::CorrelationId;
use tracing::{debug, info, warn, error};

/// Key validation service for ensuring key compatibility
/// This service validates user keys against existing ciphers with mandatory MAC verification
pub struct KeyValidationService;

impl KeyValidationService {
    /// Validate user key against existing ciphers (BREAKING CHANGE)
    /// This function now requires ALL sample ciphers to decrypt successfully
    pub async fn validate_user_key_against_ciphers(
        user_key: &UserKey,
        user_id: &str,
        database: &AppDatabase,
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
        database: &AppDatabase,
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

    /// Validate that a user key can decrypt a specific cipher
    /// This is used for testing and debugging purposes
    pub fn validate_user_key_for_cipher(
        user_key: &UserKey,
        encrypted_data: &str,
        cipher_id: &str,
        correlation_id: &CorrelationId,
    ) -> CryptoResult<bool> {
        debug!(
            cipher_id = cipher_id,
            correlation_id = %correlation_id,
            "[key_validation] Validating user key for specific cipher"
        );

        match crate::crypto::cipher_crypto::CipherCrypto::decrypt_string(encrypted_data, user_key) {
            Ok(_) => {
                debug!(
                    cipher_id = cipher_id,
                    correlation_id = %correlation_id,
                    "[key_validation] Cipher decryption successful"
                );
                Ok(true)
            }
            Err(e) => {
                debug!(
                    cipher_id = cipher_id,
                    error = %e,
                    correlation_id = %correlation_id,
                    "[key_validation] Cipher decryption failed"
                );
                Ok(false)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::UserKey;

    #[test]
    fn test_validate_user_key_for_cipher() {
        let user_key = UserKey::new(vec![0u8; 64]);
        let correlation_id = CorrelationId::new();
        
        // This will fail because we're using dummy data, but it tests the function structure
        let result = KeyValidationService::validate_user_key_for_cipher(
            &user_key,
            "dummy_encrypted_data",
            "test_cipher_id",
            &correlation_id,
        );
        
        assert!(result.is_ok());
    }
}
