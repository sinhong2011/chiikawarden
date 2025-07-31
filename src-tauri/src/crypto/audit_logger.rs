use crate::debug_config::CorrelationId;
use crate::error::{AppError, AppResult};
use crate::storage::database::AppDatabase;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

/// Audit logger for cryptographic operations and authentication events
pub struct AuditLogger {
    database: Arc<AppDatabase>,
}

/// Types of operations that can be audited
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum OperationType {
    // Key Management Operations
    KeyDerivation,
    KeyValidation,
    KeyRotation,
    KeyDestruction,

    // Authentication Operations
    Login,
    Logout,
    Unlock,
    Lock,

    // Device Trust Operations
    DeviceTrustEstablishment,
    DeviceTrustAuthentication,
    DeviceTrustRevocation,

    // WebAuthn Operations
    WebAuthnRegistration,
    WebAuthnAuthentication,
    WebAuthnCredentialUpdate,

    // Cipher Operations
    CipherDecryption,
    CipherEncryption,
    CipherCreation,
    CipherUpdate,

    // Organization Operations
    OrganizationKeyValidation,
    OrganizationAccess,

    // Security Events
    SecurityViolation,
    SuspiciousActivity,
    RateLimitExceeded,
    InvalidAuthentication,
}

/// Result of an audited operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum OperationResult {
    Success,
    Failure,
    PartialSuccess,
    SecurityViolation,
}

/// Severity level for audit events
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SeverityLevel {
    Info,
    Warning,
    Error,
    Critical,
}

/// Audit log entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditLogEntry {
    pub id: String,
    pub user_id: Option<String>,
    pub operation_type: OperationType,
    pub operation_result: OperationResult,
    pub severity: SeverityLevel,
    pub correlation_id: String,
    pub timestamp: DateTime<Utc>,
    pub details: HashMap<String, String>,
    pub error_message: Option<String>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub session_id: Option<String>,
}

impl AuditLogEntry {
    /// Create a new audit log entry
    pub fn new(
        operation_type: OperationType,
        operation_result: OperationResult,
        correlation_id: &CorrelationId,
    ) -> Self {
        let severity = match operation_result {
            OperationResult::Success => SeverityLevel::Info,
            OperationResult::PartialSuccess => SeverityLevel::Warning,
            OperationResult::Failure => SeverityLevel::Error,
            OperationResult::SecurityViolation => SeverityLevel::Critical,
        };

        Self {
            id: Uuid::new_v4().to_string(),
            user_id: None,
            operation_type,
            operation_result,
            severity,
            correlation_id: correlation_id.to_string(),
            timestamp: Utc::now(),
            details: HashMap::new(),
            error_message: None,
            ip_address: None,
            user_agent: None,
            session_id: None,
        }
    }

    /// Set the user ID for this entry
    pub fn with_user_id(mut self, user_id: &str) -> Self {
        self.user_id = Some(user_id.to_string());
        self
    }

    /// Add a detail to this entry
    pub fn with_detail(mut self, key: &str, value: &str) -> Self {
        self.details.insert(key.to_string(), value.to_string());
        self
    }

    /// Add multiple details to this entry
    pub fn with_details(mut self, details: HashMap<String, String>) -> Self {
        self.details.extend(details);
        self
    }

    /// Set the error message for this entry
    pub fn with_error(mut self, error: &AppError) -> Self {
        self.error_message = Some(error.to_string());
        self
    }

    /// Set the IP address for this entry
    pub fn with_ip_address(mut self, ip_address: &str) -> Self {
        self.ip_address = Some(ip_address.to_string());
        self
    }

    /// Set the user agent for this entry
    pub fn with_user_agent(mut self, user_agent: &str) -> Self {
        self.user_agent = Some(user_agent.to_string());
        self
    }

    /// Set the session ID for this entry
    pub fn with_session_id(mut self, session_id: &str) -> Self {
        self.session_id = Some(session_id.to_string());
        self
    }
}

impl AuditLogger {
    /// Create a new audit logger
    pub fn new(database: Arc<AppDatabase>) -> Self {
        Self { database }
    }

    /// Log a successful operation
    pub async fn log_success(
        &self,
        operation_type: OperationType,
        correlation_id: &CorrelationId,
        user_id: Option<&str>,
        details: Option<HashMap<String, String>>,
    ) -> AppResult<()> {
        let mut entry = AuditLogEntry::new(
            operation_type.clone(),
            OperationResult::Success,
            correlation_id,
        );

        if let Some(uid) = user_id {
            entry = entry.with_user_id(uid);
        }

        if let Some(details) = details {
            entry = entry.with_details(details);
        }

        self.store_audit_entry(&entry).await?;

        debug!(
            operation_type = ?operation_type,
            user_id = user_id,
            correlation_id = %correlation_id,
            "[audit] Logged successful operation"
        );

        Ok(())
    }

