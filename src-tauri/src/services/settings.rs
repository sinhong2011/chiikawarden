use crate::error::{AppError, AppResult};
use crate::models::Settings;
use std::sync::Arc;
use tauri::AppHandle;
use tauri_plugin_store::{Store, StoreExt};
use tokio::sync::Mutex;

const SETTINGS_STORE_FILE: &str = "settings.json";
const SETTINGS_KEY: &str = "app_settings";

/// Settings service for managing application settings using tauri-plugin-store
pub struct SettingsStoreService {
    app_handle: AppHandle,
    store: Mutex<Arc<Store<tauri::Wry>>>,
}

impl SettingsStoreService {
    /// Create a new settings store service
    pub async fn new(app_handle: AppHandle) -> AppResult<Self> {
        // Initialize the store
        let store = app_handle
            .store_builder(SETTINGS_STORE_FILE)
            .build()
            .map_err(|e| AppError::StorageError {
                message: format!("Failed to initialize settings store: {}", e),
            })?;

        let store = Mutex::new(store);

        Ok(Self { app_handle, store })
    }

    /// Get current settings
    pub async fn get_settings(&self) -> AppResult<Settings> {
        let store = self.store.lock().await;

        match store.get(SETTINGS_KEY) {
            Some(value) => {
                // Try to deserialize the stored settings
                match serde_json::from_value::<Settings>(value.clone()) {
                    Ok(settings) => Ok(settings),
                    Err(e) => {
                        // If deserialization fails, try to migrate from partial settings
                        tracing::warn!(
                            error = %e,
                            "Failed to deserialize settings, attempting migration"
                        );

                        drop(store); // Release the lock before calling migrate_partial_settings
                        self.migrate_partial_settings(value.clone()).await
                    }
                }
            }
            None => {
                // No settings found, return and save defaults
                drop(store); // Release the lock before calling save_settings
                let default_settings = Settings::default();
                self.save_settings(&default_settings).await?;
                Ok(default_settings)
            }
        }
    }

    /// Save settings
    pub async fn save_settings(&self, settings: &Settings) -> AppResult<()> {
        let store = self.store.lock().await;

        // Serialize settings to JSON value
        let settings_value =
            serde_json::to_value(settings).map_err(|e| AppError::StorageError {
                message: format!("Failed to serialize settings: {}", e),
            })?;

        // Store the settings (set() doesn't return a Result)
        store.set(SETTINGS_KEY, settings_value);

        // Save to disk (save() is not async)
        store.save().map_err(|e| AppError::StorageError {
            message: format!("Failed to save settings to disk: {}", e),
        })?;

        Ok(())
    }

    /// Reset settings to defaults
    pub async fn reset_settings(&self) -> AppResult<Settings> {
        let default_settings = Settings::default();
        self.save_settings(&default_settings).await?;
        Ok(default_settings)
    }

    /// Clear all settings (for testing or reset purposes)
    pub async fn clear_settings(&self) -> AppResult<()> {
        let store = self.store.lock().await;

        // Delete the settings (delete() doesn't return a Result)
        store.delete(SETTINGS_KEY);

        // Save to disk (save() is not async)
        store.save().map_err(|e| AppError::StorageError {
            message: format!("Failed to save after clearing settings: {}", e),
        })?;

        Ok(())
    }

