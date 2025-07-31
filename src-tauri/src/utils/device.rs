use crate::error::{AppError, AppResult};
use std::fs;
use tauri::Manager;
use tracing::{debug, info};

/// Device type constants for Bitwarden API
pub const DEVICE_TYPE_DESKTOP: &str = "6";

/// Get or create a persistent device identifier
pub async fn get_device_identifier(app_handle: &tauri::AppHandle) -> AppResult<String> {
    let app_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| AppError::StorageError {
            message: format!("Failed to get app data dir: {}", e),
        })?;

    let device_id_path = app_dir.join("device_id");

    // Try to load existing device ID
    if let Ok(device_id) = fs::read_to_string(&device_id_path) {
        let device_id = device_id.trim().to_string();
        if !device_id.is_empty() {
            debug!("Loaded existing device ID: {}", device_id);
            return Ok(device_id);
        }
    }

    // Generate new device ID
    let device_id = uuid::Uuid::new_v4().to_string();

    // Ensure the app data directory exists
    if let Err(e) = fs::create_dir_all(&app_dir) {
        return Err(AppError::StorageError {
            message: format!("Failed to create app data directory: {}", e),
        });
    }

    // Save device ID
    fs::write(&device_id_path, &device_id).map_err(|e| AppError::StorageError {
        message: format!("Failed to save device ID: {}", e),
    })?;

    info!("Generated new device ID: {}", device_id);
    Ok(device_id)
}

/// Get device name for Bitwarden API
pub fn get_device_name() -> AppResult<String> {
    let hostname = hostname::get()
        .map_err(|e| AppError::StorageError {
            message: format!("Failed to get hostname: {}", e),
        })?
        .to_string_lossy()
        .to_string();
    
    Ok(format!("Chiikawarden Desktop - {}", hostname))
}

/// Get device type for Bitwarden API (always desktop for this app)
pub fn get_device_type() -> &'static str {
    DEVICE_TYPE_DESKTOP
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_get_device_name() {
        let device_name = get_device_name().unwrap();
        assert!(device_name.starts_with("Chiikawarden Desktop - "));
        assert!(device_name.len() > "Chiikawarden Desktop - ".len());
    }

    #[test]
    fn test_get_device_type() {
        assert_eq!(get_device_type(), "6");
    }
}
