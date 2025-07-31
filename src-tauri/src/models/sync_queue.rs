use crate::error::{AppError, AppResult};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use specta::Type;

/// Sync operation types
#[derive(Debug, Clone, Serialize, Deserialize, Type, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum SyncOperationType {
    Create,
    Update,
    Delete,
}

impl std::fmt::Display for SyncOperationType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SyncOperationType::Create => write!(f, "create"),
            SyncOperationType::Update => write!(f, "update"),
            SyncOperationType::Delete => write!(f, "delete"),
        }
    }
}

impl std::str::FromStr for SyncOperationType {
    type Err = AppError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "create" => Ok(SyncOperationType::Create),
            "update" => Ok(SyncOperationType::Update),
            "delete" => Ok(SyncOperationType::Delete),
            _ => Err(AppError::ValidationError {
                message: format!("Invalid sync operation type: {}", s),
            }),
        }
    }
}

/// Item types that can be synchronized
#[derive(Debug, Clone, Serialize, Deserialize, Type, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ItemType {
    Cipher,
    Folder,
    Collection,
}

impl std::fmt::Display for ItemType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ItemType::Cipher => write!(f, "cipher"),
            ItemType::Folder => write!(f, "folder"),
            ItemType::Collection => write!(f, "collection"),
        }
    }
}

impl std::str::FromStr for ItemType {
    type Err = AppError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "cipher" => Ok(ItemType::Cipher),
            "folder" => Ok(ItemType::Folder),
            "collection" => Ok(ItemType::Collection),
            _ => Err(AppError::ValidationError {
                message: format!("Invalid item type: {}", s),
            }),
        }
    }
}

/// Sync queue item status
#[derive(Debug, Clone, Serialize, Deserialize, Type, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum SyncQueueStatus {
    Pending,
    Processing,
    Completed,
    Failed,
}

impl std::fmt::Display for SyncQueueStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SyncQueueStatus::Pending => write!(f, "pending"),
            SyncQueueStatus::Processing => write!(f, "processing"),
            SyncQueueStatus::Completed => write!(f, "completed"),
            SyncQueueStatus::Failed => write!(f, "failed"),
        }
    }
}

impl std::str::FromStr for SyncQueueStatus {
    type Err = AppError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "pending" => Ok(SyncQueueStatus::Pending),
            "processing" => Ok(SyncQueueStatus::Processing),
            "completed" => Ok(SyncQueueStatus::Completed),
            "failed" => Ok(SyncQueueStatus::Failed),
            _ => Err(AppError::ValidationError {
                message: format!("Invalid sync queue status: {}", s),
            }),
        }
    }
}

/// Sync queue item for offline operations and prioritization
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct SyncQueueItem {
    pub id: String,
    pub user_id: String,
    pub operation_type: SyncOperationType,
    pub item_type: ItemType,
    pub item_id: String,
    pub priority: u8, // 0-10 scale (10 = highest)
    pub created_at: DateTime<Utc>,
    pub retry_count: u32,
    pub max_retries: u32,
    pub last_attempt: Option<DateTime<Utc>>,
    pub payload: Value, // JSON payload for the operation
    pub error_message: Option<String>,
    pub status: SyncQueueStatus,
}

impl SyncQueueItem {
    /// Create a new sync queue item
    pub fn new(
        user_id: String,
        operation_type: SyncOperationType,
        item_type: ItemType,
        item_id: String,
        payload: Value,
    ) -> Self {
        Self {
            id: crate::models::new_uuid(),
            user_id,
            operation_type,
            item_type,
            item_id,
            priority: 5, // Default priority
            created_at: Utc::now(),
            retry_count: 0,
            max_retries: 3,
            last_attempt: None,
            payload,
            error_message: None,
            status: SyncQueueStatus::Pending,
        }
    }

    /// Create a high priority sync queue item
    pub fn new_high_priority(
        user_id: String,
        operation_type: SyncOperationType,
        item_type: ItemType,
        item_id: String,
        payload: Value,
    ) -> Self {
        let mut item = Self::new(user_id, operation_type, item_type, item_id, payload);
        item.priority = 8;
        item
    }

    /// Check if the item can be retried
    pub fn can_retry(&self) -> bool {
        self.retry_count < self.max_retries && self.status == SyncQueueStatus::Failed
    }

    /// Mark the item as processing
    pub fn mark_processing(&mut self) {
        self.status = SyncQueueStatus::Processing;
        self.last_attempt = Some(Utc::now());
    }

    /// Mark the item as completed
    pub fn mark_completed(&mut self) {
        self.status = SyncQueueStatus::Completed;
    }

    /// Mark the item as failed with error message
    pub fn mark_failed(&mut self, error_message: String) {
        self.status = SyncQueueStatus::Failed;
        self.error_message = Some(error_message);
        self.retry_count += 1;
    }

    /// Create a SyncQueueItem from a database row
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

        let get_u32 = |key: &str| -> AppResult<u32> {
            row_obj
                .get(key)
                .and_then(|v| v.as_u64())
                .map(|v| v as u32)
                .ok_or_else(|| AppError::DatabaseError {
                    message: format!("Missing or invalid field: {}", key),
                })
        };

        let get_u8 = |key: &str| -> AppResult<u8> {
            row_obj
                .get(key)
                .and_then(|v| v.as_u64())
                .map(|v| v as u8)
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

        let payload_str = get_string("payload")?;
        let payload: Value = serde_json::from_str(&payload_str).map_err(|_| {
            AppError::DatabaseError {
                message: "Invalid JSON payload".to_string(),
            }
        })?;

        Ok(SyncQueueItem {
            id: get_string("id")?,
            user_id: get_string("user_id")?,
            operation_type: get_string("operation_type")?.parse()?,
            item_type: get_string("item_type")?.parse()?,
            item_id: get_string("item_id")?,
            priority: get_u8("priority")?,
            created_at: get_datetime("created_at")?,
            retry_count: get_u32("retry_count")?,
            max_retries: get_u32("max_retries")?,
            last_attempt: get_optional_datetime("last_attempt")?,
            payload,
            error_message: get_optional_string("error_message"),
            status: get_string("status")?.parse()?,
        })
    }
}
