use crate::crypto::{CryptoError, CryptoResult, MasterKey, UserKey};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant};
use tokio::time;
use tracing::{debug, warn};

/// Cache entry with TTL
#[derive(Debug, Clone)]
struct CacheEntry<T> {
    value: T,
    created_at: Instant,
    ttl: Duration,
}

impl<T> CacheEntry<T> {
    fn new(value: T, ttl: Duration) -> Self {
        Self {
            value,
            created_at: Instant::now(),
            ttl,
        }
    }

    fn is_expired(&self) -> bool {
        self.created_at.elapsed() > self.ttl
    }
}

/// Failure counter for tracking decryption failures per user
#[derive(Debug, Clone)]
pub struct FailureCounter {
    pub count: u32,
    pub last_failure: Instant,
    pub threshold: u32,
    pub reset_duration: Duration,
}

impl FailureCounter {
    pub fn new(threshold: u32, reset_duration: Duration) -> Self {
        Self {
            count: 0,
            last_failure: Instant::now(),
            threshold,
            reset_duration,
        }
    }

    pub fn increment(&mut self) {
        self.count += 1;
        self.last_failure = Instant::now();
    }

    pub fn should_reset(&self) -> bool {
        self.last_failure.elapsed() > self.reset_duration
    }

    pub fn reset(&mut self) {
        self.count = 0;
        self.last_failure = Instant::now();
    }

    pub fn is_threshold_exceeded(&self) -> bool {
        self.count >= self.threshold
    }
}

/// Circuit breaker states
#[derive(Debug, Clone, PartialEq)]
pub enum CircuitBreakerState {
    Closed,   // Normal operation
    Open,     // Failing fast
    HalfOpen, // Testing if service recovered
}

/// Circuit breaker for preventing cascade failures
#[derive(Debug, Clone)]
pub struct CircuitBreaker {
    pub state: CircuitBreakerState,
    pub failure_count: u32,
    pub failure_threshold: u32,
    pub recovery_timeout: Duration,
    pub last_failure_time: Instant,
    pub half_open_max_calls: u32,
    pub half_open_calls: u32,
}

impl CircuitBreaker {
    pub fn new(failure_threshold: u32, recovery_timeout: Duration) -> Self {
        Self {
            state: CircuitBreakerState::Closed,
            failure_count: 0,
            failure_threshold,
            recovery_timeout,
            last_failure_time: Instant::now(),
            half_open_max_calls: 3,
            half_open_calls: 0,
        }
    }

    pub fn can_execute(&mut self) -> bool {
        match self.state {
            CircuitBreakerState::Closed => true,
            CircuitBreakerState::Open => {
                if self.last_failure_time.elapsed() > self.recovery_timeout {
                    self.state = CircuitBreakerState::HalfOpen;
                    self.half_open_calls = 0;
                    true
                } else {
                    false
                }
            }
            CircuitBreakerState::HalfOpen => self.half_open_calls < self.half_open_max_calls,
        }
    }

    pub fn record_success(&mut self) {
        match self.state {
            CircuitBreakerState::HalfOpen => {
                self.state = CircuitBreakerState::Closed;
                self.failure_count = 0;
                self.half_open_calls = 0;
            }
            CircuitBreakerState::Closed => {
                self.failure_count = 0;
            }
            _ => {}
        }
    }

    pub fn record_failure(&mut self) {
        self.failure_count += 1;
        self.last_failure_time = Instant::now();

        match self.state {
            CircuitBreakerState::Closed => {
                if self.failure_count >= self.failure_threshold {
                    self.state = CircuitBreakerState::Open;
                }
            }
            CircuitBreakerState::HalfOpen => {
                self.state = CircuitBreakerState::Open;
                self.half_open_calls = 0;
            }
            _ => {}
        }
    }
}

