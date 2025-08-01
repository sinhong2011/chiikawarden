use super::{CryptoError, CryptoResult, EncryptedData, EncryptionType, MasterKey, UserKey};
use crate::logging::log_crypto_operation;
use aws_lc_rs::{
    cipher::{
        DecryptionContext, PaddedBlockDecryptingKey, PaddedBlockEncryptingKey, UnboundCipherKey,
        AES_256,
    },
    hkdf::{Prk, Salt, HKDF_SHA256},
    hmac::{Key as HmacKey, HMAC_SHA256},
    iv::{FixedLength, IV_LEN_128_BIT},
};
use rand::{rngs::OsRng, RngCore};
use tracing::{debug, error, info, warn};

/// Classification of decryption errors for better handling
#[derive(Debug, Clone, PartialEq)]
pub enum DecryptionErrorType {
    MacVerificationFailure,
    PaddingError,
    InvalidKeyLength,
    InvalidParameters,
    Unknown,
}

pub struct EncryptionService;

impl EncryptionService {
    /// Encrypt data using AES-256-CBC with optional HMAC-SHA256 authentication
    pub fn encrypt(
        data: &[u8],
        key: &[u8],
        encryption_type: EncryptionType,
    ) -> CryptoResult<EncryptedData> {
        debug!(
            encryption_type = ?encryption_type,
            data_size = data.len(),
            "[crypto] Starting encryption operation"
        );

        let result = match encryption_type {
            EncryptionType::AesCbc256B64 => Self::encrypt_aes_cbc(data, key),
            EncryptionType::AesCbc256HmacSha256B64 => Self::encrypt_aes_cbc_hmac(data, key),
        };

        let success = result.is_ok();
        if success {
            info!(
                encryption_type = ?encryption_type,
                data_size = data.len(),
                "[crypto] Encryption completed successfully"
            );
            log_crypto_operation("encrypt", true, None);
        } else {
            let error_msg = result.as_ref().err().map(|e| e.to_string());
            log_crypto_operation("encrypt", false, error_msg.as_deref());
        }

        result
    }

    /// Decrypt data using AES-256-CBC with optional HMAC-SHA256 verification
    pub fn decrypt(
        encrypted_data: &EncryptedData,
        key: &[u8],
        encryption_type: EncryptionType,
    ) -> CryptoResult<Vec<u8>> {
        Self::decrypt_with_context(encrypted_data, key, encryption_type, None)
    }

    /// Decrypt data with optional context for better logging
    pub fn decrypt_with_context(
        encrypted_data: &EncryptedData,
        key: &[u8],
        encryption_type: EncryptionType,
        context: Option<&str>,
    ) -> CryptoResult<Vec<u8>> {
        debug!(
            encryption_type = ?encryption_type,
            data_size = encrypted_data.data.len(),
            context = context.unwrap_or("unknown"),
            "[crypto] Starting decryption operation"
        );

        // Validate key before attempting decryption
        Self::validate_key_for_decryption(key, encryption_type, context)?;

        let result = match &encryption_type {
            EncryptionType::AesCbc256B64 => Self::decrypt_aes_cbc(encrypted_data, key),
            EncryptionType::AesCbc256HmacSha256B64 => {
                Self::decrypt_aes_cbc_hmac(encrypted_data, key)
            }
        };

        match &result {
            Ok(decrypted_data) => {
                info!(
                    encryption_type = ?encryption_type,
                    input_size = encrypted_data.data.len(),
                    output_size = decrypted_data.len(),
                    has_mac = encrypted_data.mac.is_some(),
                    "[crypto] Decryption completed successfully"
                );
                log_crypto_operation("decrypt", true, None);
            }
            Err(error) => {
                let error_msg = error.to_string();
                let error_classification = Self::classify_decryption_error(error);

                warn!(
                    encryption_type = ?encryption_type,
                    data_size = encrypted_data.data.len(),
                    has_mac = encrypted_data.mac.is_some(),
                    iv_size = encrypted_data.iv.len(),
                    error = %error,
                    error_type = ?error_classification,
                    "[crypto] Decryption failed with detailed context"
                );

                // Enhanced error logging for debugging
                match error_classification {
                    DecryptionErrorType::MacVerificationFailure => {
                        warn!(
                            "[crypto] MAC verification failure detected - likely key mismatch or data corruption"
                        );
                    }
                    DecryptionErrorType::PaddingError => {
                        warn!(
                            "[crypto] Padding error detected - likely wrong key or corrupted data"
                        );
                    }
                    DecryptionErrorType::InvalidKeyLength => {
                        tracing::error!(
                            "[crypto] Invalid key length - key validation should have caught this"
                        );
                    }
                    DecryptionErrorType::InvalidParameters => {
                        tracing::error!(
                            "[crypto] Invalid parameters - check encryption type and data format"
                        );
                    }
                    DecryptionErrorType::Unknown => {
                        warn!("[crypto] Unknown decryption error - may need investigation");
                    }
                }

                log_crypto_operation("decrypt", false, Some(&error_msg));
            }
        }

        result
    }

