use crate::app_state::AppState;
use crate::models::Settings;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use specta::Type;
use tauri::{command, State};

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SaveSettingsRequest {
    pub settings: Settings,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct MigrateLegacySettingsRequest {
    pub legacy_settings: String, // JSON string that will be parsed
}

/// Get current settings
#[command]
#[specta::specta]
pub async fn get_settings(state: State<'_, AppState>) -> Result<Settings, String> {
    // Check if app state is initialized
    if !state.is_initialized().await {
        return Err("Application not initialized".to_string());
    }

    // Get the settings service and retrieve settings
    match state.settings_store_service.get_settings().await {
        Ok(settings) => Ok(settings),
        Err(e) => {
            eprintln!("Failed to get settings: {}", e);
            Err(format!("Failed to get settings: {}", e))
        }
    }
}

/// Save settings
#[command]
#[specta::specta]
pub async fn save_settings(
    request: SaveSettingsRequest,
    state: State<'_, AppState>,
) -> Result<(), String> {
    // Check if app state is initialized
    if !state.is_initialized().await {
        return Err("Application not initialized".to_string());
    }

    // Save the settings using the store service
    match state
        .settings_store_service
        .save_settings(&request.settings)
        .await
    {
        Ok(()) => {
            println!("Settings saved successfully");
            Ok(())
        }
        Err(e) => {
            eprintln!("Failed to save settings: {}", e);
            Err(format!("Failed to save settings: {}", e))
        }
    }
}

/// Reset settings to defaults
#[command]
#[specta::specta]
pub async fn reset_settings(state: State<'_, AppState>) -> Result<Settings, String> {
    // Check if app state is initialized
    if !state.is_initialized().await {
        return Err("Application not initialized".to_string());
    }

    // Reset settings to defaults using the store service
    match state.settings_store_service.reset_settings().await {
        Ok(settings) => {
            println!("Settings reset to defaults");
            Ok(settings)
        }
        Err(e) => {
            eprintln!("Failed to reset settings: {}", e);
            Err(format!("Failed to reset settings: {}", e))
        }
    }
}

/// Migrate legacy settings to current format
#[command]
#[specta::specta]
pub async fn migrate_legacy_settings(
    request: MigrateLegacySettingsRequest,
    state: State<'_, AppState>,
) -> Result<Settings, String> {
    // Check if app state is initialized
    if !state.is_initialized().await {
        return Err("Application not initialized".to_string());
    }

    // Parse the JSON string
    let legacy_settings: Value = match serde_json::from_str(&request.legacy_settings) {
        Ok(value) => value,
        Err(e) => return Err(format!("Failed to parse legacy settings JSON: {}", e)),
    };

    // Migrate the legacy settings using the store service
    match state
        .settings_store_service
        .migrate_from_legacy(legacy_settings)
        .await
    {
        Ok(settings) => {
            println!("Legacy settings migrated successfully");
            Ok(settings)
        }
        Err(e) => {
            eprintln!("Failed to migrate legacy settings: {}", e);
            Err(format!("Failed to migrate legacy settings: {}", e))
        }
    }
}
