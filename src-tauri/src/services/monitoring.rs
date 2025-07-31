use crate::error::AppResult;
use crate::logging::{log_cache_health, log_failure_pattern};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Monitoring service for tracking system health and failure patterns
pub struct MonitoringService {
    metrics: Arc<RwLock<SystemMetrics>>,
    failure_patterns: Arc<RwLock<HashMap<String, FailurePattern>>>,
    health_checks: Arc<RwLock<HashMap<String, HealthCheck>>>,
}

/// System-wide metrics
#[derive(Debug, Clone)]
pub struct SystemMetrics {
    pub crypto_operations: CryptoMetrics,
    pub vault_operations: VaultMetrics,
    pub cache_metrics: CacheMetrics,
    pub circuit_breaker_metrics: CircuitBreakerMetrics,
    pub uptime: Duration,
    pub last_updated: Instant,
}

/// Crypto operation metrics
#[derive(Debug, Clone)]
pub struct CryptoMetrics {
    pub total_operations: u64,
    pub successful_operations: u64,
    pub failed_operations: u64,
    pub mac_verification_failures: u64,
    pub key_validation_failures: u64,
    pub average_operation_time_ms: f64,
    pub last_failure_time: Option<Instant>,
}

/// Vault operation metrics
#[derive(Debug, Clone)]
pub struct VaultMetrics {
    pub total_decryptions: u64,
    pub successful_decryptions: u64,
    pub failed_decryptions: u64,
    pub cascade_failures_prevented: u64,
    pub average_decryption_time_ms: f64,
    pub last_successful_decryption: Option<Instant>,
}

/// Cache metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheMetrics {
    pub hit_count: u64,
    pub miss_count: u64,
    pub eviction_count: u64,
    pub failure_count: u64,
    pub hit_rate: f64,
    pub miss_rate: f64,
}

/// Circuit breaker metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CircuitBreakerMetrics {
    pub total_services: u32,
    pub open_circuits: u32,
    pub half_open_circuits: u32,
    pub closed_circuits: u32,
    pub total_failures: u64,
    pub total_recoveries: u64,
}

/// Failure pattern tracking
#[derive(Debug, Clone)]
pub struct FailurePattern {
    pub user_id: String,
    pub failure_count: u32,
    pub first_failure: Instant,
    pub last_failure: Instant,
    pub failure_types: HashMap<String, u32>,
    pub recovery_attempts: u32,
}

/// Health check status
#[derive(Debug, Clone)]
pub struct HealthCheck {
    pub component: String,
    pub status: HealthStatus,
    pub last_check: Instant,
    pub failure_count: u32,
    pub details: String,
}

/// Health status enumeration
#[derive(Debug, Clone, PartialEq)]
pub enum HealthStatus {
    Healthy,
    Degraded,
    Unhealthy,
    Unknown,
}

