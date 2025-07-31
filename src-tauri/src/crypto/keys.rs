use super::encryption::EncryptionService;
use super::{CryptoError, CryptoResult, UserKey};
use rand::rngs::OsRng;
use rsa::pkcs8::{DecodePrivateKey, DecodePublicKey, EncodePrivateKey, EncodePublicKey};

use rsa::{RsaPrivateKey, RsaPublicKey};
use serde::{Deserialize, Serialize};
use zeroize::Zeroize;

#[derive(Debug, Clone, Serialize, Deserialize, Zeroize)]
#[zeroize(drop)]
pub struct RsaKeyPair {
    pub public_key: Vec<u8>,
    pub private_key: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptedPrivateKey {
    pub encrypted_key: Vec<u8>,
    pub iv: Vec<u8>,
    pub mac: Vec<u8>,
}

pub struct KeyService;

impl KeyService {
    /// Generate a new user key (512-bit symmetric key)
    pub fn generate_user_key() -> CryptoResult<UserKey> {
        let key_bytes = EncryptionService::generate_key(64)?; // 512 bits
        Ok(UserKey::new(key_bytes))
    }

    /// Generate RSA key pair for asymmetric encryption
    pub fn generate_rsa_key_pair(bits: usize) -> CryptoResult<RsaKeyPair> {
        let mut rng = OsRng;

        let private_key = RsaPrivateKey::new(&mut rng, bits)
            .map_err(|e| CryptoError::KeyGeneration(format!("RSA key generation failed: {}", e)))?;

        let public_key = RsaPublicKey::from(&private_key);

        // Encode keys to DER format
        let private_key_der = private_key.to_pkcs8_der().map_err(|e| {
            CryptoError::KeyGeneration(format!("Private key encoding failed: {}", e))
        })?;

        let public_key_der = public_key.to_public_key_der().map_err(|e| {
            CryptoError::KeyGeneration(format!("Public key encoding failed: {}", e))
        })?;

        Ok(RsaKeyPair {
            public_key: public_key_der.as_bytes().to_vec(),
            private_key: private_key_der.as_bytes().to_vec(),
        })
    }

    /// Encrypt data with RSA public key
    pub fn rsa_encrypt(data: &[u8], public_key_der: &[u8]) -> CryptoResult<Vec<u8>> {
        let public_key = RsaPublicKey::from_public_key_der(public_key_der)
            .map_err(|e| CryptoError::Encryption(format!("Invalid public key: {}", e)))?;

        let mut rng = OsRng;
        let padding = rsa::Oaep::new::<sha2::Sha256>();

        let encrypted = public_key
            .encrypt(&mut rng, padding, data)
            .map_err(|e| CryptoError::Encryption(format!("RSA encryption failed: {}", e)))?;

        Ok(encrypted)
    }

    /// Decrypt data with RSA private key
    pub fn rsa_decrypt(encrypted_data: &[u8], private_key_der: &[u8]) -> CryptoResult<Vec<u8>> {
        let private_key = RsaPrivateKey::from_pkcs8_der(private_key_der)
            .map_err(|e| CryptoError::Decryption(format!("Invalid private key: {}", e)))?;

        let padding = rsa::Oaep::new::<sha2::Sha256>();

        let decrypted = private_key
            .decrypt(padding, encrypted_data)
            .map_err(|e| CryptoError::Decryption(format!("RSA decryption failed: {}", e)))?;

        Ok(decrypted)
    }

    /// Encrypt private key with user key
    pub fn encrypt_private_key(
        private_key_der: &[u8],
        user_key: &UserKey,
    ) -> CryptoResult<EncryptedPrivateKey> {
        use super::EncryptionType;

        let encrypted_data = EncryptionService::encrypt(
            private_key_der,
            user_key.as_bytes(),
            EncryptionType::AesCbc256HmacSha256B64,
        )?;

        Ok(EncryptedPrivateKey {
            encrypted_key: encrypted_data.data,
            iv: encrypted_data.iv,
            mac: encrypted_data.mac.unwrap_or_default(),
        })
    }

    /// Decrypt private key with user key
    pub fn decrypt_private_key(
        encrypted_private_key: &EncryptedPrivateKey,
        user_key: &UserKey,
    ) -> CryptoResult<Vec<u8>> {
        use super::{EncryptedData, EncryptionType};

        // Reconstruct encrypted data structure
        let encrypted_data = EncryptedData {
            iv: encrypted_private_key.iv.clone(),
            data: encrypted_private_key.encrypted_key.clone(),
            mac: Some(encrypted_private_key.mac.clone()),
        };

        EncryptionService::decrypt(
            &encrypted_data,
            user_key.as_bytes(),
            EncryptionType::AesCbc256HmacSha256B64,
        )
    }

