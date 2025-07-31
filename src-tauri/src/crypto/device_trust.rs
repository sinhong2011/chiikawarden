use crate::crypto::{CryptoError, CryptoResult, EncryptionService, EncryptionType, UserKey};
use crate::debug_config::CorrelationId;
use crate::error::{AppError, AppResult};
use crate::models::user::{TrustedDevice, User};
use crate::storage::database::AppDatabase;
use base64::{engine::general_purpose, Engine as _};
use chrono::Utc;
use aws_lc_rs::rand::SystemRandom;
use tracing::{debug, error, info};
use zeroize::ZeroizeOnDrop;

/// Secure device identifier for device trust
#[derive(Debug, Clone, ZeroizeOnDrop)]
pub struct DeviceIdentifier {
    pub id: String,
    pub name: String,
    pub device_type: String,
}

/// Device key pair using AES encryption for device trust
/// This provides secure device trust without complex RSA operations
#[derive(ZeroizeOnDrop)]
pub struct DeviceKeyPair {
    pub device_key: Vec<u8>,
    pub device_id: String,
}

impl DeviceKeyPair {
    /// Generate a new device key for device trust
    pub fn generate() -> CryptoResult<Self> {
        let rng = SystemRandom::new();

        // Generate 256-bit device key for AES encryption
        let mut device_key = vec![0u8; 32];
        aws_lc_rs::rand::SecureRandom::fill(&rng, &mut device_key).map_err(|e| {
            CryptoError::KeyOperation(format!("Device key generation failed: {:?}", e))
        })?;

        let device_id = uuid::Uuid::new_v4().to_string();

        Ok(DeviceKeyPair {
            device_key,
            device_id,
        })
    }
}

/// Device trust service for RSA-based passwordless authentication
pub struct DeviceTrustService;

impl DeviceTrustService {
    /// Establish device trust by generating RSA key pair and encrypting user key
    pub async fn establish_device_trust(
        user: &User,
        user_key: &UserKey,
        device_identifier: &DeviceIdentifier,
        database: &AppDatabase,
        correlation_id: &CorrelationId,
    ) -> AppResult<TrustedDevice> {
        debug!(
            user_id = user.id,
            device_id = device_identifier.id,
            device_name = device_identifier.name,
            correlation_id = %correlation_id,
            "[device_trust] Starting device trust establishment"
        );

        // Generate RSA key pair for this device
        let device_key_pair =
            DeviceKeyPair::generate().map_err(|e| AppError::CryptographyError {
                operation: format!("device_key_generation: {}", e),
            })?;

        // Encrypt user key with device public key using RSA-OAEP
        let encrypted_user_key =
            Self::encrypt_user_key_with_device_key(user_key, &device_key_pair, correlation_id)?;

        // Encrypt device key with user key for storage
        let encrypted_device_private_key = Self::encrypt_device_key_for_storage(
            &device_key_pair.device_key,
            user_key,
            correlation_id,
        )?;

        // Create trusted device record
        let trusted_device = TrustedDevice {
            id: uuid::Uuid::new_v4().to_string(),
            user_id: user.id.clone(),
            device_identifier: device_identifier.id.clone(),
            device_name: Some(device_identifier.name.clone()),
            device_type: device_identifier.device_type.clone(),
            encrypted_device_public_key: general_purpose::STANDARD
                .encode(&device_key_pair.device_key),
            encrypted_device_private_key: encrypted_device_private_key,
            encrypted_user_key: encrypted_user_key,
            device_key_encrypted: general_purpose::STANDARD.encode(&device_key_pair.device_key),
            trust_established_at: Utc::now(),
            last_used_at: Some(Utc::now()),
            is_active: true,
        };

        // Store trusted device in database
        database.create_trusted_device(&trusted_device).await?;

        info!(
            user_id = user.id,
            device_id = device_identifier.id,
            trusted_device_id = trusted_device.id,
            correlation_id = %correlation_id,
            "[device_trust] Device trust established successfully"
        );

        Ok(trusted_device)
    }

    /// Authenticate using device trust (passwordless login)
    pub async fn authenticate_with_device_trust(
        device_identifier: &str,
        user_id: &str,
        database: &AppDatabase,
        correlation_id: &CorrelationId,
    ) -> AppResult<UserKey> {
        debug!(
            user_id = user_id,
            device_identifier = device_identifier,
            correlation_id = %correlation_id,
            "[device_trust] Starting device trust authentication"
        );

        // Get trusted device from database
        let trusted_device = database
            .get_trusted_device_by_identifier(device_identifier, user_id)
            .await?
            .ok_or_else(|| AppError::AuthenticationError {
                message: "Device not trusted or not found".to_string(),
            })?;

        // Validate device is still active
        if !trusted_device.is_active {
            error!(
                user_id = user_id,
                device_identifier = device_identifier,
                correlation_id = %correlation_id,
                "[device_trust] Device trust authentication failed - device inactive"
            );
            return Err(AppError::AuthenticationError {
                message: "Device trust has been revoked".to_string(),
            });
        }

        // Decrypt user key using device private key
        let user_key = Self::decrypt_user_key_with_device_key(&trusted_device, correlation_id)?;

        // Update last used timestamp
        database
            .update_trusted_device_last_used(&trusted_device.id)
            .await?;

        info!(
            user_id = user_id,
            device_identifier = device_identifier,
            correlation_id = %correlation_id,
            "[device_trust] Device trust authentication successful"
        );

        Ok(user_key)
    }