/// Thread-safe crypto cache for performance optimization with failure tracking
#[derive(Debug)]
pub struct CryptoCache {
    master_keys: Arc<RwLock<HashMap<String, CacheEntry<MasterKey>>>>,
    user_keys: Arc<RwLock<HashMap<String, CacheEntry<UserKey>>>>,
    derived_keys: Arc<RwLock<HashMap<String, CacheEntry<Vec<u8>>>>>,
    failure_counters: Arc<RwLock<HashMap<String, FailureCounter>>>,
    circuit_breakers: Arc<RwLock<HashMap<String, CircuitBreaker>>>,
    settings: CacheSettings,
}

#[derive(Debug, Clone)]
pub struct CacheSettings {
    pub master_key_ttl: Duration,
    pub user_key_ttl: Duration,
    pub derived_key_ttl: Duration,
    pub max_entries: usize,
    pub cleanup_interval: Duration,
    pub failure_threshold: u32,
    pub failure_reset_duration: Duration,
    pub circuit_breaker_threshold: u32,
    pub circuit_breaker_recovery_timeout: Duration,
}

impl Default for CacheSettings {
    fn default() -> Self {
        Self {
            master_key_ttl: Duration::from_secs(900),  // 15 minutes
            user_key_ttl: Duration::from_secs(1800),   // 30 minutes
            derived_key_ttl: Duration::from_secs(600), // 10 minutes
            max_entries: 1000,
            cleanup_interval: Duration::from_secs(60), // 1 minute
            failure_threshold: 3, // Allow 3 failures before marking as problematic
            failure_reset_duration: Duration::from_secs(300), // Reset failures after 5 minutes
            circuit_breaker_threshold: 5, // Open circuit after 5 consecutive failures
            circuit_breaker_recovery_timeout: Duration::from_secs(60), // Try recovery after 1 minute
        }
    }
}

impl CryptoCache {
    pub fn new(settings: CacheSettings) -> Self {
        let cache = Self {
            master_keys: Arc::new(RwLock::new(HashMap::new())),
            user_keys: Arc::new(RwLock::new(HashMap::new())),
            derived_keys: Arc::new(RwLock::new(HashMap::new())),
            failure_counters: Arc::new(RwLock::new(HashMap::new())),
            circuit_breakers: Arc::new(RwLock::new(HashMap::new())),
            settings,
        };

        // Start cleanup task
        cache.start_cleanup_task();
        cache
    }

    pub fn with_default_settings() -> Self {
        Self::new(CacheSettings::default())
    }

    /// Store master key with TTL
    pub fn store_master_key(&self, key: String, master_key: MasterKey) -> CryptoResult<()> {
        let mut cache = self
            .master_keys
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock master key cache: {}", e)))?;

        cache.insert(
            key,
            CacheEntry::new(master_key, self.settings.master_key_ttl),
        );
        self.cleanup_if_needed(&mut cache);
        Ok(())
    }

    /// Retrieve master key if not expired
    pub fn get_master_key(&self, key: &str) -> CryptoResult<Option<MasterKey>> {
        let cache = self
            .master_keys
            .read()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock master key cache: {}", e)))?;

        if let Some(entry) = cache.get(key) {
            if !entry.is_expired() {
                return Ok(Some(entry.value.clone()));
            }
        }
        Ok(None)
    }

    /// Store user key with TTL
    pub fn store_user_key(&self, key: String, user_key: UserKey) -> CryptoResult<()> {
        let mut cache = self
            .user_keys
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock user key cache: {}", e)))?;

        cache.insert(key, CacheEntry::new(user_key, self.settings.user_key_ttl));
        self.cleanup_if_needed(&mut cache);
        Ok(())
    }

    /// Retrieve user key if not expired
    pub fn get_user_key(&self, key: &str) -> CryptoResult<Option<UserKey>> {
        let cache = self
            .user_keys
            .read()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock user key cache: {}", e)))?;

        if let Some(entry) = cache.get(key) {
            if !entry.is_expired() {
                return Ok(Some(entry.value.clone()));
            }
        }
        Ok(None)
    }

    /// Remove a user key from cache (useful when key becomes stale)
    pub fn remove_user_key(&self, key: &str) -> CryptoResult<()> {
        let mut cache = self
            .user_keys
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock user key cache: {}", e)))?;

        cache.remove(key);
        debug!(
            "[crypto_cache] Removed user key from cache for key: {}",
            key
        );
        Ok(())
    }