impl MonitoringService {
    pub fn new() -> Self {
        Self {
            metrics: Arc::new(RwLock::new(SystemMetrics::default())),
            failure_patterns: Arc::new(RwLock::new(HashMap::new())),
            health_checks: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Record a crypto operation result
    pub async fn record_crypto_operation(
        &self,
        _operation: &str,
        success: bool,
        duration_ms: u64,
        error_type: Option<&str>,
    ) {
        let mut metrics = self.metrics.write().await;
        metrics.crypto_operations.total_operations += 1;

        if success {
            metrics.crypto_operations.successful_operations += 1;
        } else {
            metrics.crypto_operations.failed_operations += 1;
            metrics.crypto_operations.last_failure_time = Some(Instant::now());

            // Track specific error types
            if let Some(error) = error_type {
                match error {
                    "mac_verification" => metrics.crypto_operations.mac_verification_failures += 1,
                    "key_validation" => metrics.crypto_operations.key_validation_failures += 1,
                    _ => {}
                }
            }
        }

        // Update average operation time
        let total_ops = metrics.crypto_operations.total_operations as f64;
        let current_avg = metrics.crypto_operations.average_operation_time_ms;
        metrics.crypto_operations.average_operation_time_ms =
            (current_avg * (total_ops - 1.0) + duration_ms as f64) / total_ops;

        metrics.last_updated = Instant::now();
    }

    /// Record a vault operation result
    pub async fn record_vault_operation(
        &self,
        _operation: &str,
        success: bool,
        duration_ms: u64,
        cascade_prevented: bool,
    ) {
        let mut metrics = self.metrics.write().await;
        metrics.vault_operations.total_decryptions += 1;

        if success {
            metrics.vault_operations.successful_decryptions += 1;
            metrics.vault_operations.last_successful_decryption = Some(Instant::now());
        } else {
            metrics.vault_operations.failed_decryptions += 1;
        }

        if cascade_prevented {
            metrics.vault_operations.cascade_failures_prevented += 1;
        }

        // Update average decryption time
        let total_ops = metrics.vault_operations.total_decryptions as f64;
        let current_avg = metrics.vault_operations.average_decryption_time_ms;
        metrics.vault_operations.average_decryption_time_ms =
            (current_avg * (total_ops - 1.0) + duration_ms as f64) / total_ops;

        metrics.last_updated = Instant::now();
    }

    /// Record a failure pattern for a user
    pub async fn record_failure_pattern(
        &self,
        user_id: &str,
        error_type: &str,
        _context: &str,
    ) -> AppResult<bool> {
        let mut patterns = self.failure_patterns.write().await;
        let pattern = patterns
            .entry(user_id.to_string())
            .or_insert_with(|| FailurePattern {
                user_id: user_id.to_string(),
                failure_count: 0,
                first_failure: Instant::now(),
                last_failure: Instant::now(),
                failure_types: HashMap::new(),
                recovery_attempts: 0,
            });

        pattern.failure_count += 1;
        pattern.last_failure = Instant::now();
        *pattern
            .failure_types
            .entry(error_type.to_string())
            .or_insert(0) += 1;

        // Check if this indicates a concerning pattern
        let is_concerning = pattern.failure_count >= 5
            && pattern.last_failure.duration_since(pattern.first_failure)
                < Duration::from_secs(5 * 60);

        if is_concerning {
            log_failure_pattern(user_id, pattern.failure_count, 5, "5 minutes", error_type);
        }

        Ok(is_concerning)
    }

    /// Update cache metrics
    pub async fn update_cache_metrics(&self) -> AppResult<()> {
        // This would integrate with the actual cache implementation
        // For now, we'll simulate some metrics
        let mut metrics = self.metrics.write().await;

        // In a real implementation, these would come from the cache
        metrics.cache_metrics.hit_count += 1;
        metrics.cache_metrics.hit_rate = metrics.cache_metrics.hit_count as f64
            / (metrics.cache_metrics.hit_count + metrics.cache_metrics.miss_count) as f64;

        metrics.cache_metrics.miss_rate = 1.0 - metrics.cache_metrics.hit_rate;

        log_cache_health(
            "crypto_cache",
            metrics.cache_metrics.hit_rate,
            metrics.cache_metrics.miss_rate,
            metrics
                .cache_metrics
                .eviction_count
                .try_into()
                .unwrap_or(u32::MAX),
            metrics
                .cache_metrics
                .failure_count
                .try_into()
                .unwrap_or(u32::MAX),
        );

        Ok(())
    }

    /// Perform health checks on system components
    pub async fn perform_health_checks(&self) -> AppResult<HashMap<String, HealthStatus>> {
        let mut health_checks = self.health_checks.write().await;
        let mut results = HashMap::new();

        // Check crypto cache health
        let cache_status = self.check_crypto_cache_health().await?;
        health_checks.insert(
            "crypto_cache".to_string(),
            HealthCheck {
                component: "crypto_cache".to_string(),
                status: cache_status.clone(),
                last_check: Instant::now(),
                failure_count: 0,
                details: "Crypto cache health check".to_string(),
            },
        );
        results.insert("crypto_cache".to_string(), cache_status);

        // Check circuit breaker health
        let circuit_status = self.check_circuit_breaker_health().await?;
        health_checks.insert(
            "circuit_breakers".to_string(),
            HealthCheck {
                component: "circuit_breakers".to_string(),
                status: circuit_status.clone(),
                last_check: Instant::now(),
                failure_count: 0,
                details: "Circuit breaker health check".to_string(),
            },
        );
        results.insert("circuit_breakers".to_string(), circuit_status);

        Ok(results)
    }

    /// Check crypto cache health
    async fn check_crypto_cache_health(&self) -> AppResult<HealthStatus> {
        let metrics = self.metrics.read().await;

        // Check hit rate
        if metrics.cache_metrics.hit_rate < 0.3 {
            return Ok(HealthStatus::Degraded);
        }

        // Check failure rate
        let total_operations = metrics.cache_metrics.hit_count + metrics.cache_metrics.miss_count;
        if total_operations > 0 {
            let failure_rate = metrics.cache_metrics.failure_count as f64 / total_operations as f64;
            if failure_rate > 0.1 {
                return Ok(HealthStatus::Unhealthy);
            }
        }

        Ok(HealthStatus::Healthy)
    }

    /// Check circuit breaker health
    async fn check_circuit_breaker_health(&self) -> AppResult<HealthStatus> {
        let metrics = self.metrics.read().await;

        // Check if too many circuits are open
        let open_ratio = if metrics.circuit_breaker_metrics.total_services > 0 {
            metrics.circuit_breaker_metrics.open_circuits as f64
                / metrics.circuit_breaker_metrics.total_services as f64
        } else {
            0.0
        };

        if open_ratio > 0.5 {
            Ok(HealthStatus::Unhealthy)
        } else if open_ratio > 0.2 {
            Ok(HealthStatus::Degraded)
        } else {
            Ok(HealthStatus::Healthy)
        }
    }

    /// Get current system metrics
    pub async fn get_metrics(&self) -> SystemMetrics {
        self.metrics.read().await.clone()
    }

    /// Get failure patterns for analysis
    pub async fn get_failure_patterns(&self) -> HashMap<String, FailurePattern> {
        self.failure_patterns.read().await.clone()
    }
}

impl Default for SystemMetrics {
    fn default() -> Self {
        Self {
            crypto_operations: CryptoMetrics::default(),
            vault_operations: VaultMetrics::default(),
            cache_metrics: CacheMetrics::default(),
            circuit_breaker_metrics: CircuitBreakerMetrics::default(),
            uptime: Duration::from_secs(0),
            last_updated: Instant::now(),
        }
    }
}

impl Default for CryptoMetrics {
    fn default() -> Self {
        Self {
            total_operations: 0,
            successful_operations: 0,
            failed_operations: 0,
            mac_verification_failures: 0,
            key_validation_failures: 0,
            average_operation_time_ms: 0.0,
            last_failure_time: None,
        }
    }
}

impl Default for VaultMetrics {
    fn default() -> Self {
        Self {
            total_decryptions: 0,
            successful_decryptions: 0,
            failed_decryptions: 0,
            cascade_failures_prevented: 0,
            average_decryption_time_ms: 0.0,
            last_successful_decryption: None,
        }
    }
}

impl Default for CacheMetrics {
    fn default() -> Self {
        Self {
            hit_count: 0,
            miss_count: 0,
            eviction_count: 0,
            failure_count: 0,
            hit_rate: 0.0,
            miss_rate: 0.0,
        }
    }
}

impl Default for CircuitBreakerMetrics {
    fn default() -> Self {
        Self {
            total_services: 0,
            open_circuits: 0,
            half_open_circuits: 0,
            closed_circuits: 0,
            total_failures: 0,
            total_recoveries: 0,
        }
    }
}

impl Default for MonitoringService {
    fn default() -> Self {
        Self::new()
    }
}
