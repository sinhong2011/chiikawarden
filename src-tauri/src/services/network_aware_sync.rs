use crate::api::ApiClient;
use crate::error::{AppError, AppResult};
use crate::logging::log_sync_event;
use crate::models::{SyncMode, SyncState};
use crate::services::{NetworkMonitorService, ServerProviderService, SyncStateManager};
use crate::storage::AppDatabase;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use specta::Type;
use std::collections::HashMap;
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use tokio::sync::Mutex;
use tracing::{debug, error, info, warn};

/// Sync operation result with mode information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct NetworkAwareSyncResult {
    pub success: bool,
    pub sync_mode: SyncMode,
    pub last_sync: String,
    pub revision_date: Option<String>,
    pub message: String,
    pub items_synced: u32,
    pub network_state: String,
    pub cached_items_count: u32,
}

/// Network-aware sync service supporting both online and offline modes
pub struct NetworkAwareSyncService {
    app_handle: AppHandle,
    api_client: ApiClient,
    database: Arc<AppDatabase>,
    network_monitor: Arc<NetworkMonitorService>,
    sync_state_manager: Arc<SyncStateManager>,
    token_manager: Arc<tokio::sync::RwLock<crate::crypto::token_manager::TokenManager>>,
    // Sync coordination to prevent concurrent syncs for the same user
    sync_locks: Arc<Mutex<HashMap<String, Arc<Mutex<()>>>>>,
    // Rate limiting: track last sync attempt per user (additional safety)
    last_sync_attempts: Arc<Mutex<HashMap<String, DateTime<Utc>>>>,
}

