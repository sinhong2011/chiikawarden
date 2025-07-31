use rand;
use serde::{Deserialize, Serialize};
use specta::Type;
use thiserror::Error;
use tokio;
use tracing::{error, info, warn};

/// Application error types with enhanced classification for better error handling
#[derive(Error, Debug, Clone, Serialize, Deserialize, Type)]
pub enum AppError {
    #[error("Authentication failed: {message}")]
    AuthenticationError { message: String },

    #[error("Re-authentication required: {message}")]
    ReAuthenticationRequired { message: String },

    #[error("Encryption error: {operation}")]
    CryptographyError { operation: String },

    #[error("Crypto error: {message}")]
    CryptoError { message: String },

    /// MAC verification failed - could be transient data corruption or invalid key
    #[error("MAC verification failed: {context} - {message}")]
    MacVerificationError { context: String, message: String },

    /// Key validation failed - permanent authentication issue
    #[error("Key validation failed: {key_type} - {message}")]
    KeyValidationError { key_type: String, message: String },

    /// Transient decryption failure - retry may succeed
    #[error("Transient decryption failure in {operation}: {message} (attempt {retry_count})")]
    TransientDecryptionError {
        operation: String,
        message: String,
        retry_count: u32,
    },

    /// Permanent decryption failure - retry will not succeed
    #[error("Permanent decryption failure in {operation}: {message}")]
    PermanentDecryptionError { operation: String, message: String },

    /// Cache operation failed
    #[error("Cache operation failed for {operation}: {message}")]
    CacheError { operation: String, message: String },

    /// Circuit breaker is open - too many failures detected
    #[error("Circuit breaker open for {service}: {message} (failures: {failure_count})")]
    CircuitBreakerError {
        service: String,
        message: String,
        failure_count: u32,
    },

    #[error("Database error: {message}")]
    DatabaseError { message: String },

    #[error("Network error: {status} - {message}")]
    NetworkError { status: u16, message: String },

    #[error("Storage error: {message}")]
    StorageError { message: String },

    #[error("Validation error: {field} - {message}")]
    ValidationError { field: String, message: String },

    #[error("Configuration error: {message}")]
    ConfigurationError { message: String },

    #[error("Biometric error: {message}")]
    BiometricError { message: String },

    #[error("Sync error: {message}")]
    SyncError { message: String },

    #[error("Internal error: {message}")]
    InternalError { message: String },
}

// Database errors are now handled through SQLx
impl From<sqlx::Error> for AppError {
    fn from(err: sqlx::Error) -> Self {
        AppError::DatabaseError {
            message: format!("SQLx error: {}", err),
        }
    }
}

impl From<tauri_plugin_http::reqwest::Error> for AppError {
    fn from(err: tauri_plugin_http::reqwest::Error) -> Self {
        let status = err.status().map(|s| s.as_u16()).unwrap_or(0);
        AppError::NetworkError {
            status,
            message: err.to_string(),
        }
    }
}

impl From<serde_json::Error> for AppError {
    fn from(err: serde_json::Error) -> Self {
        AppError::InternalError {
            message: format!("JSON error: {}", err),
        }
    }
}

impl From<std::io::Error> for AppError {
    fn from(err: std::io::Error) -> Self {
        AppError::StorageError {
            message: err.to_string(),
        }
    }
}

impl From<crate::crypto::CryptoError> for AppError {
    fn from(err: crate::crypto::CryptoError) -> Self {
        AppError::CryptographyError {
            operation: err.to_string(),
        }
    }
}

/// Result type alias for application operations
pub type AppResult<T> = Result<T, AppError>;

/// Convert AppError to String for Tauri commands
impl From<AppError> for String {
    fn from(err: AppError) -> Self {
        // Log the error before converting to string
        error!(error = %err, "Application error occurred");
        err.to_string()
    }
}

impl AppError {
    /// Log this error with additional context
    pub fn log_with_context(&self, context: &str) {
        error!(
            error = %self,
            context = context,
            "Application error with context"
        );
    }