    /// Generate organization key (shared key for organization)
    pub fn generate_org_key() -> CryptoResult<Vec<u8>> {
        EncryptionService::generate_key(64) // 512 bits
    }

    /// Encrypt organization key with user's public key
    pub fn encrypt_org_key_for_user(
        org_key: &[u8],
        user_public_key: &[u8],
    ) -> CryptoResult<Vec<u8>> {
        Self::rsa_encrypt(org_key, user_public_key)
    }

    /// Decrypt organization key with user's private key
    pub fn decrypt_org_key_for_user(
        encrypted_org_key: &[u8],
        user_private_key: &[u8],
    ) -> CryptoResult<Vec<u8>> {
        Self::rsa_decrypt(encrypted_org_key, user_private_key)
    }

    /// Derive key from material using HKDF
    pub fn derive_key_from_material(
        material: &[u8],
        salt: &str,
        info: &str,
        length: usize,
    ) -> CryptoResult<Vec<u8>> {
        use aws_lc_rs::hkdf::{Salt, HKDF_SHA256};

        let salt_obj = Salt::new(HKDF_SHA256, salt.as_bytes());
        let prk = salt_obj.extract(material);
        let info_slice = [info.as_bytes()];
        let okm = prk
            .expand(&info_slice, HKDF_SHA256.hmac_algorithm())
            .map_err(|e| CryptoError::KeyGeneration(format!("HKDF expand failed: {}", e)))?;
        let mut output = vec![0u8; length];
        okm.fill(&mut output)
            .map_err(|e| CryptoError::KeyGeneration(format!("HKDF fill failed: {}", e)))?;

        Ok(output)
    }

    /// Create a key with specific purpose (for PIN, biometric, etc.)
    pub fn create_key_with_purpose(
        bit_length: usize,
        purpose: &str,
        salt: Option<&str>,
    ) -> CryptoResult<(String, Vec<u8>, Vec<u8>)> {
        let salt = salt.unwrap_or("default-salt");

        let material = EncryptionService::generate_key(bit_length / 8)?;
        let derived_key = Self::derive_key_from_material(&material, salt, purpose, 64)?;

        Ok((salt.to_string(), material, derived_key))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_user_key_generation() {
        let user_key = KeyService::generate_user_key().unwrap();
        assert_eq!(user_key.as_bytes().len(), 64); // 512 bits
    }

    #[test]
    fn test_rsa_key_pair_generation() {
        let key_pair = KeyService::generate_rsa_key_pair(2048).unwrap();
        assert!(!key_pair.public_key.is_empty());
        assert!(!key_pair.private_key.is_empty());
    }

    #[test]
    fn test_rsa_encryption_decryption() {
        let key_pair = KeyService::generate_rsa_key_pair(2048).unwrap();
        let data = b"Hello, RSA!";

        let encrypted = KeyService::rsa_encrypt(data, &key_pair.public_key).unwrap();
        let decrypted = KeyService::rsa_decrypt(&encrypted, &key_pair.private_key).unwrap();

        assert_eq!(data, decrypted.as_slice());
    }

    #[test]
    fn test_private_key_encryption() {
        let key_pair = KeyService::generate_rsa_key_pair(2048).unwrap();
        let user_key = KeyService::generate_user_key().unwrap();

        let encrypted_private_key =
            KeyService::encrypt_private_key(&key_pair.private_key, &user_key).unwrap();

        let decrypted_private_key =
            KeyService::decrypt_private_key(&encrypted_private_key, &user_key).unwrap();

        assert_eq!(key_pair.private_key, decrypted_private_key);
    }

    #[test]
    fn test_org_key_operations() {
        let org_key = KeyService::generate_org_key().unwrap();
        let key_pair = KeyService::generate_rsa_key_pair(2048).unwrap();

        let encrypted_org_key =
            KeyService::encrypt_org_key_for_user(&org_key, &key_pair.public_key).unwrap();

        let decrypted_org_key =
            KeyService::decrypt_org_key_for_user(&encrypted_org_key, &key_pair.private_key)
                .unwrap();

        assert_eq!(org_key, decrypted_org_key);
    }

    #[test]
    fn test_key_derivation() {
        let material = b"test-material";
        let salt = "test-salt";
        let info = "test-purpose";

        let derived_key = KeyService::derive_key_from_material(material, salt, info, 32).unwrap();
        assert_eq!(derived_key.len(), 32);

        // Same inputs should produce same output
        let derived_key2 = KeyService::derive_key_from_material(material, salt, info, 32).unwrap();
        assert_eq!(derived_key, derived_key2);
    }
}