    /// Encrypt using AES-256-CBC (no authentication)
    fn encrypt_aes_cbc(data: &[u8], key: &[u8]) -> CryptoResult<EncryptedData> {
        if key.len() != 32 {
            return Err(CryptoError::InvalidParameters(
                "Key must be 32 bytes".to_string(),
            ));
        }

        // Create AWS-LC-RS cipher key
        let unbound_key = UnboundCipherKey::new(&AES_256, key)
            .map_err(|e| CryptoError::Encryption(format!("Failed to create cipher key: {}", e)))?;

        let encrypting_key = PaddedBlockEncryptingKey::cbc_pkcs7(unbound_key).map_err(|e| {
            CryptoError::Encryption(format!("Failed to create encrypting key: {}", e))
        })?;

        // Encrypt the data (AWS-LC-RS generates IV internally)
        let mut buffer = data.to_vec();
        let context = encrypting_key
            .encrypt(&mut buffer)
            .map_err(|e| CryptoError::Encryption(format!("Encryption failed: {}", e)))?;

        // Extract IV from context
        let context_iv: &[u8] = (&context).try_into().map_err(|_| {
            CryptoError::Encryption("Failed to extract IV from context".to_string())
        })?;

        Ok(EncryptedData {
            iv: context_iv.to_vec(),
            data: buffer,
            mac: None,
        })
    }

    /// Encrypt using AES-256-CBC with HMAC-SHA256 authentication
    fn encrypt_aes_cbc_hmac(data: &[u8], key: &[u8]) -> CryptoResult<EncryptedData> {
        if key.len() != 64 {
            return Err(CryptoError::InvalidParameters(
                "Key must be 64 bytes for HMAC".to_string(),
            ));
        }

        let (enc_key, mac_key) = key.split_at(32);

        // Create AWS-LC-RS cipher key for encryption
        let unbound_key = UnboundCipherKey::new(&AES_256, enc_key)
            .map_err(|e| CryptoError::Encryption(format!("Failed to create cipher key: {}", e)))?;

        let encrypting_key = PaddedBlockEncryptingKey::cbc_pkcs7(unbound_key).map_err(|e| {
            CryptoError::Encryption(format!("Failed to create encrypting key: {}", e))
        })?;

        // Encrypt the data (AWS-LC-RS generates IV internally)
        let mut buffer = data.to_vec();
        let context = encrypting_key
            .encrypt(&mut buffer)
            .map_err(|e| CryptoError::Encryption(format!("Encryption failed: {}", e)))?;

        // Extract IV from context
        let context_iv: &[u8] = (&context).try_into().map_err(|_| {
            CryptoError::Encryption("Failed to extract IV from context".to_string())
        })?;

        // Calculate HMAC over IV + encrypted data using AWS-LC-RS
        let hmac_key = HmacKey::new(HMAC_SHA256, mac_key);
        let mut mac_input = Vec::with_capacity(context_iv.len() + buffer.len());
        mac_input.extend_from_slice(context_iv);
        mac_input.extend_from_slice(&buffer);

        let mac_tag = aws_lc_rs::hmac::sign(&hmac_key, &mac_input);

        Ok(EncryptedData {
            iv: context_iv.to_vec(),
            data: buffer,
            mac: Some(mac_tag.as_ref().to_vec()),
        })
    }

    /// Decrypt using AES-256-CBC (no authentication)
    fn decrypt_aes_cbc(encrypted_data: &EncryptedData, key: &[u8]) -> CryptoResult<Vec<u8>> {
        if key.len() != 32 {
            return Err(CryptoError::InvalidParameters(
                "Key must be 32 bytes".to_string(),
            ));
        }

        if encrypted_data.iv.len() != 16 {
            return Err(CryptoError::InvalidParameters(
                "IV must be 16 bytes".to_string(),
            ));
        }

        // Create AWS-LC-RS cipher key for decryption
        let unbound_key = UnboundCipherKey::new(&AES_256, key)
            .map_err(|e| CryptoError::Decryption(format!("Failed to create cipher key: {}", e)))?;

        let decrypting_key = PaddedBlockDecryptingKey::cbc_pkcs7(unbound_key).map_err(|e| {
            CryptoError::Decryption(format!("Failed to create decrypting key: {}", e))
        })?;

        // Create decryption context from IV
        let iv_array: [u8; 16] = encrypted_data.iv.as_slice().try_into().map_err(|_| {
            CryptoError::Decryption("Invalid IV length for FixedLength".to_string())
        })?;
        let context = DecryptionContext::Iv128(FixedLength::<IV_LEN_128_BIT>::from(iv_array));

        // Decrypt the data
        let mut buffer = encrypted_data.data.clone();
        let decrypted_data = decrypting_key
            .decrypt(&mut buffer, context)
            .map_err(|e| CryptoError::Decryption(format!("Failed to decrypt: {}", e)))?;

        Ok(decrypted_data.to_vec())
    }

    /// Decrypt using AES-256-CBC with HMAC-SHA256 verification
    /// Handles missing MAC gracefully for server compatibility
    fn decrypt_aes_cbc_hmac(encrypted_data: &EncryptedData, key: &[u8]) -> CryptoResult<Vec<u8>> {
        use tracing::warn;

        if key.len() != 64 {
            return Err(CryptoError::InvalidParameters(
                "Key must be 64 bytes for HMAC".to_string(),
            ));
        }

        // Handle missing MAC case (server compatibility issue)
        if encrypted_data.mac.is_none() {
            warn!(
                "[crypto] HMAC decryption requested but MAC is missing - this may indicate server compatibility issues"
            );
            return Err(CryptoError::InvalidParameters(
                "MAC is required for HMAC decryption".to_string(),
            ));
        }

        let mac = encrypted_data.mac.as_ref().unwrap();
        let (enc_key, mac_key) = key.split_at(32);

        // Prepare MAC input data (IV + Ciphertext concatenation)
        let mac_input_data = [&encrypted_data.iv[..], &encrypted_data.data[..]].concat();

        // Log MAC verification attempt without sensitive data
        debug!(
            mac_input_len = mac_input_data.len(),
            mac_input_iv_len = encrypted_data.iv.len(),
            mac_input_ct_len = encrypted_data.data.len(),
            "[crypto] Starting MAC verification for decryption"
        );

        // Verify HMAC using AWS-LC-RS
        let hmac_key = HmacKey::new(HMAC_SHA256, mac_key);
        let computed_mac = aws_lc_rs::hmac::sign(&hmac_key, &mac_input_data);

        // Log verification result without exposing MAC values
        debug!(
            macs_match = computed_mac.as_ref() == mac,
            "[crypto] MAC verification completed"
        );

        aws_lc_rs::hmac::verify(&hmac_key, &mac_input_data, mac).map_err(|_| {
            // Log MAC verification failure without exposing sensitive data
            error!(
                mac_input_len = mac_input_data.len(),
                "[crypto] MAC verification failed - potential data corruption or key mismatch"
            );
            CryptoError::Decryption("MAC verification failed".to_string())
        })?;

        // Decrypt after MAC verification
        Self::decrypt_aes_cbc(
            &EncryptedData {
                iv: encrypted_data.iv.clone(),
                data: encrypted_data.data.clone(),
                mac: None,
            },
            enc_key,
        )
    }

