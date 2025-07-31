use crate::crypto::{CryptoError, EncryptedData, EncryptionService, EncryptionType, UserKey};
use crate::error::{AppError, AppResult};
use base64::{engine::general_purpose, Engine as _};
use serde_json::Value;
use tracing::{debug, warn};

/// Bitwarden encrypted string format
/// Format: {type}.{iv}|{data}|{mac} or {type}.{iv}|{data}
#[derive(Debug, Clone)]
pub struct EncryptedString {
    pub encryption_type: EncryptionType,
    pub iv: Vec<u8>,
    pub data: Vec<u8>,
    pub mac: Option<Vec<u8>>,
}

impl EncryptedString {
    /// Parse a Bitwarden encrypted string
    pub fn from_string(encrypted_str: &str) -> AppResult<Self> {
        let parts: Vec<&str> = encrypted_str.split('.').collect();
        if parts.len() != 2 {
            return Err(AppError::CryptographyError {
                operation: "parse_encrypted_string".to_string(),
            });
        }

        // Parse encryption type
        let encryption_type = match parts[0] {
            "0" => EncryptionType::AesCbc256B64,
            "2" => EncryptionType::AesCbc256HmacSha256B64,
            _ => {
                return Err(AppError::CryptographyError {
                    operation: "unsupported_encryption_type".to_string(),
                });
            }
        };

        // Parse data components
        let data_parts: Vec<&str> = parts[1].split('|').collect();
        if data_parts.len() < 2 {
            return Err(AppError::CryptographyError {
                operation: "invalid_encrypted_string_format".to_string(),
            });
        }

        let iv = general_purpose::STANDARD
            .decode(data_parts[0])
            .map_err(|_| AppError::CryptographyError {
                operation: "decode_iv".to_string(),
            })?;

        let data = general_purpose::STANDARD
            .decode(data_parts[1])
            .map_err(|_| AppError::CryptographyError {
                operation: "decode_data".to_string(),
            })?;

        let mac = if data_parts.len() > 2 {
            Some(
                general_purpose::STANDARD
                    .decode(data_parts[2])
                    .map_err(|_| AppError::CryptographyError {
                        operation: "decode_mac".to_string(),
                    })?,
            )
        } else {
            None
        };

        Ok(EncryptedString {
            encryption_type,
            iv,
            data,
            mac,
        })
    }

    /// Convert to EncryptedData for decryption
    pub fn to_encrypted_data(&self) -> EncryptedData {
        EncryptedData {
            iv: self.iv.clone(),
            data: self.data.clone(),
            mac: self.mac.clone(),
        }
    }

    /// Convert EncryptedData to Bitwarden encrypted string format
    pub fn from_encrypted_data(
        encrypted_data: &EncryptedData,
        encryption_type: EncryptionType,
    ) -> String {
        use base64::{engine::general_purpose, Engine as _};

        let type_prefix = match encryption_type {
            EncryptionType::AesCbc256B64 => "0",
            EncryptionType::AesCbc256HmacSha256B64 => "2",
        };

        let iv_b64 = general_purpose::STANDARD.encode(&encrypted_data.iv);
        let data_b64 = general_purpose::STANDARD.encode(&encrypted_data.data);

        if let Some(mac) = &encrypted_data.mac {
            let mac_b64 = general_purpose::STANDARD.encode(mac);
            format!("{}.{}|{}|{}", type_prefix, iv_b64, data_b64, mac_b64)
        } else {
            format!("{}.{}|{}", type_prefix, iv_b64, data_b64)
        }
    }
}

/// Cipher decryption utilities
pub struct CipherCrypto;

