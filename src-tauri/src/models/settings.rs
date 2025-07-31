use serde::{Deserialize, Serialize};
use specta::Type;

/// Vault timeout configuration
#[derive(Debug, Clone, Serialize, Deserialize, Type, PartialEq, Eq)]
pub enum VaultTimeout {
    /// Timeout after specified minutes
    Minutes(i32),
    /// Never timeout (auto-unlock enabled)
    Never,
}

impl Default for VaultTimeout {
    fn default() -> Self {
        VaultTimeout::Minutes(15)
    }
}

impl VaultTimeout {
    /// Check if this timeout setting enables auto-unlock
    pub fn is_never(&self) -> bool {
        matches!(self, VaultTimeout::Never)
    }

    /// Get timeout in minutes, returns None for Never
    pub fn minutes(&self) -> Option<i32> {
        match self {
            VaultTimeout::Minutes(m) => Some(*m),
            VaultTimeout::Never => None,
        }
    }

    /// Convert from legacy i32 format (for migration)
    pub fn from_legacy_minutes(minutes: i32) -> Self {
        if minutes < 0 {
            VaultTimeout::Never
        } else {
            VaultTimeout::Minutes(minutes)
        }
    }

    /// Convert to legacy i32 format (for backward compatibility)
    pub fn to_legacy_minutes(&self) -> i32 {
        match self {
            VaultTimeout::Minutes(m) => *m,
            VaultTimeout::Never => -1,
        }
    }
}

/// Settings model for application configuration
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct Settings {
    // UI Settings
    pub theme: String,
    pub language: String,

    // Security Settings
    pub vault_timeout: VaultTimeout,
    pub vault_timeout_action: String,
    pub biometric_unlock: bool,
    pub clear_clipboard: i32,

    // Application Settings
    pub minimize_to_tray: bool,
    pub start_to_tray: bool,
    pub auto_start: bool,

    // Server URL for self-hosted instances (moved from environment)
    pub server_url: Option<String>,

    // Debug Settings
    pub debug_token_operations: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            // UI defaults
            theme: "system".to_string(),
            language: "en".to_string(),

            // Security defaults
            vault_timeout: VaultTimeout::default(),
            vault_timeout_action: "lock".to_string(),
            biometric_unlock: false,
            clear_clipboard: 20,

            // Application defaults
            minimize_to_tray: true,
            start_to_tray: false,
            auto_start: false,

            // Server URL defaults
            server_url: None,

            // Debug defaults
            debug_token_operations: false,
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
