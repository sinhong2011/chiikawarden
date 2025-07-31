use crate::error::{AppError, AppResult};
use crate::storage::database::AppDatabase;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, info};
use uuid::Uuid;

/// Session information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub user_id: String,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub last_activity: DateTime<Utc>,
    pub device_info: Option<String>,
    pub is_active: bool,
}

/// Session creation request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateSessionRequest {
    pub user_id: String,
    pub device_info: Option<String>,
    pub expires_in_hours: Option<i64>, // Default to 24 hours if not specified
}

/// Session service for managing user sessions
pub struct SessionService {
    database: Arc<AppDatabase>,
}

impl SessionService {
    /// Create a new session service
    pub fn new(database: Arc<AppDatabase>) -> Self {
        Self { database }
    }

    /// Create a new session for a user
    pub async fn create_session(&self, request: CreateSessionRequest) -> AppResult<Session> {
        use tracing::{debug, info};

        debug!(
            user_id = request.user_id,
            device_info = request.device_info.as_deref().unwrap_or("unknown"),
            "Creating new session for user"
        );

        let session_id = Uuid::new_v4().to_string();
        let now = Utc::now();
        let expires_in_hours = request.expires_in_hours.unwrap_or(24);
        let expires_at = now + Duration::hours(expires_in_hours);

        let session = Session {
            id: session_id.clone(),
            user_id: request.user_id.clone(),
            expires_at,
            created_at: now,
            last_activity: now,
            device_info: request.device_info.clone(),
            is_active: true,
        };

        // Store session in database
        self.store_session(&session).await?;

        info!(
            user_id = request.user_id,
            session_id = session_id,
            expires_at = %expires_at,
            "Session created successfully"
        );

        Ok(session)
    }

    /// Get session by ID
    pub async fn get_session(&self, session_id: &str) -> AppResult<Option<Session>> {
        debug!(session_id = session_id, "Retrieving session");

        let query = "SELECT id, user_id, expires_at, created_at, last_activity, device_info 
                     FROM sessions WHERE id = ?";
        
        let result = self.database.select_query(
            query,
            vec![serde_json::Value::String(session_id.to_string())],
        ).await?;

        let empty_vec = vec![];
        let rows = result.as_array().unwrap_or(&empty_vec);
        if rows.is_empty() {
            debug!(session_id = session_id, "Session not found");
            return Ok(None);
        }

        let row = &rows[0];
        let session = Session {
            id: row.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            user_id: row.get("user_id").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            expires_at: self.parse_datetime(row.get("expires_at"))?,
            created_at: self.parse_datetime(row.get("created_at"))?,
            last_activity: self.parse_datetime(row.get("last_activity"))?,
            device_info: row.get("device_info").and_then(|v| v.as_str()).map(|s| s.to_string()),
            is_active: !self.is_session_expired(&self.parse_datetime(row.get("expires_at"))?),
        };

        debug!(
            session_id = session_id,
            user_id = session.user_id,
            is_active = session.is_active,
            "Session retrieved"
        );

        Ok(Some(session))
    }

    /// Get all active sessions for a user
    pub async fn get_user_sessions(&self, user_id: &str) -> AppResult<Vec<Session>> {
        debug!(user_id = user_id, "Retrieving all sessions for user");

        let query = "SELECT id, user_id, expires_at, created_at, last_activity, device_info 
                     FROM sessions WHERE user_id = ? ORDER BY last_activity DESC";
        
        let result = self.database.select_query(
            query,
            vec![serde_json::Value::String(user_id.to_string())],
        ).await?;

        let empty_vec = vec![];
        let rows = result.as_array().unwrap_or(&empty_vec);
        let mut sessions = Vec::new();
        for row in rows {
            let expires_at = self.parse_datetime(row.get("expires_at"))?;
            let session = Session {
                id: row.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string(),
                user_id: row.get("user_id").and_then(|v| v.as_str()).unwrap_or("").to_string(),
                expires_at,
                created_at: self.parse_datetime(row.get("created_at"))?,
                last_activity: self.parse_datetime(row.get("last_activity"))?,
                device_info: row.get("device_info").and_then(|v| v.as_str()).map(|s| s.to_string()),
                is_active: !self.is_session_expired(&expires_at),
            };
            sessions.push(session);
        }

        debug!(
            user_id = user_id,
            session_count = sessions.len(),
            active_count = sessions.iter().filter(|s| s.is_active).count(),
            "Retrieved user sessions"
        );

        Ok(sessions)
    }

