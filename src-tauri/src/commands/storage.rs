use crate::crypto::token_manager::StoredKeyType;
use crate::app_state::AppState;
use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::{command, State};

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
        "access_token" => Ok(StoredKeyType::AccessToken),
        "refresh_token" => Ok(StoredKeyType::RefreshToken),
        _ => Err(format!("Invalid key type: {}", key_type)),
    }
}

/// Store a key in secure storage
#[command]
pub async fn store_key(
    request: StoreKeyRequest,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let key_type = parse_key_type(&request.key_type)?;
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    match key_type {
        StoredKeyType::BiometricKey => {
            token_manager
                .store_biometric_key(&request.user_id, &request.key_data)
                .await
                .map_err(|e| e.to_string())
        }
        StoredKeyType::EncryptedUserKey => {
            token_manager
                .store_encrypted_user_key(&request.user_id, &request.key_data)
                .await
                .map_err(|e| e.to_string())
        }
        StoredKeyType::RefreshToken => {
            let token = String::from_utf8(request.key_data)
                .map_err(|e| format!("Invalid UTF-8 in token: {}", e))?;
            token_manager
                .store_refresh_token(&request.user_id, &token)
                .await
                .map_err(|e| e.to_string())
        }
        _ => Err("Unsupported key type for direct storage".to_string()),
    }
}

/// Retrieve a key from secure storage
#[command]
pub async fn retrieve_key(
    request: RetrieveKeyRequest,
    state: State<'_, AppState>,
) -> Result<RetrieveKeyResponse, String> {
    let key_type = parse_key_type(&request.key_type)?;
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    let key_data = match key_type {
        StoredKeyType::BiometricKey => {
            token_manager
                .retrieve_biometric_key(&request.user_id)
                .await
                .map_err(|e| e.to_string())?
        }
        StoredKeyType::EncryptedUserKey => {
            token_manager
                .retrieve_encrypted_user_key(&request.user_id)
                .await
                .map_err(|e| e.to_string())?
        }
        StoredKeyType::RefreshToken => {
            match token_manager
                .retrieve_refresh_token(&request.user_id)
                .await
                .map_err(|e| e.to_string())?
            {
                Some(token) => Some(token.into_bytes()),
                None => None,
            }
        }
        _ => return Err("Unsupported key type for direct retrieval".to_string()),
    };

    Ok(RetrieveKeyResponse { key_data })
}

/// Check if a key exists in secure storage
#[command]
pub async fn has_key(
    request: HasKeyRequest,
    state: State<'_, AppState>,
) -> Result<HasKeyResponse, String> {
    let key_type = parse_key_type(&request.key_type)?;
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    let exists = match key_type {
        StoredKeyType::BiometricKey => {
            token_manager
                .retrieve_biometric_key(&request.user_id)
                .await
                .map_err(|e| e.to_string())?
                .is_some()
        }
        StoredKeyType::EncryptedUserKey => {
            token_manager
                .retrieve_encrypted_user_key(&request.user_id)
                .await
                .map_err(|e| e.to_string())?
                .is_some()
        }
        StoredKeyType::RefreshToken => {
            token_manager
                .retrieve_refresh_token(&request.user_id)
                .await
                .map_err(|e| e.to_string())?
                .is_some()
        }
        _ => return Err("Unsupported key type for existence check".to_string()),
    };

    Ok(HasKeyResponse { exists })
}

/// Delete a key from secure storage
#[command]
pub async fn delete_key(
    request: RetrieveKeyRequest,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let key_type = parse_key_type(&request.key_type)?;
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    match key_type {
        StoredKeyType::BiometricKey => {
            token_manager
                .delete_biometric_key(&request.user_id)
                .await
                .map_err(|e| e.to_string())
        }
        StoredKeyType::RefreshToken => {
            token_manager
                .delete_refresh_token(&request.user_id)
                .await
                .map_err(|e| e.to_string())
        }
        _ => Err("Unsupported key type for deletion".to_string()),
    }
}

/// Store biometric key
#[command]
pub async fn store_biometric_key(
    user_id: String,
    key_data: Vec<u8>,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;
    token_manager
        .store_biometric_key(&user_id, &key_data)
        .await
        .map_err(|e| e.to_string())
}

/// Retrieve biometric key
#[command]
pub async fn retrieve_biometric_key(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<RetrieveKeyResponse, String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;
    let key_data = token_manager
        .retrieve_biometric_key(&user_id)
        .await
        .map_err(|e| e.to_string())?;

    Ok(RetrieveKeyResponse { key_data })
}

/// Delete biometric key
#[command]
pub async fn delete_biometric_key(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;
    token_manager
        .delete_biometric_key(&user_id)
        .await
        .map_err(|e| e.to_string())
}

/// Store encrypted user key
#[command]
pub async fn store_encrypted_user_key(
    user_id: String,
    encrypted_key: Vec<u8>,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;
    token_manager
        .store_encrypted_user_key(&user_id, &encrypted_key)
        .await
        .map_err(|e| e.to_string())
}