    /// Clear all cached data for a user (on logout/authentication change)
    pub fn clear_user_data(&self, user_id: &str) -> CryptoResult<()> {
        use tracing::{debug, warn};

        debug!(
            user_id = user_id,
            "[crypto_cache] Clearing all cached data for user"
        );

        // Clear user key
        if let Err(e) = self.remove_user_key(user_id) {
            warn!(
                user_id = user_id,
                error = %e,
                "[crypto_cache] Failed to remove user key during cache clear"
            );
        }

        // Clear master key
        if let Err(e) = self.remove_master_key(user_id) {
            warn!(
                user_id = user_id,
                error = %e,
                "[crypto_cache] Failed to remove master key during cache clear"
            );
        }

        // Clear derived keys (remove all keys that start with user_id)
        if let Ok(mut derived_cache) = self.derived_keys.write() {
            let keys_to_remove: Vec<String> = derived_cache
                .keys()
                .filter(|key| key.starts_with(user_id))
                .cloned()
                .collect();

            for key in keys_to_remove {
                derived_cache.remove(&key);
            }
        }

        // Clear failure counters
        if let Ok(mut counters) = self.failure_counters.write() {
            counters.remove(user_id);
        }

        // Clear circuit breakers
        if let Ok(mut breakers) = self.circuit_breakers.write() {
            breakers.remove(user_id);
        }

        debug!(
            user_id = user_id,
            "[crypto_cache] Successfully cleared all cached data for user"
        );

        Ok(())
    }

    /// Remove a master key from cache
    pub fn remove_master_key(&self, key: &str) -> CryptoResult<()> {
        let mut cache = self
            .master_keys
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock master key cache: {}", e)))?;

        cache.remove(key);
        debug!(
            "[crypto_cache] Removed master key from cache for key: {}",
            key
        );
        Ok(())
    }

    /// Store derived key with TTL
    pub fn store_derived_key(&self, key: String, derived_key: Vec<u8>) -> CryptoResult<()> {
        let mut cache = self.derived_keys.write().map_err(|e| {
            CryptoError::Storage(format!("Failed to lock derived key cache: {}", e))
        })?;

        cache.insert(
            key,
            CacheEntry::new(derived_key, self.settings.derived_key_ttl),
        );
        self.cleanup_if_needed(&mut cache);
        Ok(())
    }

    /// Retrieve derived key if not expired
    pub fn get_derived_key(&self, key: &str) -> CryptoResult<Option<Vec<u8>>> {
        let cache = self.derived_keys.read().map_err(|e| {
            CryptoError::Storage(format!("Failed to lock derived key cache: {}", e))
        })?;

        if let Some(entry) = cache.get(key) {
            if !entry.is_expired() {
                return Ok(Some(entry.value.clone()));
            }
        }
        Ok(None)
    }

    /// Clear all caches
    pub fn clear_all(&self) -> CryptoResult<()> {
        let mut master_keys = self
            .master_keys
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock master key cache: {}", e)))?;
        let mut user_keys = self
            .user_keys
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock user key cache: {}", e)))?;
        let mut derived_keys = self.derived_keys.write().map_err(|e| {
            CryptoError::Storage(format!("Failed to lock derived key cache: {}", e))
        })?;

        master_keys.clear();
        user_keys.clear();
        derived_keys.clear();

        Ok(())
    }

    /// Clear expired entries
    pub fn cleanup_expired(&self) -> CryptoResult<()> {
        self.cleanup_cache(&self.master_keys)?;
        self.cleanup_cache(&self.user_keys)?;
        self.cleanup_cache(&self.derived_keys)?;
        Ok(())
    }

