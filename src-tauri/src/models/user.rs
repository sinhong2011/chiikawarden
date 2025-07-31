use crate::error::{AppError, AppResult};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use specta::Type;

/// User model with new key management structure (BREAKING CHANGE)
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct User {
    pub id: String,
    pub email: String,
    pub master_key_hash: Option<String>,
    // BREAKING: Removed old encrypted_private_key and encrypted_user_key
    // These are replaced with new fields that follow proper key management patterns
    pub encrypted_private_key_new: Option<String>,
    pub encrypted_user_key_new: Option<String>,
    pub key_derivation_method: String, // 'server_provided', 'device_trust', 'webauthn_prf'
    pub device_trust_enabled: bool,
    pub webauthn_enabled: bool,
    pub server_provider_id: String,
    pub kdf_type: i32,
    pub kdf_iterations: i32,
    pub kdf_memory: Option<i32>,
    pub kdf_parallelism: Option<i32>,
    pub created_date: DateTime<Utc>,
    pub revision_date: DateTime<Utc>,
}

impl User {
    /// Create a User from a database row
    pub fn from_database_row(row: &Value) -> AppResult<Self> {
        let row_obj = row.as_object().ok_or_else(|| AppError::DatabaseError {
            message: "Invalid row format".to_string(),
        })?;

        let get_string = |key: &str| -> AppResult<String> {
            row_obj
                .get(key)
                .and_then(|v| v.as_str())
                .ok_or_else(|| AppError::DatabaseError {
                    message: format!("Missing or invalid field: {}", key),
                })
                .map(|s| s.to_string())
        };

        let get_optional_string = |key: &str| -> Option<String> {
            row_obj
                .get(key)
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
        };

        let get_i32 = |key: &str| -> AppResult<i32> {
            row_obj
                .get(key)
                .and_then(|v| v.as_i64())
                .ok_or_else(|| AppError::DatabaseError {
                    message: format!("Missing or invalid field: {}", key),
                })
                .map(|i| i as i32)
        };

        let get_optional_i32 = |key: &str| -> Option<i32> {
            row_obj.get(key).and_then(|v| v.as_i64()).map(|i| i as i32)
        };

        let get_bool = |key: &str| -> AppResult<bool> {
            row_obj
                .get(key)
                .and_then(|v| v.as_i64())
                .ok_or_else(|| AppError::DatabaseError {
                    message: format!("Missing or invalid boolean field: {}", key),
                })
                .map(|i| i != 0)
        };

        let get_datetime = |key: &str| -> AppResult<DateTime<Utc>> {
            let date_str = get_string(key)?;
            DateTime::parse_from_rfc3339(&date_str)
                .map(|dt| dt.with_timezone(&Utc))
                .map_err(|_| AppError::DatabaseError {
                    message: format!("Invalid datetime format for field: {}", key),
                })
        };

        Ok(User {
            id: get_string("id")?,
            email: get_string("email")?,
            master_key_hash: get_optional_string("master_key_hash"),
            // BREAKING: Use new key management fields
            encrypted_private_key_new: get_optional_string("encrypted_private_key_new"),
            encrypted_user_key_new: get_optional_string("encrypted_user_key_new"),
            key_derivation_method: get_string("key_derivation_method")
                .unwrap_or_else(|_| "server_provided".to_string()),
            device_trust_enabled: get_bool("device_trust_enabled").unwrap_or(false),
            webauthn_enabled: get_bool("webauthn_enabled").unwrap_or(false),
            server_provider_id: get_string("server_provider_id")
                .unwrap_or_else(|_| "us-cloud".to_string()),
            kdf_type: get_i32("kdf_type")?,
            kdf_iterations: get_i32("kdf_iterations")?,
            kdf_memory: get_optional_i32("kdf_memory"),
            kdf_parallelism: get_optional_i32("kdf_parallelism"),
            created_date: get_datetime("created_date")?,
            revision_date: get_datetime("revision_date")?,
        })
    }
}

/// Device trust information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct TrustedDevice {
    pub id: String,
    pub user_id: String,
    pub device_identifier: String,
    pub device_name: Option<String>,
    pub device_type: String,
    pub encrypted_device_public_key: String,
    pub encrypted_device_private_key: String,
    pub encrypted_user_key: String,
    pub device_key_encrypted: String,
    pub trust_established_at: DateTime<Utc>,
    pub last_used_at: Option<DateTime<Utc>>,
    pub is_active: bool,
}

impl TrustedDevice {
    pub fn from_database_row(row: &serde_json::Value) -> AppResult<Self> {
        let get_string = |key: &str| -> AppResult<String> {
            row.get(key)
                .and_then(|v| v.as_str())
                .ok_or_else(|| AppError::DatabaseError {
                    message: format!("Missing or invalid string field: {}", key),
                })
                .map(|s| s.to_string())
        };

        let get_optional_string = |key: &str| -> Option<String> {
            row.get(key).and_then(|v| v.as_str()).map(|s| s.to_string())
        };

        let get_bool = |key: &str| -> AppResult<bool> {
            row.get(key)
                .and_then(|v| v.as_i64())
                .ok_or_else(|| AppError::DatabaseError {
                    message: format!("Missing or invalid boolean field: {}", key),
                })
                .map(|i| i != 0)
        };

        let get_datetime = |key: &str| -> AppResult<DateTime<Utc>> {
            let date_str = get_string(key)?;
            DateTime::parse_from_rfc3339(&date_str)
                .map(|dt| dt.with_timezone(&Utc))
                .map_err(|_| AppError::DatabaseError {
                    message: format!("Invalid datetime format for field: {}", key),
                })
        };

        let get_optional_datetime = |key: &str| -> Option<DateTime<Utc>> {
            get_optional_string(key)
                .and_then(|date_str| DateTime::parse_from_rfc3339(&date_str).ok())
                .map(|dt| dt.with_timezone(&Utc))
        };

        Ok(TrustedDevice {
            id: get_string("id")?,
            user_id: get_string("user_id")?,
            device_identifier: get_string("device_identifier")?,
            device_name: get_optional_string("device_name"),
            device_type: get_string("device_type")?,
            encrypted_device_public_key: get_string("encrypted_device_public_key")?,
            encrypted_device_private_key: get_string("encrypted_device_private_key")?,
            encrypted_user_key: get_string("encrypted_user_key")?,
            device_key_encrypted: get_string("device_key_encrypted")?,
            trust_established_at: get_datetime("trust_established_at")?,
            last_used_at: get_optional_datetime("last_used_at"),
            is_active: get_bool("is_active")?,
        })
    }
}