impl CipherCrypto {
    /// Get the best encrypted value from multiple possible sources
    /// Priority: type-specific > data object > top-level
    /// This handles the dual data structure in Vaultwarden API responses
    pub fn get_encrypted_field<'a>(
        top_level: Option<&'a str>,
        data_object: Option<&'a str>,
        type_specific: Option<&'a str>,
    ) -> Option<&'a str> {
        // Priority: type-specific > data object > top-level
        type_specific.or(data_object).or(top_level)
    }

    /// Check if a string looks like a valid Bitwarden encrypted string
    /// Valid format: {type}.{iv}|{data}|{mac} or {type}.{iv}|{data}
    fn is_valid_encrypted_string_format(encrypted_str: &str) -> bool {
        // Basic format check: must contain a dot and at least one pipe
        if !encrypted_str.contains('.') || !encrypted_str.contains('|') {
            return false;
        }

        // Split by dot to check type prefix
        let parts: Vec<&str> = encrypted_str.split('.').collect();
        if parts.len() != 2 {
            return false;
        }

        // Check if the first part is a valid encryption type
        match parts[0] {
            "0" | "2" => {
                // Check if the second part has the right structure
                let data_parts: Vec<&str> = parts[1].split('|').collect();
                // Should have at least 2 parts (iv|data) and optionally 3 (iv|data|mac)
                data_parts.len() >= 2 && data_parts.len() <= 3
            }
            _ => false,
        }
    }

    /// Decrypt a Bitwarden encrypted string with enhanced error handling
    /// Following rbw's approach: gracefully handle parsing failures
    pub fn decrypt_string(encrypted_str: &str, user_key: &UserKey) -> AppResult<String> {
        if encrypted_str.is_empty() {
            return Ok(String::new());
        }

        // Check if the string looks like a valid Bitwarden encrypted string
        // Valid format: {type}.{iv}|{data}|{mac} or {type}.{iv}|{data}
        if !Self::is_valid_encrypted_string_format(encrypted_str) {
            warn!(
                encrypted_string = encrypted_str,
                string_length = encrypted_str.len(),
                "[CIPHER_DECRYPT] String does not match Bitwarden encrypted format - treating as plaintext or invalid"
            );

            // If it's clearly not an encrypted string (like "asd"), return it as-is or error
            // This prevents the parsing error that was causing issues
            if encrypted_str.len() < 10
                || !encrypted_str.contains('.')
                || !encrypted_str.contains('|')
            {
                return Err(AppError::CryptoError {
                    message: format!(
                        "String '{}' is not a valid Bitwarden encrypted string",
                        encrypted_str
                    ),
                });
            }
        }

        // Parse encrypted string with rbw-style error handling
        let enc_string = match EncryptedString::from_string(encrypted_str) {
            Ok(enc_string) => enc_string,
            Err(e) => {
                // Following rbw's approach: log warning and return error for graceful handling
                warn!(
                    encrypted_string = encrypted_str,
                    error = %e,
                    string_length = encrypted_str.len(),
                    "[CIPHER_DECRYPT] Failed to parse encrypted string - treating as invalid"
                );
                return Err(AppError::CryptoError {
                    message: format!("Invalid encrypted string format: {}", e),
                });
            }
        };

        let encrypted_data = enc_string.to_encrypted_data();

        // Attempt decryption with detailed error classification
        let decrypted_bytes = match EncryptionService::decrypt(
            &encrypted_data,
            user_key.as_bytes(),
            enc_string.encryption_type,
        ) {
            Ok(bytes) => bytes,
            Err(crypto_error) => {
                // Classify the crypto error based on its type
                return Self::classify_decryption_error(crypto_error, "decrypt_string");
            }
        };

        // Convert to UTF-8 with proper error handling
        String::from_utf8(decrypted_bytes).map_err(|utf8_error| {
            AppError::permanent_decryption_error(
                "utf8_conversion".to_string(),
                format!("Invalid UTF-8 in decrypted data: {}", utf8_error),
            )
        })
    }

    /// Decrypt a Bitwarden encrypted string to bytes (for key derivation)
    pub fn decrypt_bytes(
        encrypted_string: &EncryptedString,
        key: &[u8],
    ) -> Result<Vec<u8>, CryptoError> {
        use tracing::debug;

        // DEBUG STEP 7: Log cipher crypto decryption details
        debug!(
            encryption_type = ?encrypted_string.encryption_type,
            key_len = key.len(),
            key_preview = format!("{:02x?}", &key[..std::cmp::min(8, key.len())]),
            has_mac = encrypted_string.mac.is_some(),
            iv_len = encrypted_string.iv.len(),
            data_len = encrypted_string.data.len(),
            mac_len = encrypted_string.mac.as_ref().map(|m| m.len()),
            "[DEBUG_MAC] Step 7a: CipherCrypto decrypt_bytes called"
        );

        let encrypted_data = encrypted_string.to_encrypted_data();

        // DEBUG STEP 7: Log encrypted data conversion
        debug!(
            encrypted_data_iv_len = encrypted_data.iv.len(),
            encrypted_data_data_len = encrypted_data.data.len(),
            encrypted_data_has_mac = encrypted_data.mac.is_some(),
            encrypted_data_mac_len = encrypted_data.mac.as_ref().map(|m| m.len()),
            "[DEBUG_MAC] Step 7b: Converted to EncryptedData format"
        );

        // DEBUG STEP 7: Log before calling EncryptionService::decrypt
        debug!(
            final_encryption_type = ?encrypted_string.encryption_type,
            "[DEBUG_MAC] Step 7c: About to call EncryptionService::decrypt"
        );

        let result =
            EncryptionService::decrypt(&encrypted_data, key, encrypted_string.encryption_type);

        // DEBUG STEP 7: Log decryption result
        match &result {
            Ok(decrypted) => {
                debug!(
                    decrypted_len = decrypted.len(),
                    "[DEBUG_MAC] Step 7d: Decryption successful"
                );
            }
            Err(e) => {
                debug!(
                    error = %e,
                    "[DEBUG_MAC] Step 7d: Decryption failed - this is where MAC verification fails"
                );
            }
        }

        result
    }

    /// Classify decryption errors based on their characteristics
    fn classify_decryption_error(crypto_error: CryptoError, operation: &str) -> AppResult<String> {
        let error_msg = format!("{}", crypto_error);

        // Check for MAC verification failures (potentially transient)
        if error_msg.contains("MAC verification failed") || error_msg.contains("MAC") {
            return Err(AppError::mac_verification_error(
                operation.to_string(),
                "MAC verification failed - could be data corruption or key mismatch".to_string(),
            ));
        }

        // Check for key-related errors (permanent)
        if error_msg.contains("key") || error_msg.contains("invalid") {
            return Err(AppError::key_validation_error(
                "user_key".to_string(),
                format!("Key validation failed during {}: {}", operation, error_msg),
            ));
        }

        // Check for decryption failures (potentially transient)
        if error_msg.contains("decrypt") || error_msg.contains("cipher") {
            return Err(AppError::transient_decryption_error(
                operation.to_string(),
                format!("Decryption operation failed: {}", error_msg),
                1,
            ));
        }

        // Default to permanent error for unknown issues
        Err(AppError::permanent_decryption_error(
            operation.to_string(),
            format!("Crypto operation failed: {}", error_msg),
        ))
    }

    /// Decrypt string with retry mechanism for transient failures
    pub async fn decrypt_string_with_retry(
        encrypted_str: &str,
        user_key: &UserKey,
        max_retries: u32,
    ) -> AppResult<String> {
        let mut last_error = None;

        for attempt in 0..=max_retries {
            match Self::decrypt_string(encrypted_str, user_key) {
                Ok(result) => return Ok(result),
                Err(error) => {
                    // Only retry for transient errors
                    if error.is_retryable() && attempt < max_retries {
                        let delay = error.retry_delay(attempt).unwrap_or(1000);
                        debug!(
                            attempt = attempt + 1,
                            max_retries = max_retries,
                            delay_ms = delay,
                            error = %error,
                            "[crypto] Retrying decryption after transient failure"
                        );
                        tokio::time::sleep(std::time::Duration::from_millis(delay)).await;
                        last_error = Some(error);
                    } else {
                        // Non-retryable error or max retries exceeded
                        return Err(error);
                    }
                }
            }
        }

        // This should never be reached, but handle it gracefully
        Err(last_error.unwrap_or_else(|| {
            AppError::permanent_decryption_error(
                "decrypt_string_with_retry".to_string(),
                "Max retries exceeded".to_string(),
            )
        }))
    }

    /// Decrypt an optional string field
    pub fn decrypt_optional_string(
        encrypted_str: &Option<String>,
        user_key: &UserKey,
    ) -> AppResult<Option<String>> {
        match encrypted_str {
            Some(s) if !s.is_empty() => Ok(Some(Self::decrypt_string(s, user_key)?)),
            _ => Ok(None),
        }
    }

    /// Decrypt cipher data JSON with enhanced error handling
    pub fn decrypt_cipher_data(encrypted_data_json: &str, user_key: &UserKey) -> AppResult<Value> {
        if encrypted_data_json.is_empty() {
            return Ok(Value::Null);
        }

        // Try to parse as JSON first with better error context
        let data: Value = serde_json::from_str(encrypted_data_json).map_err(|e| {
            debug!("Failed to parse cipher data as JSON: {}", e);
            AppError::permanent_decryption_error(
                "parse_cipher_data_json".to_string(),
                format!("Invalid JSON in cipher data: {}", e),
            )
        })?;

        Self::decrypt_json_value(&data, user_key)
    }

    /// Recursively decrypt JSON values
    fn decrypt_json_value(value: &Value, user_key: &UserKey) -> AppResult<Value> {
        match value {
            Value::String(s) => {
                // Check if this looks like an encrypted string (contains dots and pipes)
                if s.contains('.') && s.contains('|') {
                    match Self::decrypt_string(s, user_key) {
                        Ok(decrypted) => Ok(Value::String(decrypted)),
                        Err(e) => {
                            // Following rbw's approach: log warning and return original string
                            // This allows processing to continue for other fields
                            warn!(
                                encrypted_string = s,
                                error = %e,
                                string_length = s.len(),
                                "[CIPHER_DECRYPT] Failed to decrypt field - keeping original value"
                            );

                            // Return the original string to allow processing to continue
                            // This matches rbw's behavior of graceful degradation
                            Ok(Value::String(s.clone()))
                        }
                    }
                } else {
                    Ok(Value::String(s.clone()))
                }
            }
            Value::Object(map) => {
                let mut decrypted_map = serde_json::Map::new();
                for (key, val) in map {
                    decrypted_map.insert(key.clone(), Self::decrypt_json_value(val, user_key)?);
                }
                Ok(Value::Object(decrypted_map))
            }
            Value::Array(arr) => {
                let mut decrypted_arr = Vec::new();
                for item in arr {
                    decrypted_arr.push(Self::decrypt_json_value(item, user_key)?);
                }
                Ok(Value::Array(decrypted_arr))
            }
            _ => Ok(value.clone()),
        }
    }

    /// Validate decryption context and provide debugging information
    pub fn validate_decryption_context(
        encrypted_str: &str,
        user_key: &UserKey,
        context: &str,
    ) -> AppResult<()> {
        // Basic validation
        if encrypted_str.is_empty() {
            return Err(AppError::validation_error(
                "encrypted_string".to_string(),
                format!("Empty encrypted string in context: {}", context),
            ));
        }

        if user_key.as_bytes().is_empty() {
            return Err(AppError::key_validation_error(
                "user_key".to_string(),
                format!("Empty user key in context: {}", context),
            ));
        }

        // Try to parse the encrypted string format
        match EncryptedString::from_string(encrypted_str) {
            Ok(enc_string) => {
                debug!(
                    context = context,
                    encryption_type = ?enc_string.encryption_type,
                    data_length = encrypted_str.len(),
                    "[crypto] Decryption context validated successfully"
                );
                Ok(())
            }
            Err(e) => Err(AppError::permanent_decryption_error(
                "validate_context".to_string(),
                format!("Invalid encrypted string format in {}: {}", context, e),
            )),
        }
    }

    /// Get detailed error information for debugging
    pub fn get_decryption_debug_info(
        encrypted_str: &str,
        error: &AppError,
        context: &str,
    ) -> String {
        let mut debug_info = Vec::new();

        debug_info.push(format!("Context: {}", context));
        debug_info.push(format!("Error: {}", error));
        debug_info.push(format!("Encrypted string length: {}", encrypted_str.len()));

        if let Ok(enc_string) = EncryptedString::from_string(encrypted_str) {
            debug_info.push(format!("Encryption type: {:?}", enc_string.encryption_type));
            let encrypted_data = enc_string.to_encrypted_data();
            debug_info.push(format!("IV length: {}", encrypted_data.iv.len()));
            debug_info.push(format!("Data length: {}", encrypted_data.data.len()));
            debug_info.push(format!("Has MAC: {}", encrypted_data.mac.is_some()));
        } else {
            debug_info.push("Failed to parse encrypted string format".to_string());
        }

        debug_info.join(" | ")
    }

    /// Check if an error indicates a recoverable decryption failure
    pub fn is_recoverable_error(error: &AppError) -> bool {
        matches!(
            error,
            AppError::MacVerificationError { .. }
                | AppError::TransientDecryptionError { .. }
                | AppError::CacheError { .. }
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_encrypted_string() {
        let encrypted_str = "2.dGVzdGl2MTIzNDU2Nzg=|dGVzdGRhdGE=|dGVzdG1hYw==";
        let result = EncryptedString::from_string(encrypted_str);
        assert!(result.is_ok());

        let enc_string = result.unwrap();
        assert!(matches!(
            enc_string.encryption_type,
            EncryptionType::AesCbc256HmacSha256B64
        ));
        assert!(enc_string.mac.is_some());
    }

    #[test]
    fn test_parse_encrypted_string_no_mac() {
        let encrypted_str = "0.dGVzdGl2MTIzNDU2Nzg=|dGVzdGRhdGE=";
        let result = EncryptedString::from_string(encrypted_str);
        assert!(result.is_ok());

        let enc_string = result.unwrap();
        assert!(matches!(
            enc_string.encryption_type,
            EncryptionType::AesCbc256B64
        ));
        assert!(enc_string.mac.is_none());
    }

    #[test]
    fn test_parse_failing_cipher_string() {
        // Test the actual failing cipher string from the database
        let encrypted_str = "2.4oAzBrcGojRfTFXaTp5jIQ==|hxYbtXAWgp0kCiYlXE1zPA==|Q+7klJZY3vTFU2/PgMFGADUUN2UAL65XfC8ff57inhU=";
        let result = EncryptedString::from_string(encrypted_str);

        match &result {
            Ok(enc_string) => {
                println!("Successfully parsed failing cipher string:");
                println!("  Encryption type: {:?}", enc_string.encryption_type);
                println!("  IV length: {}", enc_string.iv.len());
                println!("  Data length: {}", enc_string.data.len());
                println!(
                    "  MAC length: {:?}",
                    enc_string.mac.as_ref().map(|m| m.len())
                );
            }
            Err(e) => {
                println!("Failed to parse failing cipher string: {:?}", e);
            }
        }

        assert!(
            result.is_ok(),
            "Should be able to parse the failing cipher string"
        );

        let enc_string = result.unwrap();
        assert!(matches!(
            enc_string.encryption_type,
            EncryptionType::AesCbc256HmacSha256B64
        ));
        assert!(enc_string.mac.is_some());
        assert_eq!(enc_string.iv.len(), 16);
        assert_eq!(enc_string.data.len(), 16);
        assert_eq!(enc_string.mac.as_ref().unwrap().len(), 32);
    }

    #[test]
    fn test_debug_cipher_decrypt_string() {
        use crate::crypto::UserKey;

        // Test the actual failing cipher string with CipherCrypto::decrypt_string
        let encrypted_str = "2.4oAzBrcGojRfTFXaTp5jIQ==|hxYbtXAWgp0kCiYlXE1zPA==|Q+7klJZY3vTFU2/PgMFGADUUN2UAL65XfC8ff57inhU=";

        // Create a dummy user key for testing (this will fail decryption but should pass parsing)
        let dummy_key = UserKey::new(vec![0u8; 64]);

        let result = CipherCrypto::decrypt_string(encrypted_str, &dummy_key);

        match &result {
            Ok(_) => {
                println!("Unexpectedly succeeded in decrypting with dummy key");
            }
            Err(e) => {
                println!("Expected decryption failure with dummy key: {:?}", e);
                // The error should NOT be a parsing error - it should be a decryption/MAC error
                let error_str = format!("{}", e);
                assert!(
                    !error_str.contains("Invalid encrypted string format"),
                    "Should not be a parsing error, got: {}",
                    error_str
                );
            }
        }
    }

    /// Decrypt an optional string field
    pub fn decrypt_optional_string(
        encrypted_str: &Option<String>,
        user_key: &UserKey,
    ) -> AppResult<Option<String>> {
        if let Some(encrypted) = encrypted_str {
            if !encrypted.is_empty() {
                return Ok(Some(CipherCrypto::decrypt_string(encrypted, user_key)?));
            }
        }
        Ok(None)
    }
}