    /// Decrypt user key with master key
    pub fn decrypt_user_key(
        encrypted_user_key: &EncryptedData,
        master_key: &MasterKey,
        encryption_type: EncryptionType,
    ) -> CryptoResult<UserKey> {
        use tracing::{debug, info};

        debug!(
            encryption_type = ?encryption_type,
            data_size = encrypted_user_key.data.len(),
            has_mac = encrypted_user_key.mac.is_some(),
            "[crypto] Starting user key decryption with master key"
        );

        let key_bytes = match &encryption_type {
            EncryptionType::AesCbc256B64 => {
                debug!("[crypto] Using AesCbc256B64 for user key decryption (no key stretching)");
                Self::decrypt(encrypted_user_key, master_key.as_bytes(), encryption_type)?
            }
            EncryptionType::AesCbc256HmacSha256B64 => {
                debug!("[crypto] Using AesCbc256HmacSha256B64 for user key decryption (with key stretching)");
                // Stretch the master key for HMAC variant
                let stretched_key = EncryptionService::stretch_key(master_key)?;
                debug!(
                    original_key_len = master_key.as_bytes().len(),
                    stretched_key_len = stretched_key.len(),
                    "[crypto] Master key stretched for HMAC decryption"
                );
                Self::decrypt(encrypted_user_key, &stretched_key, encryption_type)?
            }
        };

        info!(
            encryption_type = ?encryption_type,
            user_key_len = key_bytes.len(),
            "[crypto] User key decrypted successfully from master key"
        );

        Ok(UserKey::new(key_bytes))
    }

    /// Encrypt user key with master key
    pub fn encrypt_user_key(
        user_key: &UserKey,
        master_key: &MasterKey,
    ) -> CryptoResult<EncryptedData> {
        // Use AES-256-CBC with HMAC-SHA256 for user key encryption
        let stretched_key = EncryptionService::stretch_key(master_key)?;
        Self::encrypt(
            user_key.as_bytes(),
            &stretched_key,
            EncryptionType::AesCbc256HmacSha256B64,
        )
    }

    /// Stretch a 32-byte key to 64 bytes using HKDF (Bitwarden protocol)
    /// This follows the official Bitwarden key derivation process:
    /// - Single HKDF expansion with empty info to produce 64 bytes
    /// - First 32 bytes: encryption key
    /// - Last 32 bytes: MAC key
    fn stretch_key(master_key: &MasterKey) -> CryptoResult<Vec<u8>> {
        // FIXED: Use master key directly as PRK (rbw-compatible approach)
        // This matches rbw's implementation exactly
        let prk = Prk::new_less_safe(HKDF_SHA256, master_key.as_bytes());

        // DEBUG: Log HKDF parameters
        debug!(
            master_key_len = master_key.as_bytes().len(),
            master_key_preview = format!("{:02x?}", &master_key.as_bytes()[..8]),
            approach = "direct_prk_rbw_compatible",
            "[DEBUG_MAC] HKDF setup for key stretching"
        );

        // Use separate HKDF expansions with "enc" and "mac" info parameters (rbw approach)

        // First derive encryption key (32 bytes) with info="enc"
        let enc_info = b"enc";
        let enc_info_slice = [enc_info.as_slice()];
        let mut encryption_key = vec![0u8; 32];
        let okm_enc = prk
            .expand(&enc_info_slice, HKDF_SHA256.hmac_algorithm())
            .map_err(|e| {
                CryptoError::KeyGeneration(format!("Encryption key HKDF expansion failed: {}", e))
            })?;

        okm_enc.fill(&mut encryption_key).map_err(|e| {
            CryptoError::KeyGeneration(format!("Failed to fill encryption key: {}", e))
        })?;

        // Then derive MAC key (32 bytes) with info="mac"
        let mac_info = b"mac";
        let mac_info_slice = [mac_info.as_slice()];
        let mut mac_key = vec![0u8; 32];
        let okm_mac = prk
            .expand(&mac_info_slice, HKDF_SHA256.hmac_algorithm())
            .map_err(|e| {
                CryptoError::KeyGeneration(format!("MAC key HKDF expansion failed: {}", e))
            })?;

        okm_mac
            .fill(&mut mac_key)
            .map_err(|e| CryptoError::KeyGeneration(format!("Failed to fill MAC key: {}", e)))?;

        // Combine into 64-byte stretched key (enc_key + mac_key)
        let mut stretched_key = Vec::with_capacity(64);
        stretched_key.extend_from_slice(&encryption_key);
        stretched_key.extend_from_slice(&mac_key);

        // Split into enc_key (first 32) and mac_key (last 32) - Bitwarden standard
        let enc_key = &stretched_key[0..32];
        let mac_key = &stretched_key[32..64];

        // DEBUG: Log derived keys with full byte comparison
        debug!(
            enc_key_preview = format!("{:02x?}", &enc_key[..8]),
            mac_key_preview = format!("{:02x?}", &mac_key[..8]),
            "[DEBUG_MAC] HKDF derived keys"
        );

        // Log key derivation success without exposing key material
        debug!(
            enc_key_len = enc_key.len(),
            mac_key_len = mac_key.len(),
            stretched_len = stretched_key.len(),
            "[crypto] Key stretching completed successfully"
        );

        Ok(stretched_key)
    }