impl NetworkAwareSyncService {
    /// Create a new network-aware sync service
    pub fn new(
        app_handle: AppHandle,
        database: Arc<AppDatabase>,
        server_provider_service: Arc<ServerProviderService>,
        network_monitor: Arc<NetworkMonitorService>,
        sync_state_manager: Arc<SyncStateManager>,
        token_manager: Arc<tokio::sync::RwLock<crate::crypto::token_manager::TokenManager>>,
    ) -> Self {
        Self {
            app_handle: app_handle.clone(),
            api_client: ApiClient::new(app_handle, server_provider_service),
            database,
            network_monitor,
            sync_state_manager,
            token_manager,
            sync_locks: Arc::new(Mutex::new(HashMap::new())),
            last_sync_attempts: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Get or create a sync lock for a user to prevent concurrent syncs
    async fn get_sync_lock(&self, user_id: &str) -> Arc<Mutex<()>> {
        let mut locks = self.sync_locks.lock().await;
        locks
            .entry(user_id.to_string())
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone()
    }

    /// Sync vault data with automatic mode detection
    pub async fn sync_vault(
        &self,
        user_id: &str,
        access_token: &str,
    ) -> AppResult<NetworkAwareSyncResult> {
        info!(
            user_id = user_id,
            "[network_aware_sync] Starting network-aware vault synchronization"
        );

        // Get current sync state and network status
        let sync_state = self
            .sync_state_manager
            .get_sync_state(user_id)
            .await?
            .unwrap_or_else(|| self.create_default_sync_state(user_id));

        let network_status = self.network_monitor.get_status().await;
        let is_online = self.network_monitor.is_online().await;

        // Determine sync mode
        let sync_mode = if is_online {
            SyncMode::Online
        } else {
            SyncMode::Offline
        };

        info!(
            user_id = user_id,
            sync_mode = %sync_mode,
            network_state = %network_status.state,
            "[network_aware_sync] Sync mode determined: {}", sync_mode
        );

        // Update sync state mode
        self.sync_state_manager
            .set_sync_mode(user_id, sync_mode.clone())
            .await?;

        // Perform sync based on mode
        let result = match sync_mode {
            SyncMode::Online => {
                self.sync_online_mode(user_id, access_token, &sync_state)
                    .await?
            }
            SyncMode::Offline => self.sync_offline_mode(user_id, &sync_state).await?,
        };

        // Emit sync completed event
        if let Err(e) = self.app_handle.emit("vault_sync_completed", &result) {
            warn!(
                "[network_aware_sync] Failed to emit sync completed event: {}",
                e
            );
        }

        log_sync_event(
            "network_aware_sync_completed",
            user_id,
            Some(&format!("mode: {}, success: {}", sync_mode, result.success)),
        );

        Ok(result)
    }

    /// Perform online mode sync with full server communication
    async fn sync_online_mode(
        &self,
        user_id: &str,
        access_token: &str,
        sync_state: &SyncState,
    ) -> AppResult<NetworkAwareSyncResult> {
        info!(
            user_id = user_id,
            "[network_aware_sync] Performing online sync"
        );

        // Mark as syncing
        let mut updated_state = sync_state.clone();
        updated_state.is_syncing = true;
        self.sync_state_manager
            .update_sync_state(&updated_state)
            .await?;

        // Build sync URL with revision date if available
        let mut sync_url = "/sync".to_string();
        if let Some(revision_date) = sync_state.revision_date {
            sync_url.push_str(&format!("?lastRevisionDate={}", revision_date.timestamp()));
            debug!(
                user_id = user_id,
                revision_date = %revision_date,
                "[network_aware_sync] Using incremental sync from revision date"
            );
        } else {
            info!(
                user_id = user_id,
                "[network_aware_sync] Performing full sync (no previous revision date)"
            );
        }

        // Perform server sync
        let sync_result = match self.api_client.get(&sync_url, Some(access_token)).await {
            Ok(sync_data) => {
                // Process sync data
                let items_synced = self.process_sync_data(user_id, &sync_data).await?;

                // Update sync state
                let mut new_sync_state = sync_state.clone();
                new_sync_state.last_sync = Some(Utc::now());
                new_sync_state.last_online_sync = Some(Utc::now());
                new_sync_state.revision_date = Some(Utc::now());
                new_sync_state.is_syncing = false;
                new_sync_state.sync_mode = SyncMode::Online;
                new_sync_state.network_state = "online".to_string();

                // Count cached items
                let cached_count = self.count_cached_items(user_id).await?;
                new_sync_state.cached_items_count = cached_count;

                self.sync_state_manager
                    .update_sync_state(&new_sync_state)
                    .await?;

                NetworkAwareSyncResult {
                    success: true,
                    sync_mode: SyncMode::Online,
                    last_sync: new_sync_state.last_sync.unwrap().to_rfc3339(),
                    revision_date: new_sync_state.revision_date.map(|dt| dt.to_rfc3339()),
                    message: "Vault synchronized successfully (online mode)".to_string(),
                    items_synced,
                    network_state: "online".to_string(),
                    cached_items_count: cached_count,
                }
            }
            Err(e) => {
                error!(user_id = user_id, error = %e, "[network_aware_sync] Online sync failed, falling back to offline mode");

                // Mark as not syncing and fallback to offline
                let mut fallback_state = sync_state.clone();
                fallback_state.is_syncing = false;
                fallback_state.sync_mode = SyncMode::Offline;
                fallback_state.network_state = "limited".to_string();
                self.sync_state_manager
                    .update_sync_state(&fallback_state)
                    .await?;

                // Perform offline sync as fallback
                self.sync_offline_mode(user_id, &fallback_state).await?
            }
        };

        Ok(sync_result)
    }

    /// Perform offline mode sync using cached data
    async fn sync_offline_mode(
        &self,
        user_id: &str,
        sync_state: &SyncState,
    ) -> AppResult<NetworkAwareSyncResult> {
        info!(
            user_id = user_id,
            "[network_aware_sync] Performing offline sync (read-only mode)"
        );

        // Count cached items
        let cached_count = self.count_cached_items(user_id).await?;

        // Update sync state for offline mode
        let mut updated_state = sync_state.clone();
        updated_state.sync_mode = SyncMode::Offline;
        updated_state.cached_items_count = cached_count;
        updated_state.is_syncing = false;

        // Determine network state
        let network_status = self.network_monitor.get_status().await;
        updated_state.network_state = network_status.state.to_string();

        self.sync_state_manager
            .update_sync_state(&updated_state)
            .await?;

        let last_sync = sync_state
            .last_sync
            .or(sync_state.last_online_sync)
            .unwrap_or_else(Utc::now);

        Ok(NetworkAwareSyncResult {
            success: true,
            sync_mode: SyncMode::Offline,
            last_sync: last_sync.to_rfc3339(),
            revision_date: sync_state.revision_date.map(|dt| dt.to_rfc3339()),
            message: format!(
                "Using cached vault data ({} items available offline)",
                cached_count
            ),
            items_synced: 0, // No items synced in offline mode
            network_state: network_status.state.to_string(),
            cached_items_count: cached_count,
        })
    }

    /// Sync vault data with automatic token refresh and mode detection
    pub async fn sync_vault_with_auto_refresh(
        &self,
        user_id: &str,
    ) -> AppResult<NetworkAwareSyncResult> {
        // Acquire sync lock to prevent concurrent syncs for the same user
        let sync_lock = self.get_sync_lock(user_id).await;
        let _guard = sync_lock.lock().await;

        info!(
            user_id = user_id,
            "[network_aware_sync] Starting network-aware vault synchronization with auto-refresh (lock acquired)"
        );

        // Additional rate limiting check (safety mechanism)
        {
            let mut attempts = self.last_sync_attempts.lock().await;
            let now = Utc::now();

            if let Some(last_attempt) = attempts.get(user_id) {
                let time_since_attempt = now.signed_duration_since(*last_attempt);
                if time_since_attempt.num_seconds() < 2 {
                    error!(
                        user_id = user_id,
                        seconds_since_attempt = time_since_attempt.num_seconds(),
                        "[network_aware_sync] RATE LIMIT: Rejecting sync attempt - too frequent (< 2 seconds)"
                    );
                    return Ok(NetworkAwareSyncResult {
                        success: false,
                        sync_mode: SyncMode::Offline,
                        last_sync: "".to_string(),
                        revision_date: None,
                        message: format!("Rate limited - only {} seconds since last attempt", time_since_attempt.num_seconds()),
                        items_synced: 0,
                        network_state: "rate_limited".to_string(),
                        cached_items_count: 0,
                    });
                }
            }

            // Record this attempt
            attempts.insert(user_id.to_string(), now);
        }

        // Check if already syncing (double-check after acquiring lock)
        if let Some(current_state) = self.sync_state_manager.get_sync_state(user_id).await? {
            if current_state.is_syncing {
                warn!(
                    user_id = user_id,
                    "[network_aware_sync] Sync already in progress, rejecting duplicate request"
                );
                return Ok(NetworkAwareSyncResult {
                    success: false, // Changed to false to indicate rejection
                    sync_mode: current_state.sync_mode,
                    last_sync: current_state.last_sync.map(|d| d.to_rfc3339()).unwrap_or_default(),
                    revision_date: current_state.revision_date.map(|d| d.to_rfc3339()),
                    message: "Sync already in progress - request rejected".to_string(),
                    items_synced: 0,
                    network_state: current_state.network_state,
                    cached_items_count: current_state.cached_items_count,
                });
            }
        }

        // We'll mark as syncing after getting the sync state

        // Get current sync state and network status
        let sync_state = self
            .sync_state_manager
            .get_sync_state(user_id)
            .await?
            .unwrap_or_else(|| self.create_default_sync_state(user_id));

        // Mark as syncing IMMEDIATELY to prevent race conditions
        let mut updated_sync_state = sync_state.clone();
        updated_sync_state.is_syncing = true;
        self.sync_state_manager.update_sync_state(&updated_sync_state).await?;

        // Debounce rapid sync requests (minimum 5 seconds between syncs)
        if let Some(last_sync) = sync_state.last_sync {
            let time_since_last_sync = Utc::now().signed_duration_since(last_sync);
            let seconds_since = time_since_last_sync.num_seconds();

            info!(
                user_id = user_id,
                last_sync_time = %last_sync,
                current_time = %Utc::now(),
                seconds_since_last = seconds_since,
                "[network_aware_sync] Checking debounce: {} seconds since last sync",
                seconds_since
            );

            if seconds_since < 5 {
                info!(
                    user_id = user_id,
                    seconds_since_last = seconds_since,
                    "[network_aware_sync] Debouncing sync request - too soon since last sync"
                );
                return Ok(NetworkAwareSyncResult {
                    success: true,
                    sync_mode: sync_state.sync_mode,
                    last_sync: last_sync.to_rfc3339(),
                    revision_date: sync_state.revision_date.map(|d| d.to_rfc3339()),
                    message: format!("Sync debounced - only {} seconds since last sync (minimum 5 required)", seconds_since),
                    items_synced: 0,
                    network_state: sync_state.network_state,
                    cached_items_count: sync_state.cached_items_count,
                });
            }
        }

        let network_status = self.network_monitor.get_status().await;
        let is_online = self.network_monitor.is_online().await;

        // Determine sync mode
        let sync_mode = if is_online {
            SyncMode::Online
        } else {
            SyncMode::Offline
        };

        info!(
            user_id = user_id,
            sync_mode = %sync_mode,
            network_state = %network_status.state,
            "[network_aware_sync] Sync mode determined: {}", sync_mode
        );

        // Update sync state mode
        self.sync_state_manager
            .set_sync_mode(user_id, sync_mode.clone())
            .await?;

        // Perform sync based on mode with proper error handling
        let result = match sync_mode {
            SyncMode::Online => {
                self.sync_online_mode_with_auto_refresh(user_id, &sync_state)
                    .await
            }
            SyncMode::Offline => self.sync_offline_mode(user_id, &sync_state).await,
        };

        // Always reset is_syncing flag, regardless of success/failure
        let mut final_sync_state = sync_state.clone();
        final_sync_state.is_syncing = false;

        match result {
            Ok(sync_result) => {
                // Update last_sync timestamp on success
                final_sync_state.last_sync = Some(Utc::now());
                final_sync_state.last_online_sync = if sync_mode == SyncMode::Online {
                    Some(Utc::now())
                } else {
                    final_sync_state.last_online_sync
                };

                if let Err(e) = self.sync_state_manager.update_sync_state(&final_sync_state).await {
                    error!(user_id = user_id, error = %e, "[network_aware_sync] Failed to update sync state after successful sync");
                }

                // Emit sync completed event
                if let Err(e) = self.app_handle.emit("vault_sync_completed", &sync_result) {
                    warn!(
                        "[network_aware_sync] Failed to emit sync completed event: {}",
                        e
                    );
                }

                log_sync_event(
                    "network_aware_sync_completed",
                    user_id,
                    Some(&format!("mode: {}, success: {}", sync_mode, sync_result.success)),
                );

                Ok(sync_result)
            }
            Err(e) => {
                // Reset sync state on error
                if let Err(state_err) = self.sync_state_manager.update_sync_state(&final_sync_state).await {
                    error!(user_id = user_id, error = %state_err, "[network_aware_sync] Failed to reset sync state after error");
                }

                error!(user_id = user_id, error = %e, "[network_aware_sync] Sync failed");
                Err(e)
            }
        }


    }

    /// Perform online mode sync with auto-refresh and full server communication
    async fn sync_online_mode_with_auto_refresh(
        &self,
        user_id: &str,
        sync_state: &SyncState,
    ) -> AppResult<NetworkAwareSyncResult> {
        info!(
            user_id = user_id,
            "[network_aware_sync] Performing online sync with auto-refresh"
        );

        // Mark as syncing
        let mut updated_state = sync_state.clone();
        updated_state.is_syncing = true;
        self.sync_state_manager
            .update_sync_state(&updated_state)
            .await?;

        // Build sync URL with revision date if available
        let mut sync_url = "/sync".to_string();
        if let Some(revision_date) = sync_state.revision_date {
            sync_url.push_str(&format!("?lastRevisionDate={}", revision_date.timestamp()));
            debug!(
                user_id = user_id,
                revision_date = %revision_date,
                "[network_aware_sync] Using incremental sync from revision date"
            );
        } else {
            info!(
                user_id = user_id,
                "[network_aware_sync] Performing full sync (no previous revision date)"
            );
        }

        // Perform server sync with auto-refresh
        let sync_result = match self.api_client.get_with_auto_refresh(&sync_url, user_id, &self.token_manager).await {
            Ok(sync_data) => {
                // Process sync data
                let items_synced = self.process_sync_data(user_id, &sync_data).await?;

                // Update sync state
                let mut new_sync_state = sync_state.clone();
                new_sync_state.last_sync = Some(Utc::now());
                new_sync_state.last_online_sync = Some(Utc::now());
                new_sync_state.revision_date = Some(Utc::now());
                new_sync_state.is_syncing = false;
                new_sync_state.sync_mode = SyncMode::Online;
                new_sync_state.network_state = "online".to_string();

                // Count cached items
                let cached_count = self.count_cached_items(user_id).await?;
                new_sync_state.cached_items_count = cached_count;

                self.sync_state_manager
                    .update_sync_state(&new_sync_state)
                    .await?;

                NetworkAwareSyncResult {
                    success: true,
                    sync_mode: SyncMode::Online,
                    last_sync: new_sync_state.last_sync.unwrap().to_rfc3339(),
                    revision_date: new_sync_state.revision_date.map(|dt| dt.to_rfc3339()),
                    message: format!("Online sync completed successfully ({} items)", items_synced),
                    items_synced,
                    network_state: "online".to_string(),
                    cached_items_count: cached_count,
                }
            }
            Err(e) => {
                error!(user_id = user_id, error = %e, "[network_aware_sync] Online sync with auto-refresh failed, falling back to offline mode");

                // Mark as not syncing and fallback to offline
                let mut fallback_state = sync_state.clone();
                fallback_state.is_syncing = false;
                fallback_state.sync_mode = SyncMode::Offline;
                fallback_state.network_state = "limited".to_string();
                self.sync_state_manager
                    .update_sync_state(&fallback_state)
                    .await?;

                // Perform offline sync as fallback
                self.sync_offline_mode(user_id, &fallback_state).await?
            }
        };

        Ok(sync_result)
    }

    /// Force online sync (will fail if network is unavailable)
    pub async fn force_online_sync(
        &self,
        user_id: &str,
        access_token: &str,
    ) -> AppResult<NetworkAwareSyncResult> {
        if !self.network_monitor.is_online().await {
            return Err(AppError::NetworkError {
                status: 0,
                message: "Cannot perform online sync - network is offline".to_string(),
            });
        }

        let sync_state = self
            .sync_state_manager
            .get_sync_state(user_id)
            .await?
            .unwrap_or_else(|| self.create_default_sync_state(user_id));

        self.sync_online_mode(user_id, access_token, &sync_state)
            .await
    }

    /// Force online sync with automatic token refresh
    pub async fn force_online_sync_with_auto_refresh(
        &self,
        user_id: &str,
    ) -> AppResult<NetworkAwareSyncResult> {
        if !self.network_monitor.is_online().await {
            return Err(AppError::NetworkError {
                status: 0,
                message: "Cannot perform online sync - network is offline".to_string(),
            });
        }

        let sync_state = self
            .sync_state_manager
            .get_sync_state(user_id)
            .await?
            .unwrap_or_else(|| self.create_default_sync_state(user_id));

        self.sync_online_mode_with_auto_refresh(user_id, &sync_state)
            .await
    }

    /// Get sync status with network awareness
    pub async fn get_sync_status(&self, user_id: &str) -> AppResult<NetworkAwareSyncResult> {
        let sync_state = self
            .sync_state_manager
            .get_sync_state(user_id)
            .await?
            .unwrap_or_else(|| self.create_default_sync_state(user_id));

        let network_status = self.network_monitor.get_status().await;
        let cached_count = self.count_cached_items(user_id).await?;

        let last_sync = sync_state
            .last_sync
            .or(sync_state.last_online_sync)
            .unwrap_or_else(Utc::now);

        let sync_mode = sync_state.sync_mode.clone();
        let message = match sync_mode {
            SyncMode::Online => "Online mode - full access available".to_string(),
            SyncMode::Offline => {
                format!("Offline mode - {} cached items available", cached_count)
            }
        };

        Ok(NetworkAwareSyncResult {
            success: true,
            sync_mode,
            last_sync: last_sync.to_rfc3339(),
            revision_date: sync_state.revision_date.map(|dt| dt.to_rfc3339()),
            message,
            items_synced: 0,
            network_state: network_status.state.to_string(),
            cached_items_count: cached_count,
        })
    }

    /// Check if user can perform write operations
    pub async fn can_write(&self, user_id: &str) -> AppResult<bool> {
        Ok(self.sync_state_manager.is_online_mode(user_id).await?)
    }

    /// Check if user is in read-only mode
    pub async fn is_read_only(&self, user_id: &str) -> AppResult<bool> {
        Ok(self.sync_state_manager.is_offline_mode(user_id).await?)
    }

    /// Create default sync state for new users
    fn create_default_sync_state(&self, user_id: &str) -> SyncState {
        SyncState {
            user_id: user_id.to_string(),
            last_sync: None,
            revision_date: None,
            is_syncing: false,
            sync_mode: SyncMode::Offline, // Default to offline until network is confirmed
            last_websocket_connection: None,
            websocket_connected: false,
            background_sync_enabled: true,
            sync_interval_hours: 6,
            last_server_notification: None,
            server_revision_date: None,
            network_state: "unknown".to_string(),
            last_online_sync: None,
            cached_items_count: 0,
        }
    }

    /// Process sync data from server (placeholder - implement based on existing logic)
    async fn process_sync_data(&self, user_id: &str, _sync_data: &Value) -> AppResult<u32> {
        // This would contain the actual sync data processing logic
        // For now, return a placeholder count
        debug!(
            user_id = user_id,
            "[network_aware_sync] Processing sync data"
        );

        // TODO: Implement actual sync data processing
        // This should parse ciphers, folders, collections, etc. and update the database

        Ok(0) // Placeholder
    }

    /// Count cached items for a user
    async fn count_cached_items(&self, user_id: &str) -> AppResult<u32> {
        // This would count ciphers, folders, collections in the local database
        // For now, return a placeholder count
        debug!(
            user_id = user_id,
            "[network_aware_sync] Counting cached items"
        );

        // TODO: Implement actual item counting from database

        Ok(0) // Placeholder
    }
}