    /// Get cache statistics
    pub fn get_stats(&self) -> CryptoResult<CacheStats> {
        let master_keys = self
            .master_keys
            .read()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock master key cache: {}", e)))?;
        let user_keys = self
            .user_keys
            .read()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock user key cache: {}", e)))?;
        let derived_keys = self.derived_keys.read().map_err(|e| {
            CryptoError::Storage(format!("Failed to lock derived key cache: {}", e))
        })?;

        Ok(CacheStats {
            master_key_count: master_keys.len(),
            user_key_count: user_keys.len(),
            derived_key_count: derived_keys.len(),
            total_entries: master_keys.len() + user_keys.len() + derived_keys.len(),
            max_entries: self.settings.max_entries,
        })
    }

    /// Start background cleanup task
    fn start_cleanup_task(&self) {
        let master_keys = Arc::clone(&self.master_keys);
        let user_keys = Arc::clone(&self.user_keys);
        let derived_keys = Arc::clone(&self.derived_keys);
        let interval = self.settings.cleanup_interval;

        tokio::spawn(async move {
            let mut interval = time::interval(interval);
            loop {
                interval.tick().await;
                let _ = Self::cleanup_cache_static(&master_keys);
                let _ = Self::cleanup_cache_static(&user_keys);
                let _ = Self::cleanup_cache_static(&derived_keys);
            }
        });
    }

    /// Generic cleanup function for any cache type
    fn cleanup_cache<T>(
        &self,
        cache: &Arc<RwLock<HashMap<String, CacheEntry<T>>>>,
    ) -> CryptoResult<()> {
        let mut cache = cache
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock cache: {}", e)))?;

        cache.retain(|_, entry| !entry.is_expired());
        Ok(())
    }

    /// Static cleanup function for background task
    fn cleanup_cache_static<T: Send + Sync>(
        cache: &Arc<RwLock<HashMap<String, CacheEntry<T>>>>,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut cache = cache.write().map_err(|e| {
            Box::new(std::io::Error::new(
                std::io::ErrorKind::Other,
                format!("Failed to acquire write lock: {}", e),
            )) as Box<dyn std::error::Error + Send + Sync>
        })?;
        cache.retain(|_, entry| !entry.is_expired());
        Ok(())
    }