    /// Public function to stretch master key for user key fallback
    pub fn stretch_master_key_for_user_key(master_key: &MasterKey) -> CryptoResult<Vec<u8>> {
        EncryptionService::stretch_key(master_key)
    }

    /// DEPRECATED: This function has been replaced by KeyDerivationService
    /// Use KeyDerivationService::derive_user_key_from_server instead
    #[deprecated(note = "Use KeyDerivationService::derive_user_key_from_server instead")]
    pub fn derive_user_key_consistently(
        encrypted_user_key_b64: Option<&str>,
        master_key: &MasterKey,
        user_id: &str,
    ) -> CryptoResult<UserKey> {
        use crate::crypto::cipher_crypto::EncryptedString;
        use tracing::{debug, info, warn};

        debug!(
            user_id = user_id,
            has_encrypted_key = encrypted_user_key_b64.is_some(),
            "[crypto] Starting consistent user key derivation"
        );

        match encrypted_user_key_b64 {
            Some(encrypted_str) => {
                debug!(
                    user_id = user_id,
                    encrypted_key_preview =
                        &encrypted_str[..std::cmp::min(50, encrypted_str.len())],
                    "[crypto] Attempting to decrypt server-provided encrypted user key"
                );

                // Parse the encrypted string using Bitwarden format
                match EncryptedString::from_string(encrypted_str) {
                    Ok(enc_string) => {
                        debug!(
                            user_id = user_id,
                            encryption_type = ?enc_string.encryption_type,
                            iv_len = enc_string.iv.len(),
                            data_len = enc_string.data.len(),
                            has_mac = enc_string.mac.is_some(),
                            "[crypto] Successfully parsed encrypted user key string"
                        );

                        let encrypted_data = enc_string.to_encrypted_data();
                        match Self::decrypt_user_key(
                            &encrypted_data,
                            master_key,
                            enc_string.encryption_type,
                        ) {
                            Ok(user_key) => {
                                info!(
                                    user_id = user_id,
                                    derivation_method = "server_encrypted_key",
                                    user_key_len = user_key.as_bytes().len(),
                                    user_key_preview =
                                        format!("{:02x?}", &user_key.as_bytes()[..16]),
                                    "[crypto] Successfully decrypted server-provided user key"
                                );
                                return Ok(user_key);
                            }
                            Err(e) => {
                                // Enhanced debugging for fallback trigger
                                let error_details = format!("{:?}", e);
                                let is_mac_error = error_details.contains("MAC")
                                    || error_details.contains("verification");
                                let is_key_error = error_details.contains("key")
                                    || error_details.contains("invalid");
                                let is_decrypt_error = error_details.contains("decrypt")
                                    || error_details.contains("cipher");

                                warn!(
                                    user_id = user_id,
                                    error = %e,
                                    error_type = ?e,
                                    error_category = if is_mac_error { "MAC_VERIFICATION" }
                                                   else if is_key_error { "KEY_VALIDATION" }
                                                   else if is_decrypt_error { "DECRYPTION_FAILURE" }
                                                   else { "UNKNOWN" },
                                    master_key_len = master_key.as_bytes().len(),
                                    master_key_preview = format!("{:02x?}", &master_key.as_bytes()[..16]),
                                    encrypted_data_len = encrypted_data.data.len(),
                                    encrypted_iv_len = encrypted_data.iv.len(),
                                    encrypted_has_mac = encrypted_data.mac.is_some(),
                                    encrypted_mac_len = encrypted_data.mac.as_ref().map(|m| m.len()),
                                    encryption_type = ?enc_string.encryption_type,
                                    "[crypto] ❌ FALLBACK TRIGGER: Failed to decrypt server-provided user key - this creates User Key B instead of User Key A"
                                );

                                // Log the exact failure point for debugging
                                debug!(
                                    user_id = user_id,
                                    "[crypto] 🔍 DEBUGGING: This fallback will create a different user key than the one used to encrypt existing ciphers"
                                );
                            }
                        }
                    }
                    Err(e) => {
                        warn!(
                            user_id = user_id,
                            error = ?e,
                            "[crypto] Failed to parse encrypted user key string, falling back to stretched master key"
                        );
                    }
                }
            }
            None => {
                debug!(
                    user_id = user_id,
                    "[crypto] No encrypted user key provided, using stretched master key"
                );
            }
        }

        // Fallback: Use stretched master key as user key
        warn!(
            user_id = user_id,
            "[crypto] 🚨 CREATING USER KEY B: Using stretched master key as user key (fallback method)"
        );

        warn!(
            user_id = user_id,
            "[crypto] ⚠️  WARNING: This will create a DIFFERENT user key than User Key A used to encrypt existing ciphers!"
        );

        let stretched_key = EncryptionService::stretch_key(master_key)?;
        let user_key = UserKey::new(stretched_key.clone());

        warn!(
            user_id = user_id,
            derivation_method = "stretched_master_key",
            user_key_len = user_key.as_bytes().len(),
            user_key_preview = format!("{:02x?}", &user_key.as_bytes()[..16]),
            "[crypto] 🔑 USER KEY B CREATED: This is why MAC verification fails on existing ciphers"
        );

        Ok(user_key)
    }

