use crate::error::{AppError, AppResult};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use specta::Type;

/// Cipher model for encrypted vault items
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cipher {
    pub id: String,
    pub user_id: String,
    pub organization_id: Option<String>,
    pub folder_id: Option<String>,
    pub name: String,
    pub notes: Option<String>,
    pub cipher_type: i32,
    pub encrypted_data: String,
    pub favorite: bool,
    pub reprompt: bool,
    pub revision_date: DateTime<Utc>,
    pub created_date: DateTime<Utc>,
    pub deleted_date: Option<DateTime<Utc>>,
    pub enc_type: i32,
    pub mac: Option<String>,
}

impl Cipher {
    /// Create a Cipher from a database row
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

        let get_bool = |key: &str| -> AppResult<bool> {
            row_obj
                .get(key)
                .and_then(|v| v.as_bool())
                .ok_or_else(|| AppError::DatabaseError {
                    message: format!("Missing or invalid field: {}", key),
                })
        };

        let get_datetime = |key: &str| -> AppResult<DateTime<Utc>> {
            let date_str = get_string(key)?;
            DateTime::parse_from_rfc3339(&date_str)
                .map(|dt| dt.with_timezone(&Utc))
                .map_err(|_| AppError::DatabaseError {
                    message: format!("Invalid datetime format for field: {}", key),
                })
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

        Ok(Cipher {
            id: get_string("id")?,
            user_id: get_string("user_id")?,
            organization_id: get_optional_string("organization_id"),
            folder_id: get_optional_string("folder_id"),
            name: get_string("name")?,
            notes: get_optional_string("notes"),
            cipher_type: get_i32("cipher_type")?,
            encrypted_data: get_string("encrypted_data")?,
            favorite: get_bool("favorite")?,
            reprompt: get_bool("reprompt").unwrap_or(false),
            revision_date: get_datetime("revision_date")?,
            created_date: get_datetime("created_date")?,
            deleted_date: get_optional_datetime("deleted_date")?,
            enc_type: get_i32("enc_type")?,
            mac: get_optional_string("mac"),
        })
    }
}

/// Decrypted cipher view for frontend
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct CipherView {
    pub id: String,
    pub organization_id: Option<String>,
    pub folder_id: Option<String>,
    pub name: String,
    pub notes: Option<String>,
    pub cipher_type: CipherType,
    pub login: Option<LoginView>,
    pub secure_note: Option<SecureNoteView>,
    pub card: Option<CardView>,
    pub identity: Option<IdentityView>,
    pub favorite: bool,
    pub reprompt: bool,
    pub revision_date: DateTime<Utc>,
    pub created_date: DateTime<Utc>,
}

/// Cipher types
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub enum CipherType {
    Login = 1,
    SecureNote = 2,
    Card = 3,
    Identity = 4,
}

/// Login cipher data
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct LoginView {
    pub username: Option<String>,
    pub password: Option<String>,
    pub totp: Option<String>,
    pub uris: Vec<LoginUriView>,
}

/// Login URI data
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct LoginUriView {
    pub uri: Option<String>,
    pub match_type: Option<i32>,
}

/// Secure note cipher data
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct SecureNoteView {
    pub note_type: i32,
}

/// Card cipher data
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct CardView {
    pub cardholder_name: Option<String>,
    pub brand: Option<String>,
    pub number: Option<String>,
    pub exp_month: Option<String>,
    pub exp_year: Option<String>,
    pub code: Option<String>,
}

/// Identity cipher data
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct IdentityView {
    pub title: Option<String>,
    pub first_name: Option<String>,
    pub middle_name: Option<String>,
    pub last_name: Option<String>,
    pub address1: Option<String>,
    pub address2: Option<String>,
    pub address3: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub postal_code: Option<String>,
    pub country: Option<String>,
    pub company: Option<String>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub ssn: Option<String>,
    pub username: Option<String>,
    pub passport_number: Option<String>,
    pub license_number: Option<String>,
}

/// Folder model
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct Folder {
    pub id: String,
    pub user_id: String,
    pub name: String,
    pub revision_date: DateTime<Utc>,
}

impl Folder {
    /// Create a Folder from a database row
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

        let get_datetime = |key: &str| -> AppResult<DateTime<Utc>> {
            let date_str = get_string(key)?;
            DateTime::parse_from_rfc3339(&date_str)
                .map(|dt| dt.with_timezone(&Utc))
                .map_err(|_| AppError::DatabaseError {
                    message: format!("Invalid datetime format for field: {}", key),
                })
        };

        Ok(Folder {
            id: get_string("id")?,
            user_id: get_string("user_id")?,
            name: get_string("name")?,
            revision_date: get_datetime("revision_date")?,
        })
    }
}

/// Collection model
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct Collection {
    pub id: String,
    pub organization_id: String,
    pub name: String,
    pub external_id: Option<String>,
    pub revision_date: DateTime<Utc>,
}

impl Collection {
    /// Create a Collection from a database row
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

        let get_datetime = |key: &str| -> AppResult<DateTime<Utc>> {
            let date_str = get_string(key)?;
            DateTime::parse_from_rfc3339(&date_str)
                .map(|dt| dt.with_timezone(&Utc))
                .map_err(|_| AppError::DatabaseError {
                    message: format!("Invalid datetime format for field: {}", key),
                })
        };

        Ok(Collection {
            id: get_string("id")?,
            organization_id: get_string("organization_id")?,
            name: get_string("name")?,
            external_id: get_optional_string("external_id"),
            revision_date: get_datetime("revision_date")?,
        })
    }
}