    /// Create and log an authentication error
    pub fn auth_error(message: String) -> Self {
        let err = AppError::AuthenticationError { message };
        error!(error = %err, "Authentication error");
        err
    }

    /// Create and log a re-authentication required error
    pub fn reauth_required(message: String) -> Self {
        let err = AppError::ReAuthenticationRequired { message };
        warn!(error = %err, "Re-authentication required");
        err
    }

    /// Create and log a cryptography error
    pub fn crypto_error(operation: String) -> Self {
        let err = AppError::CryptographyError { operation };
        error!(error = %err, "Cryptography error");
        err
    }

    /// Create and log a database error
    pub fn db_error(message: String) -> Self {
        let err = AppError::DatabaseError { message };
        error!(error = %err, "Database error");
        err
    }

    /// Create and log a network error
    pub fn network_error(status: u16, message: String) -> Self {
        let err = AppError::NetworkError { status, message };
        error!(error = %err, "Network error");
        err
    }

    /// Create and log a storage error
    pub fn storage_error(message: String) -> Self {
        let err = AppError::StorageError { message };
        error!(error = %err, "Storage error");
        err
    }

    /// Create and log a MAC verification error
    pub fn mac_verification_error(context: String, message: String) -> Self {
        let err = AppError::MacVerificationError { context, message };
        warn!(error = %err, "MAC verification failed");
        err
    }

    /// Create and log a key validation error
    pub fn key_validation_error(key_type: String, message: String) -> Self {
        let err = AppError::KeyValidationError { key_type, message };
        error!(error = %err, "Key validation failed");
        err
    }

    /// Create and log a transient decryption error
    pub fn transient_decryption_error(
        operation: String,
        message: String,
        retry_count: u32,
    ) -> Self {
        let err = AppError::TransientDecryptionError {
            operation,
            message,
            retry_count,
        };
        warn!(error = %err, "Transient decryption failure");
        err
    }

    /// Create and log a permanent decryption error
    pub fn permanent_decryption_error(operation: String, message: String) -> Self {
        let err = AppError::PermanentDecryptionError { operation, message };
        error!(error = %err, "Permanent decryption failure");
        err
    }

    /// Create and log a cache error
    pub fn cache_error(operation: String, message: String) -> Self {
        let err = AppError::CacheError { operation, message };
        warn!(error = %err, "Cache operation failed");
        err
    }

    /// Create and log a circuit breaker error
    pub fn circuit_breaker_error(service: String, message: String, failure_count: u32) -> Self {
        let err = AppError::CircuitBreakerError {
            service,
            message,
            failure_count,
        };
        warn!(error = %err, "Circuit breaker opened");
        err
    }

    /// Create and log a validation error
    pub fn validation_error(field: String, message: String) -> Self {
        let err = AppError::ValidationError { field, message };
        error!(error = %err, "Validation error");
        err
    }