    /// Log a failed operation
    pub async fn log_failure(
        &self,
        operation_type: OperationType,
        correlation_id: &CorrelationId,
        user_id: Option<&str>,
        error: &AppError,
        details: Option<HashMap<String, String>>,
    ) -> AppResult<()> {
        let mut entry = AuditLogEntry::new(
            operation_type.clone(),
            OperationResult::Failure,
            correlation_id,
        )
        .with_error(error);

        if let Some(uid) = user_id {
            entry = entry.with_user_id(uid);
        }

        if let Some(details) = details {
            entry = entry.with_details(details);
        }

        self.store_audit_entry(&entry).await?;

        warn!(
            operation_type = ?operation_type,
            user_id = user_id,
            error = %error,
            correlation_id = %correlation_id,
            "[audit] Logged failed operation"
        );

        Ok(())
    }

    /// Log a security violation
    pub async fn log_security_violation(
        &self,
        operation_type: OperationType,
        correlation_id: &CorrelationId,
        user_id: Option<&str>,
        violation_details: &str,
        additional_details: Option<HashMap<String, String>>,
    ) -> AppResult<()> {
        let mut entry = AuditLogEntry::new(
            operation_type.clone(),
            OperationResult::SecurityViolation,
            correlation_id,
        )
        .with_detail("violation_type", violation_details);

        if let Some(uid) = user_id {
            entry = entry.with_user_id(uid);
        }

        if let Some(details) = additional_details {
            entry = entry.with_details(details);
        }

        self.store_audit_entry(&entry).await?;

        error!(
            operation_type = ?operation_type,
            user_id = user_id,
            violation = violation_details,
            correlation_id = %correlation_id,
            "[audit] SECURITY VIOLATION logged"
        );

        Ok(())
    }

    /// Log key derivation operation
    pub async fn log_key_derivation(
        &self,
        user_id: &str,
        correlation_id: &CorrelationId,
        success: bool,
        key_type: &str,
        derivation_method: &str,
    ) -> AppResult<()> {
        let mut details = HashMap::new();
        details.insert("key_type".to_string(), key_type.to_string());
        details.insert(
            "derivation_method".to_string(),
            derivation_method.to_string(),
        );

        if success {
            self.log_success(
                OperationType::KeyDerivation,
                correlation_id,
                Some(user_id),
                Some(details),
            )
            .await
        } else {
            let error = AppError::CryptographyError {
                operation: "Key derivation failed".to_string(),
            };
            self.log_failure(
                OperationType::KeyDerivation,
                correlation_id,
                Some(user_id),
                &error,
                Some(details),
            )
            .await
        }
    }

    /// Log authentication attempt
    pub async fn log_authentication(
        &self,
        user_id: &str,
        correlation_id: &CorrelationId,
        auth_method: &str,
        success: bool,
        failure_reason: Option<&str>,
    ) -> AppResult<()> {
        let mut details = HashMap::new();
        details.insert("auth_method".to_string(), auth_method.to_string());

        if let Some(reason) = failure_reason {
            details.insert("failure_reason".to_string(), reason.to_string());
        }

        if success {
            self.log_success(
                OperationType::Login,
                correlation_id,
                Some(user_id),
                Some(details),
            )
            .await
        } else {
            let error = AppError::AuthenticationError {
                message: failure_reason
                    .unwrap_or("Authentication failed")
                    .to_string(),
            };
            self.log_failure(
                OperationType::Login,
                correlation_id,
                Some(user_id),
                &error,
                Some(details),
            )
            .await
        }
    }