/// WebAuthn credential information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct WebAuthnCredential {
    pub id: String,
    pub user_id: String,
    pub credential_id: String,
    pub public_key: String,
    pub counter: i32,
    pub prf_salt: Option<String>,
    pub name: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_used_at: Option<DateTime<Utc>>,
    pub is_active: bool,
}

/// Sync mode indicating current operational state
#[derive(Debug, Clone, Serialize, Deserialize, Type, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum SyncMode {
    Online,  // Full CRUD operations available
    Offline, // Read-only access to cached data
}

impl std::fmt::Display for SyncMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SyncMode::Online => write!(f, "online"),
            SyncMode::Offline => write!(f, "offline"),
        }
    }
}

/// Network-aware sync state model
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncState {
    pub user_id: String,
    pub last_sync: Option<DateTime<Utc>>,
    pub revision_date: Option<DateTime<Utc>>,
    // Network-aware sync fields
    pub is_syncing: bool,
    pub sync_mode: SyncMode,
    pub last_websocket_connection: Option<DateTime<Utc>>,
    pub websocket_connected: bool,
    pub background_sync_enabled: bool,
    pub sync_interval_hours: u32,
    pub last_server_notification: Option<DateTime<Utc>>,
    pub server_revision_date: Option<DateTime<Utc>>,
    pub network_state: String, // "online", "offline", "limited", "unknown"
    pub last_online_sync: Option<DateTime<Utc>>,
    pub cached_items_count: u32,
}

impl SyncState {
    /// Create a SyncState from a database row
    pub fn from_database_row(row: &Value) -> AppResult<Self> {
        let row_obj = row.as_object().ok_or_else(|| AppError::DatabaseError {
            message: "Invalid row format".to_string(),
        })?;

        let get_string = |key: &str| -> AppResult<String> {
            row_obj
                .get(key)
                .and_then(|v| v.as_str())
                .ok_or_else(|| AppError::DatabaseError {
                    message: format!("Missing or invalid field: {}", key),
                })
                .map(|s| s.to_string())
        };

        let get_optional_string = |key: &str| -> Option<String> {
            row_obj
                .get(key)
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
        };

        let get_optional_datetime = |key: &str| -> AppResult<Option<DateTime<Utc>>> {
            match get_optional_string(key) {
                Some(date_str) => {
                    let dt = DateTime::parse_from_rfc3339(&date_str)
                        .map(|dt| dt.with_timezone(&Utc))
                        .map_err(|_| AppError::DatabaseError {
                            message: format!("Invalid datetime format for field: {}", key),
                        })?;
                    Ok(Some(dt))
                }
                None => Ok(None),
            }
        };

        let get_optional_bool =
            |key: &str| -> bool { row_obj.get(key).and_then(|v| v.as_bool()).unwrap_or(false) };

        let get_optional_u32 = |key: &str, default: u32| -> u32 {
            row_obj
                .get(key)
                .and_then(|v| v.as_u64())
                .map(|v| v as u32)
                .unwrap_or(default)
        };

        let _get_optional_u8 = |key: &str, default: u8| -> u8 {
            row_obj
                .get(key)
                .and_then(|v| v.as_u64())
                .map(|v| v as u8)
                .unwrap_or(default)
        };

        let get_optional_string_with_default = |key: &str, default: &str| -> String {
            row_obj
                .get(key)
                .and_then(|v| v.as_str())
                .unwrap_or(default)
                .to_string()
        };

        // Determine sync mode based on network state
        let network_state = get_optional_string_with_default("network_state", "unknown");
        let sync_mode = match network_state.as_str() {
            "online" => SyncMode::Online,
            _ => SyncMode::Offline,
        };

        Ok(SyncState {
            user_id: get_string("user_id")?,
            last_sync: get_optional_datetime("last_sync")?,
            revision_date: get_optional_datetime("revision_date")?,
            is_syncing: get_optional_bool("is_syncing"),
            sync_mode,
            last_websocket_connection: get_optional_datetime("last_websocket_connection")?,
            websocket_connected: get_optional_bool("websocket_connected"),
            background_sync_enabled: get_optional_bool("background_sync_enabled"),
            sync_interval_hours: get_optional_u32("sync_interval_hours", 6),
            last_server_notification: get_optional_datetime("last_server_notification")?,
            server_revision_date: get_optional_datetime("server_revision_date")?,
            network_state,
            last_online_sync: get_optional_datetime("last_online_sync")?,
            cached_items_count: get_optional_u32("cached_items_count", 0),
        })
    }
}
