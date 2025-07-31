use std::sync::OnceLock;
use tracing::{debug, info};

/// Debug configuration for token operations
/// This module provides centralized debug configuration that can be controlled
/// via environment variables or application settings
#[derive(Debug, Clone)]
pub struct DebugConfig {
    /// Enable verbose logging for token operations
    pub token_operations: bool,
    /// Enable correlation ID tracking
    pub correlation_tracking: bool,
    /// Enable storage backend operation logging
    pub storage_operations: bool,
    /// Enable token validation logging
    pub token_validation: bool,
}

impl Default for DebugConfig {
    fn default() -> Self {
        Self {
            token_operations: false,
            correlation_tracking: false,
            storage_operations: false,
            token_validation: false,
        }
    }
}

impl DebugConfig {
    /// Create debug configuration from environment variables
    pub fn from_env() -> Self {
        let token_operations = get_env_bool("CHIIKAWARDEN_DEBUG_TOKEN_OPS", false);
        let correlation_tracking = get_env_bool("CHIIKAWARDEN_DEBUG_CORRELATION", false);
        let storage_operations = get_env_bool("CHIIKAWARDEN_DEBUG_STORAGE", false);
        let token_validation = get_env_bool("CHIIKAWARDEN_DEBUG_TOKEN_VALIDATION", false);

        // If the general debug flag is set, enable all token debugging
        let general_debug = get_env_bool("CHIIKAWARDEN_TOKEN_DEBUG", false);
        
        Self {
            token_operations: token_operations || general_debug,
            correlation_tracking: correlation_tracking || general_debug,
            storage_operations: storage_operations || general_debug,
            token_validation: token_validation || general_debug,
        }
    }

    /// Create debug configuration from application settings
    pub fn from_settings(settings: &crate::models::Settings) -> Self {
        Self {
            token_operations: settings.debug_token_operations,
            correlation_tracking: settings.debug_token_operations,
            storage_operations: settings.debug_token_operations,
            token_validation: settings.debug_token_operations,
        }
    }

    /// Merge environment and settings configuration (environment takes precedence)
    pub fn merged(settings: &crate::models::Settings) -> Self {
        let env_config = Self::from_env();
        let settings_config = Self::from_settings(settings);

        Self {
            token_operations: env_config.token_operations || settings_config.token_operations,
            correlation_tracking: env_config.correlation_tracking || settings_config.correlation_tracking,
            storage_operations: env_config.storage_operations || settings_config.storage_operations,
            token_validation: env_config.token_validation || settings_config.token_validation,
        }
    }

    /// Check if any debug features are enabled
    pub fn is_debug_enabled(&self) -> bool {
        self.token_operations || self.correlation_tracking || self.storage_operations || self.token_validation
    }

    /// Log the current debug configuration
    pub fn log_config(&self) {
        if self.is_debug_enabled() {
            info!(
                token_operations = self.token_operations,
                correlation_tracking = self.correlation_tracking,
                storage_operations = self.storage_operations,
                token_validation = self.token_validation,
                "[debug_config] Token debug configuration enabled"
            );
        } else {
            debug!("[debug_config] Token debug configuration disabled");
        }
    }
}

/// Global debug configuration instance
static DEBUG_CONFIG: OnceLock<DebugConfig> = OnceLock::new();

/// Initialize the global debug configuration
pub fn init_debug_config(settings: Option<&crate::models::Settings>) {
    let config = match settings {
        Some(settings) => DebugConfig::merged(settings),
        None => DebugConfig::from_env(),
    };

    config.log_config();
    
    if DEBUG_CONFIG.set(config).is_err() {
        debug!("[debug_config] Debug configuration already initialized");
    }
}

/// Get the global debug configuration
pub fn get_debug_config() -> &'static DebugConfig {
    DEBUG_CONFIG.get_or_init(|| {
        debug!("[debug_config] Using default debug configuration");
        DebugConfig::from_env()
    })
}

/// Update the global debug configuration with new settings
pub fn update_debug_config(settings: &crate::models::Settings) {
    let new_config = DebugConfig::merged(settings);
    new_config.log_config();
    
    // Since OnceLock doesn't allow updates, we'll need to use a different approach
    // For now, log that the configuration would be updated
    debug!(
        "[debug_config] Debug configuration update requested (requires restart to take effect)"
    );
}

/// Helper function to parse boolean environment variables
fn get_env_bool(key: &str, default: bool) -> bool {
    std::env::var(key)
        .map(|v| {
            let v = v.to_lowercase();
            matches!(v.as_str(), "true" | "1" | "yes" | "on")
        })
        .unwrap_or(default)
}

/// Utility macros for conditional debug logging
#[macro_export]
macro_rules! debug_token_op {
    ($($arg:tt)*) => {
        if $crate::debug_config::get_debug_config().token_operations {
            tracing::debug!($($arg)*);
        }
    };
}

#[macro_export]
macro_rules! trace_token_op {
    ($($arg:tt)*) => {
        if $crate::debug_config::get_debug_config().token_operations {
            tracing::trace!($($arg)*);
        }
    };
}

#[macro_export]
macro_rules! debug_storage_op {
    ($($arg:tt)*) => {
        if $crate::debug_config::get_debug_config().storage_operations {
            tracing::debug!($($arg)*);
        }
    };
}

#[macro_export]
macro_rules! debug_token_validation {
    ($($arg:tt)*) => {
        if $crate::debug_config::get_debug_config().token_validation {
            tracing::debug!($($arg)*);
        }
    };
}

/// Correlation ID for tracking related operations
#[derive(Debug, Clone)]
pub struct CorrelationId(String);

impl CorrelationId {
    /// Generate a new correlation ID
    pub fn new() -> Self {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(1);

        let id = COUNTER.fetch_add(1, Ordering::SeqCst);
        let timestamp = chrono::Utc::now().timestamp_millis();
        Self(format!("auth-{}-{}", timestamp, id))
    }

    /// Get the correlation ID as a string
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for CorrelationId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Token metadata for safe logging (no sensitive data)
#[derive(Debug)]
pub struct TokenMetadata {
    pub length: usize,
    pub prefix: String,
    pub suffix: String,
    pub expires_at: Option<String>,
    pub is_expired: Option<bool>,
    pub time_until_expiry: Option<i64>,
}

impl TokenMetadata {
    /// Create token metadata from a token string (safe for logging)
    pub fn from_token(token: &str, expires_at: Option<u64>) -> Self {
        let length = token.len();
        let prefix = if length >= 4 {
            token.chars().take(4).collect()
        } else {
            "****".to_string()
        };
        let suffix = if length >= 4 {
            token.chars().skip(length.saturating_sub(4)).collect()
        } else {
            "****".to_string()
        };

        let (expires_at_str, is_expired, time_until_expiry) = if let Some(expires_timestamp) = expires_at {
            let expires_at_str = Some(
                chrono::DateTime::from_timestamp(expires_timestamp as i64, 0)
                    .map(|dt| dt.to_rfc3339())
                    .unwrap_or_else(|| "invalid_timestamp".to_string())
            );
            let current_time = chrono::Utc::now().timestamp() as u64;
            let is_expired = Some(current_time >= expires_timestamp);
            let time_until_expiry = Some(expires_timestamp as i64 - current_time as i64);
            (expires_at_str, is_expired, time_until_expiry)
        } else {
            (None, None, None)
        };

        Self {
            length,
            prefix,
            suffix,
            expires_at: expires_at_str,
            is_expired,
            time_until_expiry,
        }
    }
}