    /// Update session activity (extend session lifetime)
    pub async fn update_session_activity(&self, session_id: &str) -> AppResult<()> {
        debug!(session_id = session_id, "Updating session activity");

        let now = Utc::now();
        let query = "UPDATE sessions SET last_activity = ? WHERE id = ?";
        
        self.database.execute_query(
            query,
            vec![
                serde_json::Value::String(now.to_rfc3339()),
                serde_json::Value::String(session_id.to_string()),
            ],
        ).await?;

        debug!(session_id = session_id, "Session activity updated");
        Ok(())
    }

    /// Revoke a specific session
    pub async fn revoke_session(&self, session_id: &str) -> AppResult<()> {
        info!(session_id = session_id, "Revoking session");

        let query = "DELETE FROM sessions WHERE id = ?";
        let _result = self.database.execute_query(
            query,
            vec![serde_json::Value::String(session_id.to_string())],
        ).await?;

        info!(session_id = session_id, "Session revoked successfully");

        Ok(())
    }

    /// Revoke all sessions for a user
    pub async fn revoke_all_user_sessions(&self, user_id: &str) -> AppResult<()> {
        info!(user_id = user_id, "Revoking all sessions for user");

        let query = "DELETE FROM sessions WHERE user_id = ?";
        let _result = self.database.execute_query(
            query,
            vec![serde_json::Value::String(user_id.to_string())],
        ).await?;

        info!(
            user_id = user_id,
            "All user sessions revoked"
        );

        Ok(())
    }

    /// Clean up expired sessions
    pub async fn cleanup_expired_sessions(&self) -> AppResult<()> {
        info!("Cleaning up expired sessions");

        let now = Utc::now();
        let query = "DELETE FROM sessions WHERE expires_at < ?";
        let _result = self.database.execute_query(
            query,
            vec![serde_json::Value::String(now.to_rfc3339())],
        ).await?;

        info!("Expired sessions cleanup completed");

        Ok(())
    }

    /// Check if a session is valid and active
    pub async fn is_session_valid(&self, session_id: &str) -> AppResult<bool> {
        match self.get_session(session_id).await? {
            Some(session) => Ok(session.is_active && !self.is_session_expired(&session.expires_at)),
            None => Ok(false),
        }
    }

    /// Store session in database
    async fn store_session(&self, session: &Session) -> AppResult<()> {
        let query = "INSERT INTO sessions (id, user_id, expires_at, created_at, last_activity, device_info) 
                     VALUES (?, ?, ?, ?, ?, ?)";
        
        self.database.execute_query(
            query,
            vec![
                serde_json::Value::String(session.id.clone()),
                serde_json::Value::String(session.user_id.clone()),
                serde_json::Value::String(session.expires_at.to_rfc3339()),
                serde_json::Value::String(session.created_at.to_rfc3339()),
                serde_json::Value::String(session.last_activity.to_rfc3339()),
                session.device_info.as_ref()
                    .map(|s| serde_json::Value::String(s.clone()))
                    .unwrap_or(serde_json::Value::Null),
            ],
        ).await?;

        Ok(())
    }

    /// Parse datetime from database value
    fn parse_datetime(&self, value: Option<&serde_json::Value>) -> AppResult<DateTime<Utc>> {
        match value.and_then(|v| v.as_str()) {
            Some(datetime_str) => {
                DateTime::parse_from_rfc3339(datetime_str)
                    .map(|dt| dt.with_timezone(&Utc))
                    .map_err(|e| AppError::InternalError {
                        message: format!("Failed to parse datetime: {}", e),
                    })
            }
            None => Err(AppError::InternalError {
                message: "Missing datetime value".to_string(),
            }),
        }
    }

    /// Check if session is expired
    fn is_session_expired(&self, expires_at: &DateTime<Utc>) -> bool {
        Utc::now() > *expires_at
    }
}
