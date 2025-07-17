use crate::crypto::biometrics::{BiometricService, BiometricStatus};
use crate::crypto::UserKey;
use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::command;

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct BiometricStatusResponse {
    pub status: String,
    pub available: bool,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct BiometricAuthRequest {
    pub prompt: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct BiometricAuthResponse {
    pub success: bool,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SetupBiometricRequest {
    pub user_id: String,
    pub user_key: Vec<u8>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct RetrieveBiometricKeyRequest {
    pub user_id: String,
    pub prompt: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct RetrieveBiometricKeyResponse {
    pub success: bool,
    pub user_key: Option<Vec<u8>>,
}

/// Check biometric availability
#[command]
#[specta::specta]
pub async fn check_biometric_availability() -> Result<BiometricStatusResponse, String> {
    let status = BiometricService::is_available().map_err(|e| e.to_string())?;

    let (status_str, available) = match status {
        BiometricStatus::Available => ("available", true),
        BiometricStatus::NotAvailable => ("not_available", false),
        BiometricStatus::NotEnrolled => ("not_enrolled", false),
        BiometricStatus::UnlockNeeded => ("unlock_needed", true),
    };

    Ok(BiometricStatusResponse {
        status: status_str.to_string(),
        available,
    })
}

/// Authenticate with biometric
#[command]
#[specta::specta]
pub async fn authenticate_biometric(
    request: BiometricAuthRequest,
) -> Result<BiometricAuthResponse, String> {
    let success = BiometricService::authenticate(&request.prompt)
        .await
        .map_err(|e| e.to_string())?;

    Ok(BiometricAuthResponse { success })
}

/// Setup biometric unlock (alternative implementation)
#[command]
#[specta::specta]
pub async fn setup_biometric_unlock_alt(request: SetupBiometricRequest) -> Result<bool, String> {
    let user_key = UserKey::new(request.user_key);

    BiometricService::store_biometric_user_key(&request.user_id, &user_key)
        .await
        .map_err(|e| e.to_string())?;

    Ok(true)
}

/// Retrieve user key with biometric authentication
#[command]
#[specta::specta]
pub async fn retrieve_biometric_user_key(
    request: RetrieveBiometricKeyRequest,
) -> Result<RetrieveBiometricKeyResponse, String> {
    let user_key = BiometricService::retrieve_biometric_user_key(&request.user_id, &request.prompt)
        .await
        .map_err(|e| e.to_string())?;

    match user_key {
        Some(key) => Ok(RetrieveBiometricKeyResponse {
            success: true,
            user_key: Some(key.as_bytes().to_vec()),
        }),
        None => Ok(RetrieveBiometricKeyResponse {
            success: false,
            user_key: None,
        }),
    }
}

/// Delete biometric unlock
#[command]
#[specta::specta]
pub async fn delete_biometric_unlock(user_id: String) -> Result<bool, String> {
    BiometricService::delete_biometric_user_key(&user_id)
        .await
        .map_err(|e| e.to_string())?;

    Ok(true)
}

/// Check if biometric unlock is enabled
#[command]
#[specta::specta]
pub async fn is_biometric_unlock_enabled(user_id: String) -> Result<bool, String> {
    BiometricService::is_biometric_unlock_enabled(&user_id).map_err(|e| e.to_string())
}
