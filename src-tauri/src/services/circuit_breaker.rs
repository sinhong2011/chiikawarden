use crate::crypto::cache::{CircuitBreakerState, CRYPTO_CACHE};
use crate::error::{AppError, AppResult};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Circuit breaker service for managing failure thresholds and recovery
pub struct CircuitBreakerService {
    service_configs: Arc<RwLock<HashMap<String, CircuitBreakerConfig>>>,
}

/// Configuration for circuit breaker behavior
#[derive(Debug, Clone)]
pub struct CircuitBreakerConfig {
    pub failure_threshold: u32,
    pub recovery_timeout: Duration,
    pub half_open_max_calls: u32,
    pub enabled: bool,
}

impl Default for CircuitBreakerConfig {
    fn default() -> Self {
        Self {
            failure_threshold: 5,
            recovery_timeout: Duration::from_secs(60),
            half_open_max_calls: 3,
            enabled: true,
        }
    }
}

impl CircuitBreakerService {
    pub fn new() -> Self {
        Self {
            service_configs: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Register a service with circuit breaker protection
    pub async fn register_service(&self, service_name: String, config: CircuitBreakerConfig) {
        let mut configs = self.service_configs.write().await;
        configs.insert(service_name.clone(), config);

        info!(
            service = service_name,
            "[circuit_breaker] Registered service with circuit breaker protection"
        );
    }

    /// Check if a service can execute (circuit breaker is closed or half-open)
    pub async fn can_execute(&self, service_name: &str) -> AppResult<bool> {
        let configs = self.service_configs.read().await;

        if let Some(config) = configs.get(service_name) {
            if !config.enabled {
                return Ok(true); // Circuit breaker disabled
            }
        }

        // Check with crypto cache circuit breaker
        CRYPTO_CACHE.can_execute(service_name).map_err(|e| {
            AppError::circuit_breaker_error(
                service_name.to_string(),
                format!("Failed to check circuit breaker state: {}", e),
                0,
            )
        })
    }

    /// Record a successful operation
    pub async fn record_success(&self, service_name: &str) -> AppResult<()> {
        CRYPTO_CACHE.record_success(service_name).map_err(|e| {
            AppError::circuit_breaker_error(
                service_name.to_string(),
                format!("Failed to record success: {}", e),
                0,
            )
        })?;

        debug!(
            service = service_name,
            "[circuit_breaker] Recorded successful operation"
        );

        Ok(())
    }

    /// Record a failure and check if circuit breaker should open
    pub async fn record_failure(&self, service_name: &str, error: &AppError) -> AppResult<bool> {
        let is_open = CRYPTO_CACHE
            .record_circuit_failure(service_name)
            .map_err(|e| {
                AppError::circuit_breaker_error(
                    service_name.to_string(),
                    format!("Failed to record failure: {}", e),
                    0,
                )
            })?;

        if is_open {
            warn!(
                service = service_name,
                error = %error,
                "[circuit_breaker] Circuit breaker opened due to failure"
            );
        } else {
            debug!(
                service = service_name,
                error = %error,
                "[circuit_breaker] Recorded failure, circuit breaker still closed"
            );
        }

        Ok(is_open)
    }

    /// Get circuit breaker statistics for monitoring
    pub async fn get_stats(&self, service_name: &str) -> AppResult<CircuitBreakerStats> {
        // This would need to be implemented in the crypto cache
        // For now, return basic stats
        Ok(CircuitBreakerStats {
            service_name: service_name.to_string(),
            state: CircuitBreakerState::Closed, // Default
            failure_count: 0,
            success_count: 0,
            last_failure_time: None,
            recovery_time: None,
        })
    }

    /// Force open a circuit breaker (for testing or emergency)
    pub async fn force_open(&self, service_name: &str, reason: &str) -> AppResult<()> {
        warn!(
            service = service_name,
            reason = reason,
            "[circuit_breaker] Manually opening circuit breaker"
        );

        // This would need to be implemented in the crypto cache
        Ok(())
    }

    /// Force close a circuit breaker (for recovery)
    pub async fn force_close(&self, service_name: &str, reason: &str) -> AppResult<()> {
        info!(
            service = service_name,
            reason = reason,
            "[circuit_breaker] Manually closing circuit breaker"
        );

        // This would need to be implemented in the crypto cache
        Ok(())
    }

    /// Get all registered services and their states
    pub async fn get_all_services(&self) -> Vec<String> {
        let configs = self.service_configs.read().await;
        configs.keys().cloned().collect()
    }

    /// Update configuration for a service
    pub async fn update_config(
        &self,
        service_name: String,
        config: CircuitBreakerConfig,
    ) -> AppResult<()> {
        let mut configs = self.service_configs.write().await;
        configs.insert(service_name.clone(), config);

        info!(
            service = service_name,
            "[circuit_breaker] Updated service configuration"
        );

        Ok(())
    }

    /// Check if a service should use circuit breaker based on error type
    pub fn should_use_circuit_breaker(&self, error: &AppError) -> bool {
        // Use circuit breaker for errors that indicate system-level issues
        match error {
            AppError::KeyValidationError { .. } => true,
            AppError::PermanentDecryptionError { .. } => true,
            AppError::DatabaseError { .. } => true,
            AppError::NetworkError { status, .. } => *status >= 500,
            _ => false,
        }
    }

    /// Get recommended action based on circuit breaker state
    pub async fn get_recommended_action(
        &self,
        service_name: &str,
    ) -> AppResult<CircuitBreakerAction> {
        let can_execute = self.can_execute(service_name).await?;

        if can_execute {
            Ok(CircuitBreakerAction::Proceed)
        } else {
            Ok(CircuitBreakerAction::Fallback {
                reason: "Circuit breaker is open".to_string(),
                retry_after: Duration::from_secs(60),
            })
        }
    }
}

/// Circuit breaker statistics for monitoring
#[derive(Debug, Clone)]
pub struct CircuitBreakerStats {
    pub service_name: String,
    pub state: CircuitBreakerState,
    pub failure_count: u32,
    pub success_count: u32,
    pub last_failure_time: Option<std::time::Instant>,
    pub recovery_time: Option<std::time::Instant>,
}

/// Recommended action based on circuit breaker state
#[derive(Debug, Clone)]
pub enum CircuitBreakerAction {
    Proceed,
    Fallback {
        reason: String,
        retry_after: Duration,
    },
}

impl Default for CircuitBreakerService {
    fn default() -> Self {
        Self::new()
    }
}
