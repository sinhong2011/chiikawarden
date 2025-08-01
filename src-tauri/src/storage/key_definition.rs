// Key definitions for storage layer
use crate::error::AppResult;
use serde::{Deserialize, Serialize};
use specta::Type;
use std::time::Duration;
use tracing::{info, warn};

/// Events that can trigger key clearing
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Type)]
pub enum ClearOn {
    /// Clear key when vault is locked
    Lock,
    /// Clear key when user logs out
    Logout,
    /// Never clear key automatically
    Never,
}

/// Storage locations for different key types
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Type)]
pub enum StorageLocation {
    /// In-memory storage (cleared on app restart)
    Memory,
    /// Persistent disk storage
    Disk,
    /// Platform-specific secure storage (OS keyring, etc.)
    Secure,
}

/// Definition for how a specific key type should be stored and managed
#[derive(Debug, Clone)]
pub struct KeyDefinition {
    /// Unique identifier for this key type
    pub key_name: &'static str,
    /// Where the key should be stored
    pub storage_location: StorageLocation,
    /// Events that should trigger clearing this key
    pub clear_on: &'static [ClearOn],
    /// Time-to-live for the key (None = no expiration)
    pub ttl: Option<Duration>,
    /// Human-readable description for logging
    pub description: &'static str,
}

impl KeyDefinition {
    /// Check if this key should be cleared on a specific event
    pub fn should_clear_on(&self, event: &ClearOn) -> bool {
        self.clear_on.contains(event)
    }

    /// Check if this key has expired based on TTL
    pub fn is_expired(&self, stored_at: std::time::SystemTime) -> bool {
        if let Some(ttl) = self.ttl {
            if let Ok(elapsed) = stored_at.elapsed() {
                return elapsed > ttl;
            }
        }
        false
    }

    /// Get storage key for a specific user
    pub fn get_storage_key(&self, user_id: &str) -> String {
        format!("{}_{}", self.key_name, user_id)
    }
}

// Static key definitions for different key types

/// User key stored in memory with TTL
pub static USER_KEY_DEF: KeyDefinition = KeyDefinition {
    key_name: "user_key",
    storage_location: StorageLocation::Memory,
    clear_on: &[ClearOn::Lock, ClearOn::Logout],
    ttl: Some(Duration::from_secs(1800)), // 30 minutes
    description: "Primary user key for vault decryption",
};

/// Master key stored in memory with shorter TTL
pub static MASTER_KEY_DEF: KeyDefinition = KeyDefinition {
    key_name: "master_key",
    storage_location: StorageLocation::Memory,
    clear_on: &[ClearOn::Lock, ClearOn::Logout],
    ttl: Some(Duration::from_secs(900)), // 15 minutes
    description: "Master key derived from user password",
};

/// Auto-unlock key stored securely, survives lock but not logout
pub static AUTO_UNLOCK_KEY_DEF: KeyDefinition = KeyDefinition {
    key_name: "auto_unlock_key",
    storage_location: StorageLocation::Secure,
    clear_on: &[ClearOn::Logout], // Survives lock but not logout
    ttl: None,                    // No expiration for auto-unlock keys
    description: "User key for automatic unlock when timeout is never",
};

/// Device key stored securely, never cleared automatically
pub static DEVICE_KEY_DEF: KeyDefinition = KeyDefinition {
    key_name: "device_key",
    storage_location: StorageLocation::Secure,
    clear_on: &[], // Never cleared automatically
    ttl: None,     // No expiration for device keys
    description: "Device trust key for passwordless authentication",
};

/// Biometric key stored securely, cleared on logout
pub static BIOMETRIC_KEY_DEF: KeyDefinition = KeyDefinition {
    key_name: "biometric_key",
    storage_location: StorageLocation::Secure,
    clear_on: &[ClearOn::Logout],
    ttl: None, // No expiration for biometric keys
    description: "Key for biometric authentication",
};

/// Key metadata for tracking storage information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyMetadata {
    pub stored_at: std::time::SystemTime,
    pub key_type: String,
    pub user_id: String,
    pub storage_location: StorageLocation,
}

impl KeyMetadata {
    pub fn new(key_type: String, user_id: String, storage_location: StorageLocation) -> Self {
        Self {
            stored_at: std::time::SystemTime::now(),
            key_type,
            user_id,
            storage_location,
        }
    }
}

/// Service for managing keys according to their definitions
pub struct KeyDefinitionService;

impl KeyDefinitionService {
    /// Clear keys based on an event (lock, logout, etc.)
    pub async fn clear_keys_on_event(
        user_id: &str,
        event: ClearOn,
        secure_storage: &crate::storage::secure_key_store::SecureKeyStore,
        memory_cache: &crate::storage::memory_cache::MemoryCache,
    ) -> AppResult<()> {
        info!(
            user_id = user_id,
            event = ?event,
            "[key_definition] Clearing keys based on event"
        );

        let mut cleared_keys = Vec::new();

        // Clear memory-based keys (user key, master key) by clearing all user data
        if USER_KEY_DEF.should_clear_on(&event) || MASTER_KEY_DEF.should_clear_on(&event) {
            memory_cache.clear_user_data(user_id).await;
            if USER_KEY_DEF.should_clear_on(&event) {
                cleared_keys.push(USER_KEY_DEF.key_name);
            }
            if MASTER_KEY_DEF.should_clear_on(&event) {
                cleared_keys.push(MASTER_KEY_DEF.key_name);
            }
        }

        // Clear secure storage keys individually
        if AUTO_UNLOCK_KEY_DEF.should_clear_on(&event) {
            if let Err(e) = secure_storage.clear_auto_unlock_key(user_id).await {
                warn!(
                    user_id = user_id,
                    key_type = AUTO_UNLOCK_KEY_DEF.key_name,
                    error = %e,
                    "[key_definition] Failed to clear auto-unlock key from secure storage"
                );
            } else {
                cleared_keys.push(AUTO_UNLOCK_KEY_DEF.key_name);
            }
        }

        if BIOMETRIC_KEY_DEF.should_clear_on(&event) {
            let key = format!("biometric_key_{}", user_id);
            if let Err(e) = secure_storage.remove_vault_data(&key).await {
                warn!(
                    user_id = user_id,
                    key_type = BIOMETRIC_KEY_DEF.key_name,
                    error = %e,
                    "[key_definition] Failed to clear biometric key from secure storage"
                );
            } else {
                cleared_keys.push(BIOMETRIC_KEY_DEF.key_name);
            }
        }

        // Note: DEVICE_KEY_DEF never clears automatically (clear_on is empty)

        info!(
            user_id = user_id,
            event = ?event,
            cleared_keys = ?cleared_keys,
            "[key_definition] Key clearing completed"
        );

        Ok(())
    }

    /// Clean up expired keys based on their TTL
    /// Note: Currently simplified to use the memory cache's built-in cleanup
    pub async fn cleanup_expired_keys(
        _user_id: &str,
        memory_cache: &crate::storage::memory_cache::MemoryCache,
    ) -> AppResult<()> {
        // Use the memory cache's built-in cleanup mechanism
        memory_cache.cleanup_expired().await;
        Ok(())
    }
}