    /// Store audit entry in database
    async fn store_audit_entry(&self, entry: &AuditLogEntry) -> AppResult<()> {
        let query = r#"
            INSERT INTO key_operations_log
            (id, user_id, operation_type, operation_result, severity, correlation_id, timestamp,
             details, error_message, ip_address, user_agent, session_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        "#;

        let details_json =
            serde_json::to_string(&entry.details).map_err(|e| AppError::DatabaseError {
                message: format!("Failed to serialize audit details: {}", e),
            })?;

        self.database
            .execute_query(
                query,
                vec![
                    serde_json::Value::String(entry.id.clone()),
                    entry
                        .user_id
                        .as_ref()
                        .map(|s| serde_json::Value::String(s.clone()))
                        .unwrap_or(serde_json::Value::Null),
                    serde_json::Value::String(format!("{:?}", entry.operation_type)),
                    serde_json::Value::String(format!("{:?}", entry.operation_result)),
                    serde_json::Value::String(format!("{:?}", entry.severity)),
                    serde_json::Value::String(entry.correlation_id.clone()),
                    serde_json::Value::String(entry.timestamp.to_rfc3339()),
                    serde_json::Value::String(details_json),
                    entry
                        .error_message
                        .as_ref()
                        .map(|s| serde_json::Value::String(s.clone()))
                        .unwrap_or(serde_json::Value::Null),
                    entry
                        .ip_address
                        .as_ref()
                        .map(|s| serde_json::Value::String(s.clone()))
                        .unwrap_or(serde_json::Value::Null),
                    entry
                        .user_agent
                        .as_ref()
                        .map(|s| serde_json::Value::String(s.clone()))
                        .unwrap_or(serde_json::Value::Null),
                    entry
                        .session_id
                        .as_ref()
                        .map(|s| serde_json::Value::String(s.clone()))
                        .unwrap_or(serde_json::Value::Null),
                ],
            )
            .await?;

        Ok(())
    }

    /// Get audit logs for a user
    pub async fn get_user_audit_logs(
        &self,
        user_id: &str,
        limit: Option<u32>,
        offset: Option<u32>,
    ) -> AppResult<Vec<AuditLogEntry>> {
        let limit = limit.unwrap_or(100);
        let offset = offset.unwrap_or(0);

        let query = r#"
            SELECT id, user_id, operation_type, operation_result, severity, correlation_id,
                   timestamp, details, error_message, ip_address, user_agent, session_id
            FROM key_operations_log
            WHERE user_id = ?
            ORDER BY timestamp DESC
            LIMIT ? OFFSET ?
        "#;

        let result = self
            .database
            .select_query(
                query,
                vec![
                    serde_json::Value::String(user_id.to_string()),
                    serde_json::Value::Number((limit as i64).into()),
                    serde_json::Value::Number((offset as i64).into()),
                ],
            )
            .await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Expected array result from audit log query".to_string(),
        })?;

        let mut entries = Vec::new();
        for row in rows {
            entries.push(self.parse_audit_entry(row)?);
        }

        Ok(entries)
    }

    /// Parse audit entry from database row
    fn parse_audit_entry(&self, row: &serde_json::Value) -> AppResult<AuditLogEntry> {
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

        let details_json = get_string("details")?;
        let details: HashMap<String, String> =
            serde_json::from_str(&details_json).map_err(|e| AppError::DatabaseError {
                message: format!("Failed to parse audit details: {}", e),
            })?;

        let timestamp_str = get_string("timestamp")?;
        let timestamp = DateTime::parse_from_rfc3339(&timestamp_str)
            .map(|dt| dt.with_timezone(&Utc))
            .map_err(|_| AppError::DatabaseError {
                message: "Invalid timestamp format".to_string(),
            })?;

        // Parse enums from strings
        let operation_type = match get_string("operation_type")?.as_str() {
            "KeyDerivation" => OperationType::KeyDerivation,
            "KeyValidation" => OperationType::KeyValidation,
            "Login" => OperationType::Login,
            "DeviceTrustEstablishment" => OperationType::DeviceTrustEstablishment,
            "DeviceTrustAuthentication" => OperationType::DeviceTrustAuthentication,
            "CipherDecryption" => OperationType::CipherDecryption,
            _ => OperationType::SecurityViolation, // Default for unknown types
        };

        let operation_result = match get_string("operation_result")?.as_str() {
            "Success" => OperationResult::Success,
            "Failure" => OperationResult::Failure,
            "PartialSuccess" => OperationResult::PartialSuccess,
            "SecurityViolation" => OperationResult::SecurityViolation,
            _ => OperationResult::Failure, // Default for unknown results
        };

        let severity = match get_string("severity")?.as_str() {
            "Info" => SeverityLevel::Info,
            "Warning" => SeverityLevel::Warning,
            "Error" => SeverityLevel::Error,
            "Critical" => SeverityLevel::Critical,
            _ => SeverityLevel::Error, // Default for unknown severity
        };

        Ok(AuditLogEntry {
            id: get_string("id")?,
            user_id: get_optional_string("user_id"),
            operation_type,
            operation_result,
            severity,
            correlation_id: get_string("correlation_id")?,
            timestamp,
            details,
            error_message: get_optional_string("error_message"),
            ip_address: get_optional_string("ip_address"),
            user_agent: get_optional_string("user_agent"),
            session_id: get_optional_string("session_id"),
        })
    }
}