    /// Get error category for metrics
    pub fn category(&self) -> &'static str {
        match self {
            AppError::AuthenticationError { .. } => "authentication",
            AppError::ReAuthenticationRequired { .. } => "re_authentication",
            AppError::CryptographyError { .. } => "cryptography",
            AppError::CryptoError { .. } => "crypto",
            AppError::MacVerificationError { .. } => "mac_verification",
            AppError::KeyValidationError { .. } => "key_validation",
            AppError::TransientDecryptionError { .. } => "transient_decryption",
            AppError::PermanentDecryptionError { .. } => "permanent_decryption",
            AppError::CacheError { .. } => "cache",
            AppError::CircuitBreakerError { .. } => "circuit_breaker",
            AppError::DatabaseError { .. } => "database",
            AppError::NetworkError { .. } => "network",
            AppError::StorageError { .. } => "storage",
            AppError::ValidationError { .. } => "validation",
            AppError::ConfigurationError { .. } => "configuration",
            AppError::BiometricError { .. } => "biometric",
            AppError::SyncError { .. } => "sync",
            AppError::InternalError { .. } => "internal",
        }
    }

    /// Check if error is retryable
    pub fn is_retryable(&self) -> bool {
        match self {
            AppError::NetworkError { status, .. } => {
                // Retry on 5xx errors and some 4xx errors
                *status >= 500 || *status == 408 || *status == 429
            }
            AppError::DatabaseError { .. } => true, // Database errors might be transient
            AppError::SyncError { .. } => true,     // Sync errors are often retryable
            AppError::TransientDecryptionError { .. } => true, // Explicitly retryable
            AppError::MacVerificationError { .. } => true, // Could be transient data corruption
            AppError::CacheError { .. } => true,    // Cache operations can be retried
            _ => false,
        }
    }

    /// Get retry delay in milliseconds for retryable errors
    pub fn retry_delay(&self, attempt: u32) -> Option<u64> {
        if !self.is_retryable() {
            return None;
        }

        // Exponential backoff with jitter
        let base_delay = match self {
            AppError::NetworkError { status, .. } => {
                if *status == 429 {
                    5000 // Rate limiting - longer delay
                } else {
                    1000 // Regular network error
                }
            }
            AppError::DatabaseError { .. } => 500,
            AppError::SyncError { .. } => 2000,
            _ => 1000,
        };

        let exponential_delay = base_delay * 2_u64.pow(attempt.min(5));
        let jitter = rand::random::<u64>() % (exponential_delay / 4);
        Some(exponential_delay + jitter)
    }

    /// Get maximum retry attempts for this error type
    pub fn max_retry_attempts(&self) -> u32 {
        match self {
            AppError::NetworkError { status, .. } => {
                if *status >= 500 || *status == 408 {
                    5 // Server errors - more retries
                } else if *status == 429 {
                    3 // Rate limiting - fewer retries
                } else {
                    0 // Client errors - no retries
                }
            }
            AppError::DatabaseError { .. } => 3,
            AppError::SyncError { .. } => 5,
            AppError::TransientDecryptionError { .. } => 3,
            AppError::MacVerificationError { .. } => 2, // Limited retries for MAC failures
            AppError::CacheError { .. } => 2,
            _ => 0,
        }
    }

    /// Check if this error should trigger key invalidation
    pub fn should_invalidate_key(&self) -> bool {
        matches!(
            self,
            AppError::KeyValidationError { .. } | AppError::AuthenticationError { .. }
        )
    }

    /// Check if this error is a crypto-related failure
    pub fn is_crypto_error(&self) -> bool {
        matches!(
            self,
            AppError::CryptographyError { .. }
                | AppError::CryptoError { .. }
                | AppError::MacVerificationError { .. }
                | AppError::KeyValidationError { .. }
                | AppError::TransientDecryptionError { .. }
                | AppError::PermanentDecryptionError { .. }
        )
    }

    /// Check if this error should trigger circuit breaker
    pub fn should_trigger_circuit_breaker(&self) -> bool {
        matches!(
            self,
            AppError::PermanentDecryptionError { .. } | AppError::KeyValidationError { .. }
        )
    }

    /// Get retry count for transient errors
    pub fn get_retry_count(&self) -> Option<u32> {
        match self {
            AppError::TransientDecryptionError { retry_count, .. } => Some(*retry_count),
            _ => None,
        }
    }

    /// Get error code for frontend i18n translation
    pub fn error_code(&self) -> String {
        match self {
            AppError::AuthenticationError { .. } => "AUTHENTICATION_ERROR".to_string(),
            AppError::ReAuthenticationRequired { .. } => "REAUTH_REQUIRED".to_string(),
            AppError::CryptographyError { .. } => "CRYPTOGRAPHY_ERROR".to_string(),
            AppError::CryptoError { .. } => "CRYPTO_ERROR".to_string(),
            AppError::MacVerificationError { .. } => "MAC_VERIFICATION_ERROR".to_string(),
            AppError::KeyValidationError { .. } => "KEY_VALIDATION_ERROR".to_string(),
            AppError::TransientDecryptionError { .. } => "TRANSIENT_DECRYPTION_ERROR".to_string(),
            AppError::PermanentDecryptionError { .. } => "PERMANENT_DECRYPTION_ERROR".to_string(),
            AppError::CacheError { .. } => "CACHE_ERROR".to_string(),
            AppError::CircuitBreakerError { .. } => "CIRCUIT_BREAKER_ERROR".to_string(),
            AppError::DatabaseError { .. } => "DATABASE_ERROR".to_string(),
            AppError::NetworkError { status, .. } => match *status {
                0 => "NETWORK_CONNECTION_FAILED".to_string(),
                401 => "AUTHENTICATION_EXPIRED".to_string(),
                403 => "ACCESS_DENIED".to_string(),
                404 => "RESOURCE_NOT_FOUND".to_string(),
                429 => "RATE_LIMITED".to_string(),
                500..=599 => "SERVER_ERROR".to_string(),
                _ => "NETWORK_ERROR".to_string(),
            },
            AppError::StorageError { .. } => "STORAGE_ERROR".to_string(),
            AppError::ValidationError { .. } => "VALIDATION_ERROR".to_string(),
            AppError::ConfigurationError { .. } => "CONFIGURATION_ERROR".to_string(),
            AppError::BiometricError { .. } => "BIOMETRIC_ERROR".to_string(),
            AppError::SyncError { .. } => "SYNC_ERROR".to_string(),
            AppError::InternalError { .. } => "INTERNAL_ERROR".to_string(),
        }
    }

    /// Get error severity level
    pub fn severity(&self) -> ErrorSeverity {
        match self {
            AppError::AuthenticationError { .. } => ErrorSeverity::High,
            AppError::ReAuthenticationRequired { .. } => ErrorSeverity::Medium,
            AppError::CryptographyError { .. } => ErrorSeverity::Critical,
            AppError::CryptoError { .. } => ErrorSeverity::Critical,
            AppError::MacVerificationError { .. } => ErrorSeverity::High,
            AppError::KeyValidationError { .. } => ErrorSeverity::Critical,
            AppError::TransientDecryptionError { .. } => ErrorSeverity::Medium,
            AppError::PermanentDecryptionError { .. } => ErrorSeverity::High,
            AppError::CacheError { .. } => ErrorSeverity::Medium,
            AppError::CircuitBreakerError { .. } => ErrorSeverity::High,
            AppError::DatabaseError { .. } => ErrorSeverity::High,
            AppError::NetworkError { status, .. } => {
                if *status >= 500 {
                    ErrorSeverity::Medium
                } else if *status == 401 || *status == 403 {
                    ErrorSeverity::High
                } else {
                    ErrorSeverity::Low
                }
            }
            AppError::StorageError { .. } => ErrorSeverity::Medium,
            AppError::ValidationError { .. } => ErrorSeverity::Low,
            AppError::ConfigurationError { .. } => ErrorSeverity::Medium,
            AppError::BiometricError { .. } => ErrorSeverity::Low,
            AppError::SyncError { .. } => ErrorSeverity::Medium,
            AppError::InternalError { .. } => ErrorSeverity::Critical,
        }
    }

    /// Check if error should be reported to analytics/telemetry
    pub fn should_report(&self) -> bool {
        match self.severity() {
            ErrorSeverity::Critical | ErrorSeverity::High => true,
            ErrorSeverity::Medium => true,
            ErrorSeverity::Low => false,
        }
    }
}

