use serde::{Deserialize, Serialize};
use specta::Type;

/// Settings model for application configuration
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct Settings {
    // UI Settings
    pub theme: String,
    pub language: String,

    // Security Settings
    pub vault_timeout: i32,
    pub vault_timeout_action: String,
    pub biometric_unlock: bool,
    pub clear_clipboard: i32,

    // Application Settings
    pub minimize_to_tray: bool,
    pub start_to_tray: bool,
    pub auto_start: bool,

    // Server URL for self-hosted instances (moved from environment)
    pub server_url: Option<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            // UI defaults
            theme: "system".to_string(),
            language: "en".to_string(),

            // Security defaults
            vault_timeout: 15,
            vault_timeout_action: "lock".to_string(),
            biometric_unlock: false,
            clear_clipboard: 20,

            // Application defaults
            minimize_to_tray: true,
            start_to_tray: false,
            auto_start: false,

            // Server URL defaults
            server_url: None,
        }
    }
}

impl Settings {
    /// Create settings for self-hosted server
    pub fn with_self_hosted_server(server_url: String) -> Self {
        let mut settings = Self::default();
        settings.server_url = Some(server_url);
        settings
    }

    /// Check if using self-hosted server
    pub fn is_self_hosted(&self) -> bool {
        self.server_url.is_some()
    }

    /// Get the server URL
    pub fn get_server_url(&self) -> Option<String> {
        self.server_url.clone()
    }
}