    /// Check if cache needs cleanup based on size
    fn cleanup_if_needed<T>(&self, cache: &mut HashMap<String, CacheEntry<T>>) {
        if cache.len() > self.settings.max_entries {
            // Remove oldest entries
            let mut entries: Vec<_> = cache
                .iter()
                .map(|(k, v)| (k.clone(), v.created_at))
                .collect();
            entries.sort_by(|a, b| a.1.cmp(&b.1));

            let remove_count = cache.len() - self.settings.max_entries + 100; // Remove extra to avoid frequent cleanup
            for (key, _) in entries.iter().take(remove_count) {
                cache.remove(key);
            }
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheStats {
    pub master_key_count: usize,
    pub user_key_count: usize,
    pub derived_key_count: usize,
    pub total_entries: usize,
    pub max_entries: usize,
}

impl CryptoCache {
    /// Record a decryption failure for a user
    pub fn record_failure(&self, user_id: &str) -> CryptoResult<bool> {
        use tracing::warn;

        let mut counters = self
            .failure_counters
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock failure counters: {}", e)))?;

        let counter = counters.entry(user_id.to_string()).or_insert_with(|| {
            FailureCounter::new(
                self.settings.failure_threshold,
                self.settings.failure_reset_duration,
            )
        });

        if counter.should_reset() {
            counter.reset();
        }

        counter.increment();
        let threshold_exceeded = counter.is_threshold_exceeded();

        if threshold_exceeded {
            warn!(
                user_id = user_id,
                failure_count = counter.count,
                threshold = counter.threshold,
                "[crypto_cache] Failure threshold exceeded for user"
            );
        }

        Ok(threshold_exceeded)
    }

    /// Check if circuit breaker allows execution for a service
    pub fn can_execute(&self, service: &str) -> CryptoResult<bool> {
        let mut breakers = self
            .circuit_breakers
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock circuit breakers: {}", e)))?;

        let breaker = breakers.entry(service.to_string()).or_insert_with(|| {
            CircuitBreaker::new(
                self.settings.circuit_breaker_threshold,
                self.settings.circuit_breaker_recovery_timeout,
            )
        });

        Ok(breaker.can_execute())
    }

    /// Record a successful operation for circuit breaker
    pub fn record_success(&self, service: &str) -> CryptoResult<()> {
        let mut breakers = self
            .circuit_breakers
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock circuit breakers: {}", e)))?;

        if let Some(breaker) = breakers.get_mut(service) {
            breaker.record_success();
        }

        Ok(())
    }

    /// Record a failure for circuit breaker
    pub fn record_circuit_failure(&self, service: &str) -> CryptoResult<bool> {
        use tracing::warn;

        let mut breakers = self
            .circuit_breakers
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock circuit breakers: {}", e)))?;

        let breaker = breakers.entry(service.to_string()).or_insert_with(|| {
            CircuitBreaker::new(
                self.settings.circuit_breaker_threshold,
                self.settings.circuit_breaker_recovery_timeout,
            )
        });

        breaker.record_failure();
        let is_open = breaker.state == CircuitBreakerState::Open;

        if is_open {
            warn!(
                service = service,
                failure_count = breaker.failure_count,
                "[crypto_cache] Circuit breaker opened for service"
            );
        }

        Ok(is_open)
    }

    /// Check if user key should be invalidated based on failure patterns
    pub fn should_invalidate_user_key(&self, user_id: &str) -> CryptoResult<bool> {
        let counters = self
            .failure_counters
            .read()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock failure counters: {}", e)))?;

        if let Some(counter) = counters.get(user_id) {
            // Only invalidate if we have consistent failures over time
            Ok(counter.is_threshold_exceeded() && !counter.should_reset())
        } else {
            Ok(false)
        }
    }

    /// Reset failure counter for a user
    pub fn reset_failures(&self, user_id: &str) -> CryptoResult<()> {
        let mut counters = self
            .failure_counters
            .write()
            .map_err(|e| CryptoError::Storage(format!("Failed to lock failure counters: {}", e)))?;

        if let Some(counter) = counters.get_mut(user_id) {
            counter.reset();
        }

        Ok(())
    }
}

lazy_static::lazy_static! {
    /// Global cache instance
    pub static ref CRYPTO_CACHE: CryptoCache = CryptoCache::with_default_settings();
}

/// Cache key generator utilities
pub struct CacheKeyGenerator;

impl CacheKeyGenerator {
    /// Generate cache key for master key
    pub fn master_key(email: &str, password_hash: &str) -> String {
        format!("master_key:{}:{}", email, password_hash)
    }

    /// Generate cache key for user key
    pub fn user_key(user_id: &str, master_key_hash: &str) -> String {
        format!("user_key:{}:{}", user_id, master_key_hash)
    }

    /// Generate cache key for derived key
    pub fn derived_key(purpose: &str, salt: &str, iterations: u32) -> String {
        format!("derived_key:{}:{}:{}", purpose, salt, iterations)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn test_cache_expiration() {
        let settings = CacheSettings {
            master_key_ttl: Duration::from_millis(100),
            ..Default::default()
        };
        let cache = CryptoCache::new(settings);

        let key = "test_key".to_string();
        let master_key = MasterKey::new(vec![1, 2, 3, 4]);

        // Store key
        cache
            .store_master_key(key.clone(), master_key.clone())
            .unwrap();

        // Should be available immediately
        assert!(cache.get_master_key(&key).unwrap().is_some());

        // Wait for expiration
        tokio::time::sleep(Duration::from_millis(150)).await;

        // Should be expired
        assert!(cache.get_master_key(&key).unwrap().is_none());
    }

    #[test]
    fn test_cache_key_generation() {
        let master_key = CacheKeyGenerator::master_key("test@example.com", "hash123");
        assert_eq!(master_key, "master_key:test@example.com:hash123");

        let user_key = CacheKeyGenerator::user_key("user123", "master_hash");
        assert_eq!(user_key, "user_key:user123:master_hash");

        let derived_key = CacheKeyGenerator::derived_key("encryption", "salt123", 600000);
        assert_eq!(derived_key, "derived_key:encryption:salt123:600000");
    }
}