/// Error severity levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ErrorSeverity {
    Low,
    Medium,
    High,
    Critical,
}

/// Error recovery utility
pub struct ErrorRecovery;

impl ErrorRecovery {
    /// Attempt to recover from an error with retries
    pub async fn retry_with_backoff<T, F, Fut>(operation: F, max_attempts: u32) -> AppResult<T>
    where
        F: Fn() -> Fut,
        Fut: std::future::Future<Output = AppResult<T>>,
    {
        let mut attempt = 0;
        let mut last_error = None;

        while attempt < max_attempts {
            match operation().await {
                Ok(result) => return Ok(result),
                Err(error) => {
                    if !error.is_retryable() {
                        return Err(error);
                    }

                    if let Some(delay) = error.retry_delay(attempt) {
                        tokio::time::sleep(std::time::Duration::from_millis(delay)).await;
                    }

                    last_error = Some(error);
                    attempt += 1;
                }
            }
        }

        Err(last_error.unwrap_or_else(|| AppError::InternalError {
            message: "Max retry attempts exceeded".to_string(),
        }))
    }

    /// Attempt operation with fallback
    pub async fn with_fallback<T, F1, F2, Fut1, Fut2>(primary: F1, fallback: F2) -> AppResult<T>
    where
        F1: Fn() -> Fut1,
        F2: Fn() -> Fut2,
        Fut1: std::future::Future<Output = AppResult<T>>,
        Fut2: std::future::Future<Output = AppResult<T>>,
    {
        match primary().await {
            Ok(result) => Ok(result),
            Err(primary_error) => {
                warn!(
                    error = %primary_error,
                    "Primary operation failed, attempting fallback"
                );

                match fallback().await {
                    Ok(result) => {
                        info!("Fallback operation succeeded");
                        Ok(result)
                    }
                    Err(fallback_error) => {
                        error!(
                            primary_error = %primary_error,
                            fallback_error = %fallback_error,
                            "Both primary and fallback operations failed"
                        );
                        Err(primary_error) // Return original error
                    }
                }
            }
        }
    }