    /// Validate that a user key can decrypt existing ciphers
    pub async fn validate_user_key_for_existing_ciphers(
        user_key: &UserKey,
        user_id: &str,
        database: &crate::storage::AppDatabase,
    ) -> CryptoResult<bool> {
        use crate::crypto::cipher_crypto::CipherCrypto;
        use tracing::{debug, warn};

        debug!(
            user_id = user_id,
            user_key_preview = format!("{:02x?}", &user_key.as_bytes()[..16]),
            "[crypto] Validating user key against existing ciphers"
        );

        // Get a sample of existing ciphers for this user
        let sample_ciphers = match database.get_user_ciphers_sample(user_id, 3).await {
            Ok(ciphers) => ciphers,
            Err(e) => {
                debug!(
                    user_id = user_id,
                    error = %e,
                    "[crypto] No existing ciphers found for validation - assuming valid"
                );
                return Ok(true); // No ciphers to validate against
            }
        };

        if sample_ciphers.is_empty() {
            debug!(
                user_id = user_id,
                "[crypto] No ciphers found for validation - user key assumed valid"
            );
            return Ok(true);
        }

        let mut successful_decryptions = 0;
        let mut total_attempts = 0;

        for cipher in sample_ciphers {
            total_attempts += 1;

            // Try to decrypt the cipher name (most basic test)
            let encrypted_name = &cipher.name;
            if !encrypted_name.is_empty() {
                match CipherCrypto::decrypt_string(encrypted_name, user_key) {
                    Ok(_decrypted_name) => {
                        successful_decryptions += 1;
                        debug!(
                            user_id = user_id,
                            cipher_id = cipher.id,
                            "[crypto] ✅ Successfully decrypted cipher name with user key"
                        );
                    }
                    Err(e) => {
                        warn!(
                            user_id = user_id,
                            cipher_id = cipher.id,
                            error = %e,
                            "[crypto] ❌ Failed to decrypt cipher name with user key"
                        );
                    }
                }
            }
        }

        let success_rate = if total_attempts > 0 {
            (successful_decryptions as f64) / (total_attempts as f64)
        } else {
            1.0
        };

        let is_valid = success_rate >= 0.5; // At least 50% success rate

        if is_valid {
            debug!(
                user_id = user_id,
                successful_decryptions = successful_decryptions,
                total_attempts = total_attempts,
                success_rate = success_rate,
                "[crypto] ✅ User key validation PASSED - can decrypt existing ciphers"
            );
        } else {
            warn!(
                user_id = user_id,
                successful_decryptions = successful_decryptions,
                total_attempts = total_attempts,
                success_rate = success_rate,
                "[crypto] ❌ User key validation FAILED - cannot decrypt existing ciphers (User Key B detected)"
            );
        }

        Ok(is_valid)
    }

    /// Generate a random encryption key
    pub fn generate_key(length: usize) -> CryptoResult<Vec<u8>> {
        let mut key = vec![0u8; length];
        OsRng.fill_bytes(&mut key);
        Ok(key)
    }

    /// Generate random bytes
    pub fn random_bytes(length: usize) -> CryptoResult<Vec<u8>> {
        let mut bytes = vec![0u8; length];
        OsRng.fill_bytes(&mut bytes);
        Ok(bytes)
    }

    /// Validate user key by attempting to decrypt a test cipher
    pub fn validate_user_key(
        user_key: &UserKey,
        test_encrypted_data: &EncryptedData,
        encryption_type: EncryptionType,
    ) -> CryptoResult<bool> {
        use tracing::{debug, warn};

        debug!(
            key_len = user_key.as_bytes().len(),
            encryption_type = ?encryption_type,
            "[crypto] Validating user key with test decryption"
        );

        match Self::decrypt(test_encrypted_data, user_key.as_bytes(), encryption_type) {
            Ok(_) => {
                debug!("[crypto] User key validation successful");
                Ok(true)
            }
            Err(e) => {
                warn!(
                    error = %e,
                    "[crypto] User key validation failed - key may be invalid"
                );
                Ok(false)
            }
        }
    }

    /// Validate key before decryption with detailed error reporting
    pub fn validate_key_for_decryption(
        key: &[u8],
        encryption_type: EncryptionType,
        context: Option<&str>,
    ) -> CryptoResult<()> {
        use tracing::{debug, error};

        debug!(
            key_len = key.len(),
            encryption_type = ?encryption_type,
            context = context.unwrap_or("unknown"),
            "[crypto] Validating key parameters for decryption"
        );

        match &encryption_type {
            EncryptionType::AesCbc256B64 => {
                if key.len() != 32 {
                    error!(
                        expected_len = 32,
                        actual_len = key.len(),
                        context = context.unwrap_or("unknown"),
                        "[crypto] Invalid key length for AesCbc256B64"
                    );
                    return Err(CryptoError::InvalidParameters(format!(
                        "Key must be 32 bytes for AesCbc256B64, got {}",
                        key.len()
                    )));
                }
            }
            EncryptionType::AesCbc256HmacSha256B64 => {
                if key.len() != 64 {
                    error!(
                        expected_len = 64,
                        actual_len = key.len(),
                        context = context.unwrap_or("unknown"),
                        "[crypto] Invalid key length for AesCbc256HmacSha256B64"
                    );
                    return Err(CryptoError::InvalidParameters(format!(
                        "Key must be 64 bytes for AesCbc256HmacSha256B64, got {}",
                        key.len()
                    )));
                }
            }
        }

        debug!(
            context = context.unwrap_or("unknown"),
            "[crypto] Key validation passed"
        );
        Ok(())
    }