/// Retrieve encrypted user key
#[command]
pub async fn retrieve_encrypted_user_key(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<RetrieveKeyResponse, String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;
    let key_data = token_manager
        .retrieve_encrypted_user_key(&user_id)
        .await
        .map_err(|e| e.to_string())?;

    Ok(RetrieveKeyResponse { key_data })
}

/// Store master key hash
#[command]
pub async fn store_master_key_hash(
    user_id: String,
    hash: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;
    token_manager
        .store_master_key_hash(&user_id, &hash)
        .await
        .map_err(|e| e.to_string())
}

/// Retrieve master key hash
#[command]
pub async fn retrieve_master_key_hash(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<Option<String>, String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;
    token_manager
        .retrieve_master_key_hash(&user_id)
        .await
        .map_err(|e| e.to_string())
}

/// Clear all keys for a user
#[command]
pub async fn clear_user_keys(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;
    token_manager
        .clear_all_user_data(&user_id)
        .await
        .map_err(|e| e.to_string())
}

/// Store local data (non-sensitive)
#[command]
pub async fn store_local_data(
    request: StoreLocalDataRequest,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    let mut path = token_manager.get_app_data_dir().map_err(|e| e.to_string())?;
    path.push(&request.filename);

    tokio::fs::write(&path, &request.data).await
        .map_err(|e| format!("Failed to write file: {}", e))
}

/// Retrieve local data
#[command]
pub async fn retrieve_local_data(
    request: RetrieveLocalDataRequest,
    state: State<'_, AppState>,
) -> Result<RetrieveLocalDataResponse, String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    let mut path = token_manager.get_app_data_dir().map_err(|e| e.to_string())?;
    path.push(&request.filename);

    let data = match tokio::fs::read(&path).await {
        Ok(data) => Some(data),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
        Err(e) => return Err(format!("Failed to read file: {}", e)),
    };

    Ok(RetrieveLocalDataResponse { data })
}

/// Delete local data
#[command]
pub async fn delete_local_data(
    filename: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    let mut path = token_manager.get_app_data_dir().map_err(|e| e.to_string())?;
    path.push(&filename);

    match tokio::fs::remove_file(&path).await {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("Failed to delete file: {}", e)),
    }
}

/// Get application data directory path
#[command]
pub async fn get_app_data_dir(state: State<'_, AppState>) -> Result<String, String> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    let path = token_manager.get_app_data_dir().map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().to_string())
}

// Simple key-value storage commands using tauri-plugin-store
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct StoreValueRequest {
    pub store_name: String,
    pub key: String,
    pub value: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct GetValueRequest {
    pub store_name: String,
    pub key: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct GetValueResponse {
    pub value: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct DeleteValueRequest {
    pub store_name: String,
    pub key: String,
}

/// Store a value in tauri-plugin-store
#[command]
#[specta::specta]
pub async fn store_value(
    app_handle: tauri::AppHandle,
    request: StoreValueRequest,
) -> Result<(), String> {
    use tauri_plugin_store::StoreExt;

    let store = app_handle
        .store(&request.store_name)
        .map_err(|e| format!("Failed to initialize store '{}': {}", request.store_name, e))?;

    // Parse the string value as JSON for storage
    let json_value: serde_json::Value = serde_json::from_str(&request.value)
        .map_err(|e| format!("Failed to parse value as JSON: {}", e))?;

    store.set(&request.key, json_value);

    store
        .save()
        .map_err(|e| format!("Failed to save store '{}': {}", request.store_name, e))?;

    Ok(())
}

/// Get a value from tauri-plugin-store
#[command]
#[specta::specta]
pub async fn get_value(
    app_handle: tauri::AppHandle,
    request: GetValueRequest,
) -> Result<GetValueResponse, String> {
    use tauri_plugin_store::StoreExt;

    let store = app_handle
        .store(&request.store_name)
        .map_err(|e| format!("Failed to initialize store '{}': {}", request.store_name, e))?;

    let value = store.get(&request.key);

    // Convert JSON value back to string
    let string_value = match value {
        Some(json_val) => Some(
            serde_json::to_string(&json_val)
                .map_err(|e| format!("Failed to serialize value to JSON: {}", e))?,
        ),
        None => None,
    };

    Ok(GetValueResponse {
        value: string_value,
    })
}

/// Delete a value from tauri-plugin-store
#[command]
#[specta::specta]
pub async fn delete_value(
    app_handle: tauri::AppHandle,
    request: DeleteValueRequest,
) -> Result<(), String> {
    use tauri_plugin_store::StoreExt;

    let store = app_handle
        .store(&request.store_name)
        .map_err(|e| format!("Failed to initialize store '{}': {}", request.store_name, e))?;

    store.delete(&request.key);

    store
        .save()
        .map_err(|e| format!("Failed to save store '{}': {}", request.store_name, e))?;

    Ok(())
}