    /// Circuit breaker pattern for external services
    pub fn create_circuit_breaker() -> CircuitBreaker {
        CircuitBreaker::new()
    }
}

/// Circuit breaker for handling external service failures
#[derive(Debug)]
pub struct CircuitBreaker {
    state: CircuitBreakerState,
    failure_count: u32,
    success_count: u32,
    last_failure_time: Option<std::time::Instant>,
    failure_threshold: u32,
    recovery_timeout: std::time::Duration,
    success_threshold: u32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum CircuitBreakerState {
    Closed,
    Open,
    HalfOpen,
}

impl CircuitBreaker {
    pub fn new() -> Self {
        Self {
            state: CircuitBreakerState::Closed,
            failure_count: 0,
            success_count: 0,
            last_failure_time: None,
            failure_threshold: 5,
            recovery_timeout: std::time::Duration::from_secs(60),
            success_threshold: 3,
        }
    }

    pub async fn call<T, F, Fut>(&mut self, operation: F) -> AppResult<T>
    where
        F: Fn() -> Fut,
        Fut: std::future::Future<Output = AppResult<T>>,
    {
        match self.state {
            CircuitBreakerState::Open => {
                if let Some(last_failure) = self.last_failure_time {
                    if last_failure.elapsed() >= self.recovery_timeout {
                        self.state = CircuitBreakerState::HalfOpen;
                        self.success_count = 0;
                    } else {
                        return Err(AppError::InternalError {
                            message: "Circuit breaker is open".to_string(),
                        });
                    }
                } else {
                    return Err(AppError::InternalError {
                        message: "Circuit breaker is open".to_string(),
                    });
                }
            }
            CircuitBreakerState::HalfOpen => {
                // Allow limited requests in half-open state
            }
            CircuitBreakerState::Closed => {
                // Normal operation
            }
        }

        match operation().await {
            Ok(result) => {
                self.on_success();
                Ok(result)
            }
            Err(error) => {
                self.on_failure();
                Err(error)
            }
        }
    }

    fn on_success(&mut self) {
        match self.state {
            CircuitBreakerState::HalfOpen => {
                self.success_count += 1;
                if self.success_count >= self.success_threshold {
                    self.state = CircuitBreakerState::Closed;
                    self.failure_count = 0;
                    self.success_count = 0;
                }
            }
            CircuitBreakerState::Closed => {
                self.failure_count = 0;
            }
            CircuitBreakerState::Open => {
                // Should not happen
            }
        }
    }

    fn on_failure(&mut self) {
        self.failure_count += 1;
        self.last_failure_time = Some(std::time::Instant::now());

        match self.state {
            CircuitBreakerState::Closed | CircuitBreakerState::HalfOpen => {
                if self.failure_count >= self.failure_threshold {
                    self.state = CircuitBreakerState::Open;
                }
            }
            CircuitBreakerState::Open => {
                // Already open
            }
        }
    }
}