    /// Migrate settings from partial/incomplete stored settings
    pub async fn migrate_partial_settings(
        &self,
        stored_value: serde_json::Value,
    ) -> AppResult<Settings> {
        tracing::info!("Migrating partial settings to current format");

        // Start with default settings
        let mut settings = Settings::default();

        // Extract existing values from stored settings
        if let Some(theme) = stored_value.get("theme").and_then(|v| v.as_str()) {
            settings.theme = theme.to_string();
        }

        if let Some(language) = stored_value.get("language").and_then(|v| v.as_str()) {
            settings.language = language.to_string();
        }

        if let Some(vault_timeout) = stored_value.get("vault_timeout").and_then(|v| v.as_i64()) {
            settings.vault_timeout =
                crate::models::settings::VaultTimeout::from_legacy_minutes(vault_timeout as i32);
        }

        if let Some(vault_timeout_action) = stored_value
            .get("vault_timeout_action")
            .and_then(|v| v.as_str())
        {
            settings.vault_timeout_action = vault_timeout_action.to_string();
        }

        if let Some(biometric_unlock) = stored_value
            .get("biometric_unlock")
            .and_then(|v| v.as_bool())
        {
            settings.biometric_unlock = biometric_unlock;
        }

        if let Some(clear_clipboard) = stored_value.get("clear_clipboard").and_then(|v| v.as_i64())
        {
            settings.clear_clipboard = clear_clipboard as i32;
        }

        if let Some(minimize_to_tray) = stored_value
            .get("minimize_to_tray")
            .and_then(|v| v.as_bool())
        {
            settings.minimize_to_tray = minimize_to_tray;
        }

        if let Some(start_to_tray) = stored_value.get("start_to_tray").and_then(|v| v.as_bool()) {
            settings.start_to_tray = start_to_tray;
        }

        if let Some(auto_start) = stored_value.get("auto_start").and_then(|v| v.as_bool()) {
            settings.auto_start = auto_start;
        }

        if let Some(server_url) = stored_value.get("server_url") {
            settings.server_url = server_url.as_str().map(|s| s.to_string());
        }

        // debug_token_operations will use the default value (false) if not present
        if let Some(debug_token_operations) = stored_value
            .get("debug_token_operations")
            .and_then(|v| v.as_bool())
        {
            settings.debug_token_operations = debug_token_operations;
        }

        // Save the migrated settings
        self.save_settings(&settings).await?;

        tracing::info!("Successfully migrated partial settings");
        Ok(settings)
    }

    /// Migrate settings from legacy format (for one-time migration)
    pub async fn migrate_from_legacy(
        &self,
        legacy_settings: serde_json::Value,
    ) -> AppResult<Settings> {
        // Get current settings or defaults
        let mut current_settings = match self.get_settings().await {
            Ok(settings) => settings,
            Err(_) => Settings::default(),
        };

        // Extract legacy values and map to current format
        if let Some(theme) = legacy_settings.get("theme").and_then(|v| v.as_str()) {
            current_settings.theme = theme.to_string();
        }

        if let Some(language) = legacy_settings.get("language").and_then(|v| v.as_str()) {
            current_settings.language = language.to_string();
        }

        if let Some(auto_lock_timeout) = legacy_settings
            .get("autoLockTimeout")
            .and_then(|v| v.as_i64())
        {
            current_settings.vault_timeout =
                crate::models::settings::VaultTimeout::from_legacy_minutes(
                    auto_lock_timeout as i32,
                );
        }

        if let Some(auto_lock) = legacy_settings.get("autoLock").and_then(|v| v.as_bool()) {
            current_settings.vault_timeout_action =
                if auto_lock { "lock" } else { "logout" }.to_string();
        }

        if let Some(minimize_to_tray) = legacy_settings
            .get("minimizeToTray")
            .and_then(|v| v.as_bool())
        {
            current_settings.minimize_to_tray = minimize_to_tray;
        }

        if let Some(start_minimized) = legacy_settings
            .get("startMinimized")
            .and_then(|v| v.as_bool())
        {
            current_settings.start_to_tray = start_minimized;
        }

        if let Some(clear_clipboard) = legacy_settings
            .get("clearClipboard")
            .and_then(|v| v.as_bool())
        {
            if clear_clipboard {
                if let Some(timeout) = legacy_settings
                    .get("clearClipboardTimeout")
                    .and_then(|v| v.as_i64())
                {
                    current_settings.clear_clipboard = timeout as i32;
                }
            } else {
                current_settings.clear_clipboard = 0; // Disabled
            }
        }

        // Save the migrated settings
        self.save_settings(&current_settings).await?;

        Ok(current_settings)
    }
}