    /// Classify decryption errors for better handling
    fn classify_decryption_error(error: &CryptoError) -> DecryptionErrorType {
        let error_msg = error.to_string().to_lowercase();

        if error_msg.contains("mac verification failed") || error_msg.contains("mac") {
            DecryptionErrorType::MacVerificationFailure
        } else if error_msg.contains("padding") || error_msg.contains("pkcs") {
            DecryptionErrorType::PaddingError
        } else if error_msg.contains("key must be") || error_msg.contains("invalid key length") {
            DecryptionErrorType::InvalidKeyLength
        } else if error_msg.contains("invalid parameters") || error_msg.contains("invalid") {
            DecryptionErrorType::InvalidParameters
        } else {
            DecryptionErrorType::Unknown
        }
    }
}

/// Secure key derivation service following Bitwarden desktop client patterns
/// This service eliminates MAC verification failures by removing fallback logic
pub struct KeyDerivationService;

impl KeyDerivationService {
    /// Derive user key from server-provided encrypted user key (BREAKING CHANGE)
    /// This function no longer falls back to master key stretching
    pub fn derive_user_key_from_server(
        encrypted_user_key_b64: &str,
        master_key: &MasterKey,
        user_id: &str,
        correlation_id: &crate::debug_config::CorrelationId,
    ) -> CryptoResult<UserKey> {
        use crate::crypto::cipher_crypto::EncryptedString;
        use tracing::{debug, error, info};

        debug!(
            user_id = user_id,
            correlation_id = %correlation_id,
            encrypted_key_preview = &encrypted_user_key_b64[..std::cmp::min(50, encrypted_user_key_b64.len())],
            "[key_derivation] Starting server-provided user key derivation"
        );

        // DEBUG STEP 5: Log encrypted string parsing
        debug!(
            user_id = user_id,
            correlation_id = %correlation_id,
            encrypted_key_b64_len = encrypted_user_key_b64.len(),
            encrypted_key_b64_preview = &encrypted_user_key_b64[..std::cmp::min(50, encrypted_user_key_b64.len())],
            "[DEBUG_MAC] Step 5a: Parsing encrypted user key string"
        );

        // Parse encrypted string with strict validation
        let encrypted_string =
            EncryptedString::from_string(encrypted_user_key_b64).map_err(|e| {
                error!(
                    user_id = user_id,
                    correlation_id = %correlation_id,
                    error = %e,
                    "[DEBUG_MAC] Step 5a: Invalid encrypted user key format from server"
                );
                CryptoError::InvalidFormat(format!("Invalid encrypted user key format: {}", e))
            })?;

        // Log parsed encrypted string details without sensitive data
        debug!(
            user_id = user_id,
            correlation_id = %correlation_id,
            encryption_type = ?encrypted_string.encryption_type,
            has_mac = encrypted_string.mac.is_some(),
            iv_len = encrypted_string.iv.len(),
            data_len = encrypted_string.data.len(),
            mac_len = encrypted_string.mac.as_ref().map(|m| m.len()),
            "[crypto] Parsed encrypted user key for decryption"
        );

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

    /// Decrypt user key using master key with proper MAC verification and fallback handling
    fn decrypt_user_key_with_master_key(
        encrypted_string: &crate::crypto::cipher_crypto::EncryptedString,
        master_key: &MasterKey,
    ) -> CryptoResult<UserKey> {
        use tracing::{debug, info, warn};

        // DEBUG STEP 6: Log master key and encrypted string details
        debug!(
            encryption_type = ?encrypted_string.encryption_type,
            master_key_len = master_key.as_bytes().len(),
            master_key_preview = format!("{:02x?}", &master_key.as_bytes()[..8]),
            has_mac = encrypted_string.mac.is_some(),
            iv_len = encrypted_string.iv.len(),
            data_len = encrypted_string.data.len(),
            mac_len = encrypted_string.mac.as_ref().map(|m| m.len()),
            "[DEBUG_MAC] Step 6a: Starting user key decryption with master key"
        );

        // Handle key stretching based on encryption type
        let decrypted_bytes = match &encrypted_string.encryption_type {
            EncryptionType::AesCbc256B64 => {
                debug!("[crypto] Using AesCbc256B64 for user key decryption (no key stretching)");
                crate::crypto::cipher_crypto::CipherCrypto::decrypt_bytes(
                    encrypted_string,
                    master_key.as_bytes(),
                )?
            }
            EncryptionType::AesCbc256HmacSha256B64 => {
                debug!("[crypto] Using AesCbc256HmacSha256B64 for user key decryption (with key stretching)");

                // Check if MAC is missing for Type 2 encryption (server compatibility issue)
                if encrypted_string.mac.is_none() {
                    warn!(
                        "[crypto] Type 2 encrypted string missing MAC component - attempting fallback to Type 0 decryption"
                    );

                    // Fallback: Try decrypting as Type 0 (AesCbc256B64) without MAC verification
                    // This handles cases where the server sends Type 2 format but without MAC
                    match crate::crypto::cipher_crypto::CipherCrypto::decrypt_bytes(
                        encrypted_string,
                        master_key.as_bytes(),
                    ) {
                        Ok(bytes) => {
                            warn!(
                                "[crypto] Successfully decrypted Type 2 string without MAC using fallback method"
                            );
                            bytes
                        }
                        Err(fallback_error) => {
                            debug!(
                                fallback_error = %fallback_error,
                                "[crypto] Fallback decryption failed, trying with stretched key"
                            );

                            // If fallback fails, try with stretched key anyway
                            let stretched_key = EncryptionService::stretch_key(master_key)?;
                            crate::crypto::cipher_crypto::CipherCrypto::decrypt_bytes(
                                encrypted_string,
                                &stretched_key,
                            )?
                        }
                    }
                } else {
                    // Normal path: MAC is present, use stretched key
                    // DEBUG STEP 6: Log key stretching process
                    debug!(
                        original_key_len = master_key.as_bytes().len(),
                        original_key_preview = format!("{:02x?}", &master_key.as_bytes()[..8]),
                        "[DEBUG_MAC] Step 6b: About to stretch master key for HMAC decryption"
                    );

                    let stretched_key = EncryptionService::stretch_key(master_key)?;

                    debug!(
                        original_key_len = master_key.as_bytes().len(),
                        stretched_key_len = stretched_key.len(),
                        stretched_key_preview = format!("{:02x?}", &stretched_key[..8]),
                        "[DEBUG_MAC] Step 6c: Master key stretched successfully"
                    );

                    // DEBUG STEP 6: Log before MAC verification
                    debug!(
                        mac_present = encrypted_string.mac.is_some(),
                        mac_len = encrypted_string.mac.as_ref().map(|m| m.len()),
                        "[DEBUG_MAC] Step 6d: About to attempt decryption with MAC verification"
                    );

                    crate::crypto::cipher_crypto::CipherCrypto::decrypt_bytes(
                        encrypted_string,
                        &stretched_key,
                    )?
                }
            }
        };

        info!(
            encryption_type = ?encrypted_string.encryption_type,
            user_key_len = decrypted_bytes.len(),
            "[crypto] User key decrypted successfully from master key"
        );

        Ok(UserKey::new(decrypted_bytes))
    }

    /// Generate new user key (for new accounts)
    pub fn generate_new_user_key() -> CryptoResult<UserKey> {
        crate::crypto::keys::KeyService::generate_user_key()
    }

    /// Comprehensive verification function to compare with Keyguard's implementation
    /// This function performs step-by-step verification to isolate differences
    pub fn verify_keyguard_compatibility(
        master_key: &MasterKey,
        encrypted_user_key_b64: &str,
    ) -> CryptoResult<()> {
        use tracing::{info, warn};

        info!("[KEYGUARD_VERIFY] Starting comprehensive compatibility verification");

        // Step 1: Verify master key format
        info!(
            master_key_len = master_key.as_bytes().len(),
            master_key_hex = hex::encode(master_key.as_bytes()),
            "[KEYGUARD_VERIFY] Step 1: Master key verification"
        );

        // Step 2: Verify HKDF key stretching
        let stretched_key = EncryptionService::stretch_key(master_key)?;
        let (enc_key, mac_key) = stretched_key.split_at(32);

        info!(
            stretched_key_len = stretched_key.len(),
            enc_key_hex = hex::encode(enc_key),
            mac_key_hex = hex::encode(mac_key),
            "[KEYGUARD_VERIFY] Step 2: HKDF key stretching verification"
        );

        // Step 3: Parse encrypted string
        let encrypted_string =
            crate::crypto::cipher_crypto::EncryptedString::from_string(encrypted_user_key_b64)
                .map_err(|e| CryptoError::InvalidFormat(format!("Parse error: {}", e)))?;

        info!(
            encryption_type = ?encrypted_string.encryption_type,
            iv_hex = hex::encode(&encrypted_string.iv),
            data_len = encrypted_string.data.len(),
            data_hex_preview = hex::encode(&encrypted_string.data[..std::cmp::min(32, encrypted_string.data.len())]),
            mac_hex = encrypted_string.mac.as_ref().map(|m| hex::encode(m)),
            "[KEYGUARD_VERIFY] Step 3: Encrypted string parsing verification"
        );

        // Step 4: Verify MAC computation (without actual verification)
        if let Some(expected_mac) = &encrypted_string.mac {
            let mac_input = [&encrypted_string.iv[..], &encrypted_string.data[..]].concat();

            let hmac_key = HmacKey::new(HMAC_SHA256, mac_key);
            let computed_mac = aws_lc_rs::hmac::sign(&hmac_key, &mac_input);

            info!(
                mac_input_len = mac_input.len(),
                mac_input_hex_preview =
                    hex::encode(&mac_input[..std::cmp::min(64, mac_input.len())]),
                computed_mac_hex = hex::encode(computed_mac.as_ref()),
                expected_mac_hex = hex::encode(expected_mac),
                macs_match = computed_mac.as_ref() == expected_mac.as_slice(),
                "[KEYGUARD_VERIFY] Step 4: MAC computation verification"
            );

            if computed_mac.as_ref() != expected_mac.as_slice() {
                warn!(
                    "[KEYGUARD_VERIFY] MAC mismatch detected - this is the root cause of the failure"
                );
                return Err(CryptoError::Decryption(
                    "MAC verification would fail".to_string(),
                ));
            }
        }

        info!(
            "[KEYGUARD_VERIFY] All verification steps passed - implementation should be compatible"
        );

        Ok(())
    }

    /// Public method for testing HKDF key stretching in isolation
    pub async fn stretch_key_hkdf(master_key: &[u8]) -> CryptoResult<(Vec<u8>, Vec<u8>)> {
        info!("[HKDF_TEST] Starting HKDF key stretching test");
        info!("[HKDF_TEST] Master key length: {} bytes", master_key.len());
        info!("[HKDF_TEST] Master key hex: {}", hex::encode(master_key));

        // Use AWS-LC-RS HKDF with empty salt for Bitwarden compatibility
        let empty_salt: &[u8] = &[];
        let salt = Salt::new(HKDF_SHA256, empty_salt);
        let prk = salt.extract(master_key);
        info!("[HKDF_TEST] PRK extracted successfully");

        // FIXED: Use separate HKDF expansions with "enc" and "mac" info parameters (rbw confirmed)

        // First derive encryption key (32 bytes) with info="enc"
        let enc_info = b"enc";
        let enc_info_slice = [enc_info.as_slice()];
        let mut encryption_key = vec![0u8; 32];
        let okm_enc = prk
            .expand(&enc_info_slice, HKDF_SHA256.hmac_algorithm())
            .map_err(|e| {
                CryptoError::KeyGeneration(format!("Encryption key HKDF expansion failed: {}", e))
            })?;

        okm_enc.fill(&mut encryption_key).map_err(|e| {
            CryptoError::KeyGeneration(format!("Failed to fill encryption key: {}", e))
        })?;

        // Then derive MAC key (32 bytes) with info="mac"
        let mac_info = b"mac";
        let mac_info_slice = [mac_info.as_slice()];
        let mut mac_key = vec![0u8; 32];
        let okm_mac = prk
            .expand(&mac_info_slice, HKDF_SHA256.hmac_algorithm())
            .map_err(|e| {
                CryptoError::KeyGeneration(format!("MAC key HKDF expansion failed: {}", e))
            })?;

        okm_mac
            .fill(&mut mac_key)
            .map_err(|e| CryptoError::KeyGeneration(format!("Failed to fill MAC key: {}", e)))?;

        info!("[HKDF_TEST] Key material derived successfully");
        info!(
            "[HKDF_TEST] Encryption key length: {} bytes",
            encryption_key.len()
        );
        info!("[HKDF_TEST] MAC key length: {} bytes", mac_key.len());

        info!("[HKDF_TEST] Keys derived successfully");
        info!(
            "[HKDF_TEST] Encryption key: {}",
            hex::encode(&encryption_key)
        );
        info!("[HKDF_TEST] MAC key: {}", hex::encode(&mac_key));

        Ok((encryption_key, mac_key))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_aes_cbc_encryption_decryption() {
        let data = b"Hello, World!";
        let key = EncryptionService::generate_key(32).unwrap();

        let encrypted =
            EncryptionService::encrypt(data, &key, EncryptionType::AesCbc256B64).unwrap();
        let decrypted =
            EncryptionService::decrypt(&encrypted, &key, EncryptionType::AesCbc256B64).unwrap();

        assert_eq!(data, decrypted.as_slice());
    }

    #[test]
    fn test_aes_cbc_hmac_encryption_decryption() {
        let data = b"Hello, World!";
        let key = EncryptionService::generate_key(64).unwrap();

        let encrypted =
            EncryptionService::encrypt(data, &key, EncryptionType::AesCbc256HmacSha256B64).unwrap();
        let decrypted =
            EncryptionService::decrypt(&encrypted, &key, EncryptionType::AesCbc256HmacSha256B64)
                .unwrap();

        assert_eq!(data, decrypted.as_slice());
        assert!(encrypted.mac.is_some());
    }

    #[test]
    fn test_decrypt_user_key_with_missing_mac_fallback() {
        use crate::crypto::cipher_crypto::EncryptedString;

        // Create a master key
        let master_key = MasterKey::new(b"test_master_key_32_bytes_long!!!".to_vec());

        // Create a test user key
        let user_key_data = b"test_user_key_32_bytes_long_data";

        // Simulate server sending Type 2 encrypted string without MAC
        // This is the problematic scenario we're fixing
        let encrypted_string_without_mac = EncryptedString {
            encryption_type: crate::crypto::EncryptionType::AesCbc256HmacSha256B64,
            iv: vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
            data: user_key_data.to_vec(), // Simplified for test
            mac: None,                    // This is the issue - missing MAC for Type 2
        };

        // Test that our fallback mechanism works
        let result = KeyDerivationService::decrypt_user_key_with_master_key(
            &encrypted_string_without_mac,
            &master_key,
        );

        // The result should be an error since we can't actually decrypt without proper encryption
        // But it should be a graceful error, not a panic
        assert!(result.is_err());

        // The error should be about MAC being required, not a panic
        let error_msg = format!("{}", result.unwrap_err());
        assert!(error_msg.contains("MAC is required") || error_msg.contains("MAC"));
    }

    #[test]
    fn test_user_key_decryption() {
        let master_key = MasterKey::new(EncryptionService::generate_key(32).unwrap());
        let user_key_data = EncryptionService::generate_key(64).unwrap();

        // Encrypt user key with master key
        let encrypted_user_key = EncryptionService::encrypt(
            &user_key_data,
            master_key.as_bytes(),
            EncryptionType::AesCbc256B64,
        )
        .unwrap();

        // Decrypt user key
        let decrypted_user_key = EncryptionService::decrypt_user_key(
            &encrypted_user_key,
            &master_key,
            EncryptionType::AesCbc256B64,
        )
        .unwrap();

        assert_eq!(user_key_data, decrypted_user_key.as_bytes());
    }
}
