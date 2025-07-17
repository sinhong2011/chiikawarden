use crate::error::{AppError, AppResult};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// User model
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub email: String,
    pub encrypted_private_key: Option<String>,
    pub encrypted_user_key: Option<String>,
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
            encrypted_private_key: get_optional_string("encrypted_private_key"),
            encrypted_user_key: get_optional_string("encrypted_user_key"),
            kdf_type: get_i32("kdf_type")?,
            kdf_iterations: get_i32("kdf_iterations")?,
            kdf_memory: get_optional_i32("kdf_memory"),
            kdf_parallelism: get_optional_i32("kdf_parallelism"),
            created_date: get_datetime("created_date")?,
            revision_date: get_datetime("revision_date")?,
        })
    }
}

/// Sync state model
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncState {
    pub user_id: String,
    pub last_sync: Option<DateTime<Utc>>,
    pub revision_date: Option<DateTime<Utc>>,
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

        Ok(SyncState {
            user_id: get_string("user_id")?,
            last_sync: get_optional_datetime("last_sync")?,
            revision_date: get_optional_datetime("revision_date")?,
        })
    }
}
