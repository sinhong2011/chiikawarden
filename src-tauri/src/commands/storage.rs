use crate::crypto::secure_storage::{SecureStorageService, StoredKeyType};
use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::command;

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct StoreKeyRequest {
    pub user_id: String,
    pub key_type: String,
    pub key_data: Vec<u8>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct RetrieveKeyRequest {
    pub user_id: String,
    pub key_type: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct RetrieveKeyResponse {
    pub key_data: Option<Vec<u8>>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct HasKeyRequest {
    pub user_id: String,
    pub key_type: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct HasKeyResponse {
    pub exists: bool,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct StoreLocalDataRequest {
    pub filename: String,
    pub data: Vec<u8>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct RetrieveLocalDataRequest {
    pub filename: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct RetrieveLocalDataResponse {
    pub data: Option<Vec<u8>>,
}

fn parse_key_type(key_type: &str) -> Result<StoredKeyType, String> {
    match key_type {
        "biometric" => Ok(StoredKeyType::BiometricKey),
        "user" => Ok(StoredKeyType::UserKey),
        "master_hash" => Ok(StoredKeyType::MasterKeyHash),
        "encrypted_user" => Ok(StoredKeyType::EncryptedUserKey),
        _ => Err(format!("Invalid key type: {}", key_type)),
    }
}

/// Store a key in secure storage
#[command]
pub async fn store_key(request: StoreKeyRequest) -> Result<(), String> {
    let key_type = parse_key_type(&request.key_type)?;

    SecureStorageService::store_key(&request.user_id, key_type, &request.key_data)
        .map_err(|e| e.to_string())
}

/// Retrieve a key from secure storage
#[command]
pub async fn retrieve_key(request: RetrieveKeyRequest) -> Result<RetrieveKeyResponse, String> {
    let key_type = parse_key_type(&request.key_type)?;

    let key_data = SecureStorageService::retrieve_key(&request.user_id, key_type)
        .map_err(|e| e.to_string())?;

    Ok(RetrieveKeyResponse { key_data })
}

/// Check if a key exists in secure storage
#[command]
pub async fn has_key(request: HasKeyRequest) -> Result<HasKeyResponse, String> {
    let key_type = parse_key_type(&request.key_type)?;

    let exists =
        SecureStorageService::has_key(&request.user_id, key_type).map_err(|e| e.to_string())?;

    Ok(HasKeyResponse { exists })
}

/// Delete a key from secure storage
#[command]
pub async fn delete_key(request: RetrieveKeyRequest) -> Result<(), String> {
    let key_type = parse_key_type(&request.key_type)?;

    SecureStorageService::delete_key(&request.user_id, key_type).map_err(|e| e.to_string())
}

/// Store biometric key
#[command]
pub async fn store_biometric_key(user_id: String, key_data: Vec<u8>) -> Result<(), String> {
    SecureStorageService::store_biometric_key(&user_id, &key_data).map_err(|e| e.to_string())
}

/// Retrieve biometric key
#[command]
pub async fn retrieve_biometric_key(user_id: String) -> Result<RetrieveKeyResponse, String> {
    let key_data =
        SecureStorageService::retrieve_biometric_key(&user_id).map_err(|e| e.to_string())?;

    Ok(RetrieveKeyResponse { key_data })
}

/// Delete biometric key
#[command]
pub async fn delete_biometric_key(user_id: String) -> Result<(), String> {
    SecureStorageService::delete_biometric_key(&user_id).map_err(|e| e.to_string())
}

/// Store encrypted user key
#[command]
pub async fn store_encrypted_user_key(
    user_id: String,
    encrypted_key: Vec<u8>,
) -> Result<(), String> {
    SecureStorageService::store_encrypted_user_key(&user_id, &encrypted_key)
        .map_err(|e| e.to_string())
}

/// Retrieve encrypted user key
#[command]
pub async fn retrieve_encrypted_user_key(user_id: String) -> Result<RetrieveKeyResponse, String> {
    let key_data =
        SecureStorageService::retrieve_encrypted_user_key(&user_id).map_err(|e| e.to_string())?;

    Ok(RetrieveKeyResponse { key_data })
}

/// Store master key hash
#[command]
pub async fn store_master_key_hash(user_id: String, hash: String) -> Result<(), String> {
    SecureStorageService::store_master_key_hash(&user_id, &hash).map_err(|e| e.to_string())
}

/// Retrieve master key hash
#[command]
pub async fn retrieve_master_key_hash(user_id: String) -> Result<Option<String>, String> {
    SecureStorageService::retrieve_master_key_hash(&user_id).map_err(|e| e.to_string())
}

/// Clear all keys for a user
#[command]
pub async fn clear_user_keys(user_id: String) -> Result<(), String> {
    SecureStorageService::clear_user_keys(&user_id).map_err(|e| e.to_string())
}

/// Store local data (non-sensitive)
#[command]
pub async fn store_local_data(request: StoreLocalDataRequest) -> Result<(), String> {
    SecureStorageService::store_local_data(&request.filename, &request.data)
        .map_err(|e| e.to_string())
}

/// Retrieve local data
#[command]
pub async fn retrieve_local_data(
    request: RetrieveLocalDataRequest,
) -> Result<RetrieveLocalDataResponse, String> {
    let data =
        SecureStorageService::retrieve_local_data(&request.filename).map_err(|e| e.to_string())?;

    Ok(RetrieveLocalDataResponse { data })
}

/// Delete local data
#[command]
pub async fn delete_local_data(filename: String) -> Result<(), String> {
    SecureStorageService::delete_local_data(&filename).map_err(|e| e.to_string())
}

/// Get application data directory path
#[command]
pub async fn get_app_data_dir() -> Result<String, String> {
    let path = SecureStorageService::get_app_data_dir().map_err(|e| e.to_string())?;

    Ok(path.to_string_lossy().to_string())
}