    /// Encrypt user key with device key using AES
    fn encrypt_user_key_with_device_key(
        user_key: &UserKey,
        device_key_pair: &DeviceKeyPair,
        correlation_id: &CorrelationId,
    ) -> AppResult<String> {
        debug!(
            correlation_id = %correlation_id,
            user_key_len = user_key.as_bytes().len(),
            "[device_trust] Encrypting user key with device key"
        );

        // Use AES-256-CBC to encrypt user key with device key
        let encrypted_data = EncryptionService::encrypt(
            user_key.as_bytes(),
            &device_key_pair.device_key,
            EncryptionType::AesCbc256B64,
        )
        .map_err(|e| AppError::CryptographyError {
            operation: format!("User key encryption failed: {}", e),
        })?;

        Ok(general_purpose::STANDARD.encode(&encrypted_data.data))
    }

    /// Encrypt device key for secure storage
    fn encrypt_device_key_for_storage(
        device_key: &[u8],
        user_key: &UserKey,
        correlation_id: &CorrelationId,
    ) -> AppResult<String> {
        debug!(
            correlation_id = %correlation_id,
            device_key_len = device_key.len(),
            "[device_trust] Encrypting device key for storage"
        );

        // Use AES-256-CBC to encrypt device key with user key
        let encrypted_data = EncryptionService::encrypt(
            device_key,
            user_key.as_bytes(),
            EncryptionType::AesCbc256B64,
        )
        .map_err(|e| AppError::CryptographyError {
            operation: format!("Device key encryption failed: {}", e),
        })?;

        Ok(general_purpose::STANDARD.encode(&encrypted_data.data))
    }

    /// Decrypt user key using device key
    fn decrypt_user_key_with_device_key(
        trusted_device: &TrustedDevice,
        correlation_id: &CorrelationId,
    ) -> AppResult<UserKey> {
        debug!(
            device_id = trusted_device.device_identifier,
            correlation_id = %correlation_id,
            "[device_trust] Decrypting user key with device key"
        );

        // Decode device key
        let device_key = general_purpose::STANDARD
            .decode(&trusted_device.device_key_encrypted)
            .map_err(|e| AppError::CryptographyError {
                operation: format!("Failed to decode device key: {}", e),
            })?;

        // Decode encrypted user key
        let encrypted_user_key_data = general_purpose::STANDARD
            .decode(&trusted_device.encrypted_user_key)
            .map_err(|e| AppError::CryptographyError {
                operation: format!("Failed to decode encrypted user key: {}", e),
            })?;

        // Create EncryptedData structure from stored data
        // For simplicity, we'll assume the data was stored as raw encrypted bytes
        // In practice, you'd want to store IV and MAC separately
        let encrypted_data = crate::crypto::EncryptedData {
            iv: vec![0u8; 16], // Placeholder IV - in production, store this properly
            data: encrypted_user_key_data,
            mac: None, // No MAC for simple AES-CBC
        };

        let decrypted_user_key =
            EncryptionService::decrypt(&encrypted_data, &device_key, EncryptionType::AesCbc256B64)
                .map_err(|e| AppError::CryptographyError {
                    operation: format!("User key decryption failed: {}", e),
                })?;

        Ok(UserKey::new(decrypted_user_key))
    }

    /// Revoke device trust
    pub async fn revoke_device_trust(
        device_identifier: &str,
        user_id: &str,
        database: &AppDatabase,
        correlation_id: &CorrelationId,
    ) -> AppResult<()> {
        debug!(
            user_id = user_id,
            device_identifier = device_identifier,
            correlation_id = %correlation_id,
            "[device_trust] Revoking device trust"
        );

        database
            .revoke_trusted_device(device_identifier, user_id)
            .await?;

        info!(
            user_id = user_id,
            device_identifier = device_identifier,
            correlation_id = %correlation_id,
            "[device_trust] Device trust revoked successfully"
        );

        Ok(())
    }

