use crate::crypto::{cache::CRYPTO_CACHE, UserKey};
use crate::error::AppResult;
use crate::models::CipherView;
use chrono::{DateTime, Duration, Utc};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::warn;
use zeroize::Zeroize;

/// Cached cipher with metadata
#[derive(Clone)]
pub struct CachedCipher {
    pub data: CipherView,
    pub cached_at: DateTime<Utc>,
    pub access_count: u32,
}

/// Memory cache for decrypted cipher data
pub struct MemoryCache {
    ciphers: Arc<RwLock<HashMap<String, CachedCipher>>>,
    max_size: usize,
    ttl_minutes: i64,
}

impl MemoryCache {
    /// Create a new memory cache
    pub fn new(max_size: usize, ttl_minutes: i64) -> Self {
        Self {
            ciphers: Arc::new(RwLock::new(HashMap::new())),
            max_size,
            ttl_minutes,
        }
    }

    /// Get a cipher from cache
    pub async fn get_cipher(&self, cipher_id: &str) -> Option<CipherView> {
        let mut cache = self.ciphers.write().await;

        if let Some(cached) = cache.get_mut(cipher_id) {
            // Check if expired
            let now = Utc::now();
            if now.signed_duration_since(cached.cached_at) > Duration::minutes(self.ttl_minutes) {
                cache.remove(cipher_id);
                return None;
            }

            // Update access statistics
            cached.access_count += 1;
            Some(cached.data.clone())
        } else {
            None
        }
    }

    /// Cache a cipher
    pub async fn cache_cipher(&self, cipher: CipherView) {
        let mut cache = self.ciphers.write().await;

        // Evict if cache is full
        if cache.len() >= self.max_size {
            self.evict_lru(&mut cache).await;
        }

        let cached_cipher = CachedCipher {
            data: cipher.clone(),
            cached_at: Utc::now(),
            access_count: 1,
        };

        cache.insert(cipher.id.clone(), cached_cipher);
    }

    /// Remove a cipher from cache
    pub async fn remove_cipher(&self, cipher_id: &str) {
        let mut cache = self.ciphers.write().await;
        cache.remove(cipher_id);
    }

    /// Clear all cached data
    pub async fn clear_cache(&self) {
        let mut cache = self.ciphers.write().await;

        // Securely clear sensitive data
        for (_, cached_cipher) in cache.iter_mut() {
            if let Some(ref mut login) = cached_cipher.data.login {
                if let Some(ref mut password) = login.password {
                    password.zeroize();
                }
            }
        }

        cache.clear();
    }

    /// Get cache statistics
    pub async fn get_stats(&self) -> CacheStats {
        let cache = self.ciphers.read().await;
        CacheStats {
            size: cache.len(),
            max_size: self.max_size,
            ttl_minutes: self.ttl_minutes,
        }
    }

    /// Evict least recently used item
    async fn evict_lru(&self, cache: &mut HashMap<String, CachedCipher>) {
        // Find least recently used item based on access_count and cached_at
        if let Some((key_to_remove, _)) = cache
            .iter()
            .min_by_key(|(_, cached)| (cached.access_count, cached.cached_at))
        {
            let key = key_to_remove.clone();

            // Securely clear sensitive data before removal
            if let Some(mut cached_cipher) = cache.remove(&key) {
                if let Some(ref mut login) = cached_cipher.data.login {
                    if let Some(ref mut password) = login.password {
                        password.zeroize();
                    }
                }
            }
        }
    }

    /// Clean expired entries
    pub async fn cleanup_expired(&self) {
        let mut cache = self.ciphers.write().await;
        let now = Utc::now();
        let ttl_duration = Duration::minutes(self.ttl_minutes);

        let expired_keys: Vec<String> = cache
            .iter()
            .filter(|(_, cached)| now.signed_duration_since(cached.cached_at) > ttl_duration)
            .map(|(key, _)| key.clone())
            .collect();

        for key in expired_keys {
            if let Some(mut cached_cipher) = cache.remove(&key) {
                // Securely clear sensitive data
                if let Some(ref mut login) = cached_cipher.data.login {
                    if let Some(ref mut password) = login.password {
                        password.zeroize();
                    }
                }
            }
        }
    }

    /// Store user key in crypto cache
    pub async fn store_user_key(&self, user_id: String, user_key: UserKey) -> AppResult<()> {
        CRYPTO_CACHE.store_user_key(user_id, user_key).map_err(|e| {
            warn!("Failed to store user key in crypto cache: {}", e);
            crate::error::AppError::CryptographyError {
                operation: "store_user_key".to_string(),
            }
        })
    }

    /// Get user key from crypto cache
    pub async fn get_user_key(&self, user_id: &str) -> AppResult<Option<UserKey>> {
        CRYPTO_CACHE.get_user_key(user_id).map_err(|e| {
            warn!("Failed to get user key from crypto cache: {}", e);
            crate::error::AppError::CryptographyError {
                operation: "get_user_key".to_string(),
            }
        })
    }

    /// Clear all cached data for a user
    pub async fn clear_user_data(&self, user_id: &str) {
        use tracing::debug;

        debug!(
            user_id = user_id,
            "[memory_cache] Clearing all cached data for user"
        );

        // Clear all ciphers since CipherView doesn't have user_id
        // In a real implementation, we'd need to track user ownership differently
        let mut cache = self.ciphers.write().await;
        let removed_count = cache.len();
        cache.clear();
        drop(cache); // Release the lock

        debug!(
            user_id = user_id,
            removed_ciphers = removed_count,
            "[memory_cache] Successfully cleared cached data for user"
        );
    }
}

/// Cache statistics
#[derive(Debug, Clone)]
pub struct CacheStats {
    pub size: usize,
    pub max_size: usize,
    pub ttl_minutes: i64,
}

impl Default for MemoryCache {
    fn default() -> Self {
        Self::new(1000, 30) // 1000 items, 30 minutes TTL
    }
}
