use crate::crypto::{
    encryption::EncryptionService,
    kdf::{HashPurpose, KdfService},
    keys::KeyService,
    EncryptedData, EncryptionType, KdfConfig, MasterKey,
};
use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::command;

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct DeriveKeyRequest {
    pub password: String,
    pub email: String,
    pub kdf_config: KdfConfig,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct DeriveKeyResponse {
    pub master_key: Vec<u8>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct HashKeyRequest {
    pub password: String,
    pub master_key: Vec<u8>,
    pub purpose: String, // "local" or "server"
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct HashKeyResponse {
    pub hash: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct EncryptRequest {
    pub data: Vec<u8>,
    pub key: Vec<u8>,
    pub encryption_type: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct EncryptResponse {
    pub encrypted_data: EncryptedData,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct DecryptRequest {
    pub encrypted_data: EncryptedData,
    pub key: Vec<u8>,
    pub encryption_type: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct DecryptResponse {
    pub data: Vec<u8>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct GenerateKeyResponse {
    pub key: Vec<u8>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct RsaKeyPairResponse {
    pub public_key: Vec<u8>,
    pub private_key: Vec<u8>,
}

/// Derive master key from password and email
#[command]
pub async fn derive_master_key(request: DeriveKeyRequest) -> Result<DeriveKeyResponse, String> {
    let master_key =
        KdfService::derive_master_key(&request.password, &request.email, &request.kdf_config)
            .map_err(|e| e.to_string())?;

    Ok(DeriveKeyResponse {
        master_key: master_key.as_bytes().to_vec(),
    })
}

/// Hash master key for verification
#[command]
pub async fn hash_master_key(request: HashKeyRequest) -> Result<HashKeyResponse, String> {
    let master_key = MasterKey::new(request.master_key);
    let purpose = match request.purpose.as_str() {
        "local" => HashPurpose::LocalAuthorization,
        "server" => HashPurpose::ServerAuthorization,
        _ => return Err("Invalid hash purpose".to_string()),
    };

    let hash = KdfService::hash_master_key(&request.password, &master_key, purpose)
        .map_err(|e| e.to_string())?;

    Ok(HashKeyResponse { hash })
}

/// Encrypt data
#[command]
pub async fn encrypt_data(request: EncryptRequest) -> Result<EncryptResponse, String> {
    let encryption_type = match request.encryption_type.as_str() {
        "AesCbc256B64" => EncryptionType::AesCbc256B64,
        "AesCbc256HmacSha256B64" => EncryptionType::AesCbc256HmacSha256B64,
        _ => return Err("Invalid encryption type".to_string()),
    };

    let encrypted_data = EncryptionService::encrypt(&request.data, &request.key, encryption_type)
        .map_err(|e| e.to_string())?;

    Ok(EncryptResponse { encrypted_data })
}

/// Decrypt data
#[command]
pub async fn decrypt_data(request: DecryptRequest) -> Result<DecryptResponse, String> {
    let encryption_type = match request.encryption_type.as_str() {
        "AesCbc256B64" => EncryptionType::AesCbc256B64,
        "AesCbc256HmacSha256B64" => EncryptionType::AesCbc256HmacSha256B64,
        _ => return Err("Invalid encryption type".to_string()),
    };

    let data = EncryptionService::decrypt(&request.encrypted_data, &request.key, encryption_type)
        .map_err(|e| e.to_string())?;

    Ok(DecryptResponse { data })
}

/// Generate user key
#[command]
pub async fn generate_user_key() -> Result<GenerateKeyResponse, String> {
    let user_key = KeyService::generate_user_key().map_err(|e| e.to_string())?;

    Ok(GenerateKeyResponse {
        key: user_key.as_bytes().to_vec(),
    })
}

/// Generate RSA key pair
#[command]
pub async fn generate_rsa_key_pair(bits: usize) -> Result<RsaKeyPairResponse, String> {
    let key_pair = KeyService::generate_rsa_key_pair(bits).map_err(|e| e.to_string())?;

    Ok(RsaKeyPairResponse {
        public_key: key_pair.public_key.clone(),
        private_key: key_pair.private_key.clone(),
    })
}

/// Generate random bytes
#[command]
pub async fn generate_random_bytes(length: usize) -> Result<GenerateKeyResponse, String> {
    let bytes = EncryptionService::random_bytes(length).map_err(|e| e.to_string())?;

    Ok(GenerateKeyResponse { key: bytes })
}

/// Decrypt user key with master key
#[command]
pub async fn decrypt_user_key(
    encrypted_user_key: EncryptedData,
    master_key: Vec<u8>,
    encryption_type: String,
) -> Result<GenerateKeyResponse, String> {
    let master_key = MasterKey::new(master_key);
    let enc_type = match encryption_type.as_str() {
        "AesCbc256B64" => EncryptionType::AesCbc256B64,
        "AesCbc256HmacSha256B64" => EncryptionType::AesCbc256HmacSha256B64,
        _ => return Err("Invalid encryption type".to_string()),
    };

    let user_key = EncryptionService::decrypt_user_key(&encrypted_user_key, &master_key, enc_type)
        .map_err(|e| e.to_string())?;

    Ok(GenerateKeyResponse {
        key: user_key.as_bytes().to_vec(),
    })
}

/// Validate KDF configuration
#[command]
pub async fn validate_kdf_config(kdf_config: KdfConfig) -> Result<bool, String> {
    match KdfService::validate_kdf_config(&kdf_config) {
        Ok(()) => Ok(true),
        Err(e) => Err(e.to_string()),
    }
}

/// RSA encrypt data
#[command]
pub async fn rsa_encrypt(
    data: Vec<u8>,
    public_key: Vec<u8>,
) -> Result<GenerateKeyResponse, String> {
    let encrypted = KeyService::rsa_encrypt(&data, &public_key).map_err(|e| e.to_string())?;

    Ok(GenerateKeyResponse { key: encrypted })
}

/// RSA decrypt data
#[command]
pub async fn rsa_decrypt(
    encrypted_data: Vec<u8>,
    private_key: Vec<u8>,
) -> Result<GenerateKeyResponse, String> {
    let decrypted =
        KeyService::rsa_decrypt(&encrypted_data, &private_key).map_err(|e| e.to_string())?;

    Ok(GenerateKeyResponse { key: decrypted })
}

/// Encrypt data with AES-GCM
#[command]
pub async fn encrypt_aes_gcm(plaintext: String, _key: String) -> Result<String, String> {
    // This is a placeholder implementation
    // In a real implementation, you would use the AES-GCM encryption
    println!("Encrypting with AES-GCM: {}", plaintext);
    Ok(format!("aes_gcm_encrypted_{}", plaintext))
}

/// Decrypt data with AES-GCM
#[command]
pub async fn decrypt_aes_gcm(ciphertext: String, _key: String) -> Result<String, String> {
    // This is a placeholder implementation
    // In a real implementation, you would use the AES-GCM decryption
    println!("Decrypting with AES-GCM: {}", ciphertext);
    Ok(ciphertext.replace("aes_gcm_encrypted_", ""))
}

/// Derive key using Argon2
#[command]
pub async fn derive_argon2_key(
    _password: String,
    _salt: String,
    iterations: u32,
) -> Result<String, String> {
    // This is a placeholder implementation
    // In a real implementation, you would use Argon2 key derivation
    println!("Deriving Argon2 key with {} iterations", iterations);
    Ok("argon2_derived_key".to_string())
}