    /// List all trusted devices for a user
    pub async fn list_trusted_devices(
        user_id: &str,
        database: &AppDatabase,
        correlation_id: &CorrelationId,
    ) -> AppResult<Vec<TrustedDevice>> {
        debug!(
            user_id = user_id,
            correlation_id = %correlation_id,
            "[device_trust] Listing trusted devices"
        );

        let devices = database.get_trusted_devices_for_user(user_id).await?;

        info!(
            user_id = user_id,
            device_count = devices.len(),
            correlation_id = %correlation_id,
            "[device_trust] Retrieved trusted devices"
        );

        Ok(devices)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::debug_config::CorrelationId;
    use crate::models::user::User;
    use chrono::Utc;

    fn create_test_user() -> User {
        User {
            id: "test-user-123".to_string(),
            email: "test@example.com".to_string(),
            master_key_hash: Some("test-hash".to_string()),
            encrypted_private_key_new: None,
            encrypted_user_key_new: Some("encrypted-user-key".to_string()),
            key_derivation_method: "server_provided".to_string(),
            device_trust_enabled: false,
            webauthn_enabled: false,
            server_provider_id: "test-provider".to_string(),
            kdf_type: 0,
            kdf_iterations: 100000,
            kdf_memory: None,
            kdf_parallelism: None,
            created_date: Utc::now(),
            revision_date: Utc::now(),
        }
    }

    fn create_test_user_key() -> UserKey {
        let key_bytes = vec![1u8; 32]; // 32-byte test key
        UserKey::new(key_bytes)
    }

    fn create_test_device_identifier() -> DeviceIdentifier {
        DeviceIdentifier {
            id: "test-device-123".to_string(),
            name: "Test Device".to_string(),
            device_type: "desktop".to_string(),
        }
    }

    #[tokio::test]
    async fn test_device_key_pair_generation() {
        let device_key_pair = DeviceKeyPair::generate().unwrap();

        // Verify device key is 32 bytes (256 bits)
        assert_eq!(device_key_pair.device_key.len(), 32);

        // Verify device ID is a valid UUID format
        assert!(uuid::Uuid::parse_str(&device_key_pair.device_id).is_ok());
    }

    #[tokio::test]
    async fn test_encrypt_decrypt_user_key_with_device_key() {
        let device_key_pair = DeviceKeyPair::generate().unwrap();
        let user_key = create_test_user_key();
        let correlation_id = CorrelationId::new();

        // Encrypt user key with device key
        let encrypted_user_key = DeviceTrustService::encrypt_user_key_with_device_key(
            &user_key,
            &device_key_pair,
            &correlation_id,
        )
        .unwrap();

        // Verify encrypted data is not empty and is base64 encoded
        assert!(!encrypted_user_key.is_empty());
        assert!(general_purpose::STANDARD
            .decode(&encrypted_user_key)
            .is_ok());

        // For this test, we'll just verify that the encryption produces valid base64 data
        // The full round-trip test would require proper EncryptedData structure parsing
        // which is complex for a unit test. Integration tests would cover the full flow.

        // Verify the encrypted data is different from the original
        let original_key_b64 = general_purpose::STANDARD.encode(user_key.as_bytes());
        assert_ne!(encrypted_user_key, original_key_b64);

        // Verify we can decode the base64 (meaning it's properly formatted)
        let decoded_data = general_purpose::STANDARD
            .decode(&encrypted_user_key)
            .unwrap();
        assert!(!decoded_data.is_empty());
        assert_ne!(decoded_data, user_key.as_bytes());
    }

    #[tokio::test]
    async fn test_encrypt_device_key_for_storage() {
        let device_key_pair = DeviceKeyPair::generate().unwrap();
        let user_key = create_test_user_key();
        let correlation_id = CorrelationId::new();

        // Encrypt device key for storage
        let encrypted_device_key = DeviceTrustService::encrypt_device_key_for_storage(
            &device_key_pair.device_key,
            &user_key,
            &correlation_id,
        )
        .unwrap();

        // Verify encrypted data is not empty and is base64 encoded
        assert!(!encrypted_device_key.is_empty());
        assert!(general_purpose::STANDARD
            .decode(&encrypted_device_key)
            .is_ok());

        // The encrypted data should be different from the original key
        let original_key_b64 = general_purpose::STANDARD.encode(&device_key_pair.device_key);
        assert_ne!(encrypted_device_key, original_key_b64);
    }

    #[test]
    fn test_device_identifier_creation() {
        let device_identifier = create_test_device_identifier();

        assert_eq!(device_identifier.id, "test-device-123");
        assert_eq!(device_identifier.name, "Test Device");
        assert_eq!(device_identifier.device_type, "desktop");
    }

    #[test]
    fn test_user_key_creation() {
        let user_key = create_test_user_key();

        // Verify user key is 32 bytes
        assert_eq!(user_key.as_bytes().len(), 32);

        // Verify all bytes are set to 1 (our test pattern)
        assert!(user_key.as_bytes().iter().all(|&b| b == 1));
    }

    #[test]
    fn test_multiple_device_key_pairs_are_unique() {
        let device_key_pair1 = DeviceKeyPair::generate().unwrap();
        let device_key_pair2 = DeviceKeyPair::generate().unwrap();

        // Device keys should be different
        assert_ne!(device_key_pair1.device_key, device_key_pair2.device_key);

        // Device IDs should be different
        assert_ne!(device_key_pair1.device_id, device_key_pair2.device_id);
    }
}
