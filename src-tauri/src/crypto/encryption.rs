use super::{CryptoError, CryptoResult, EncryptedData, EncryptionType, MasterKey, UserKey};
use crate::logging::log_crypto_operation;
use aes::Aes256;
use cbc::cipher::{BlockDecryptMut, BlockEncryptMut, KeyIvInit};
use cbc::{Decryptor, Encryptor};
use hmac::{Hmac, Mac};
use rand::{rngs::OsRng, RngCore};
use sha2::Sha256;
use tracing::{debug, info};

type HmacSha256 = Hmac<Sha256>;

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
        debug!(
            encryption_type = ?encryption_type,
            data_size = encrypted_data.data.len(),
            "[crypto] Starting decryption operation"
        );

        let result = match encryption_type {
            EncryptionType::AesCbc256B64 => Self::decrypt_aes_cbc(encrypted_data, key),
            EncryptionType::AesCbc256HmacSha256B64 => {
                Self::decrypt_aes_cbc_hmac(encrypted_data, key)
            }
        };

        let success = result.is_ok();
        if success {
            info!(
                encryption_type = ?encryption_type,
                data_size = encrypted_data.data.len(),
                "[crypto] Decryption completed successfully"
            );
            log_crypto_operation("decrypt", true, None);
        } else {
            let error_msg = result.as_ref().err().map(|e| e.to_string());
            log_crypto_operation("decrypt", false, error_msg.as_deref());
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

        let mut iv = [0u8; 16];
        OsRng.fill_bytes(&mut iv);

        let cipher = Encryptor::<Aes256>::new_from_slices(key, &iv)
            .map_err(|e| CryptoError::Encryption(format!("Failed to create cipher: {}", e)))?;

        // Create a buffer with PKCS7 padding
        let mut buffer = data.to_vec();
        let block_size = 16;
        let padding_len = block_size - (buffer.len() % block_size);
        buffer.extend(vec![padding_len as u8; padding_len]);

        // Encrypt the padded data
        let encrypted_data = cipher
            .encrypt_padded_mut::<cbc::cipher::block_padding::Pkcs7>(&mut buffer, data.len())
            .map_err(|e| CryptoError::Encryption(format!("Encryption failed: {}", e)))?
            .to_vec();

        Ok(EncryptedData {
            iv: iv.to_vec(),
            data: encrypted_data,
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

        let mut iv = [0u8; 16];
        OsRng.fill_bytes(&mut iv);

        let cipher = Encryptor::<Aes256>::new_from_slices(enc_key, &iv)
            .map_err(|e| CryptoError::Encryption(format!("Failed to create cipher: {}", e)))?;

        // Create a buffer with PKCS7 padding
        let mut buffer = data.to_vec();
        let block_size = 16;
        let padding_len = block_size - (buffer.len() % block_size);
        buffer.extend(vec![padding_len as u8; padding_len]);

        let encrypted_data = cipher
            .encrypt_padded_mut::<cbc::cipher::block_padding::Pkcs7>(&mut buffer, data.len())
            .map_err(|e| CryptoError::Encryption(format!("Encryption failed: {}", e)))?
            .to_vec();

        // Calculate HMAC over IV + encrypted data
        let mut mac = HmacSha256::new_from_slice(mac_key)
            .map_err(|e| CryptoError::Encryption(format!("Failed to create HMAC: {}", e)))?;
        mac.update(&iv);
        mac.update(&encrypted_data);
        let mac_result = mac.finalize().into_bytes();

        Ok(EncryptedData {
            iv: iv.to_vec(),
            data: encrypted_data,
            mac: Some(mac_result.to_vec()),
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

        let cipher = Decryptor::<Aes256>::new_from_slices(key, &encrypted_data.iv)
            .map_err(|e| CryptoError::Decryption(format!("Failed to create cipher: {}", e)))?;

        let mut buffer = encrypted_data.data.clone();
        let decrypted_data = cipher
            .decrypt_padded_mut::<cbc::cipher::block_padding::Pkcs7>(&mut buffer)
            .map_err(|e| CryptoError::Decryption(format!("Failed to decrypt: {}", e)))?;

        Ok(decrypted_data.to_vec())
    }

    /// Decrypt using AES-256-CBC with HMAC-SHA256 verification
    fn decrypt_aes_cbc_hmac(encrypted_data: &EncryptedData, key: &[u8]) -> CryptoResult<Vec<u8>> {
        if key.len() != 64 {
            return Err(CryptoError::InvalidParameters(
                "Key must be 64 bytes for HMAC".to_string(),
            ));
        }

        let mac = encrypted_data
            .mac
            .as_ref()
            .ok_or_else(|| CryptoError::InvalidParameters("MAC is required".to_string()))?;

        let (enc_key, mac_key) = key.split_at(32);

        // Verify HMAC
        let mut hmac = HmacSha256::new_from_slice(mac_key)
            .map_err(|e| CryptoError::Decryption(format!("Failed to create HMAC: {}", e)))?;
        hmac.update(&encrypted_data.iv);
        hmac.update(&encrypted_data.data);

        hmac.verify_slice(mac)
            .map_err(|_| CryptoError::Decryption("MAC verification failed".to_string()))?;

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
        let key_bytes = match encryption_type {
            EncryptionType::AesCbc256B64 => {
                Self::decrypt(encrypted_user_key, master_key.as_bytes(), encryption_type)?
            }
            EncryptionType::AesCbc256HmacSha256B64 => {
                // Stretch the master key for HMAC variant
                let stretched_key = Self::stretch_key(master_key)?;
                Self::decrypt(encrypted_user_key, &stretched_key, encryption_type)?
            }
        };

        Ok(UserKey::new(key_bytes))
    }

    /// Encrypt user key with master key
    pub fn encrypt_user_key(
        user_key: &UserKey,
        master_key: &MasterKey,
    ) -> CryptoResult<EncryptedData> {
        // Use AES-256-CBC with HMAC-SHA256 for user key encryption
        let stretched_key = Self::stretch_key(master_key)?;
        Self::encrypt(
            user_key.as_bytes(),
            &stretched_key,
            EncryptionType::AesCbc256HmacSha256B64,
        )
    }

    /// Stretch a 32-byte key to 64 bytes using HKDF
    fn stretch_key(master_key: &MasterKey) -> CryptoResult<Vec<u8>> {
        use hkdf::Hkdf;

        let hk = Hkdf::<Sha256>::new(None, master_key.as_bytes());
        let mut stretched = [0u8; 64];
        hk.expand(b"bitwarden-key-stretch", &mut stretched)
            .map_err(|e| CryptoError::KeyGeneration(format!("Key stretching failed: {}", e)))?;

        Ok(stretched.to_vec())
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
