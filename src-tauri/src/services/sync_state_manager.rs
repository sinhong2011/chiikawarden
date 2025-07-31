use crate::error::AppResult;
use crate::models::{SyncMode, SyncState};
use crate::services::NetworkMonitorService;
use crate::storage::AppDatabase;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use specta::Type;
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use tokio::sync::{broadcast, RwLock};
use tracing::{debug, error, info, warn};

/// Sync state change event
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct SyncStateChangeEvent {
    pub user_id: String,
    pub old_mode: SyncMode,
    pub new_mode: SyncMode,
    pub network_state: String,
    pub timestamp: DateTime<Utc>,
}

/// Network-aware sync state manager
pub struct SyncStateManager {
    app_handle: AppHandle,
    database: Arc<AppDatabase>,
    network_monitor: Arc<NetworkMonitorService>,
    state_cache: Arc<RwLock<std::collections::HashMap<String, SyncState>>>,
    change_sender: broadcast::Sender<SyncStateChangeEvent>,
}

impl SyncStateManager {
    /// Create a new sync state manager
    pub fn new(
        app_handle: AppHandle,
        database: Arc<AppDatabase>,
        network_monitor: Arc<NetworkMonitorService>,
    ) -> Self {
        let (change_sender, _) = broadcast::channel(100);

        Self {
            app_handle,
            database,
            network_monitor,
            state_cache: Arc::new(RwLock::new(std::collections::HashMap::new())),
            change_sender,
        }
    }

    /// Initialize sync state manager and start monitoring
    pub async fn initialize(&self) -> AppResult<()> {
        info!("[sync_state_manager] Initializing network-aware sync state management");

        // Subscribe to network status changes
        let mut network_receiver = self.network_monitor.subscribe();
        let state_cache = Arc::clone(&self.state_cache);
        let database = Arc::clone(&self.database);
        let change_sender = self.change_sender.clone();
        let app_handle = self.app_handle.clone();

        tokio::spawn(async move {
            while let Ok(network_status) = network_receiver.recv().await {
                debug!(
                    "[sync_state_manager] Network status changed: {} (server_reachable: {})",
                    network_status.state, network_status.server_reachable
                );

                // Update sync states for all users based on network status
                let mut cache = state_cache.write().await;
                for (user_id, sync_state) in cache.iter_mut() {
                    let old_mode = sync_state.sync_mode.clone();
                    let new_mode = Self::determine_sync_mode(
                        &network_status.state.to_string(),
                        network_status.server_reachable,
                    );

                    if old_mode != new_mode {
                        sync_state.sync_mode = new_mode.clone();
                        sync_state.network_state = network_status.state.to_string();

                        // Update database
                        if let Err(e) = database.save_sync_state(sync_state).await {
                            error!(
                                "[sync_state_manager] Failed to save sync state for user {}: {}",
                                user_id, e
                            );
                            continue;
                        }

                        // Emit change event
                        let change_event = SyncStateChangeEvent {
                            user_id: user_id.clone(),
                            old_mode: old_mode.clone(),
                            new_mode: new_mode.clone(),
                            network_state: network_status.state.to_string(),
                            timestamp: Utc::now(),
                        };

                        if let Err(e) = change_sender.send(change_event.clone()) {
                            warn!(
                                "[sync_state_manager] Failed to broadcast state change: {}",
                                e
                            );
                        }

                        // Emit Tauri event
                        if let Err(e) = app_handle.emit("sync_state_changed", &change_event) {
                            warn!(
                                "[sync_state_manager] Failed to emit sync state event: {}",
                                e
                            );
                        }

                        info!(
                            "[sync_state_manager] User {} sync mode changed: {} -> {}",
                            user_id, old_mode, new_mode
                        );
                    }
                }
            }
        });

        Ok(())
    }

    /// Get sync state for a user
    pub async fn get_sync_state(&self, user_id: &str) -> AppResult<Option<SyncState>> {
        // Check cache first
        {
            let cache = self.state_cache.read().await;
            if let Some(state) = cache.get(user_id) {
                return Ok(Some(state.clone()));
            }
        }

        // Load from database
        let mut sync_state = match self.database.get_sync_state(user_id).await? {
            Some(state) => state,
            None => return Ok(None),
        };

        // Update sync mode based on current network status
        let network_status = self.network_monitor.get_status().await;
        let current_mode = Self::determine_sync_mode(
            &network_status.state.to_string(),
            network_status.server_reachable,
        );

        if sync_state.sync_mode != current_mode {
            sync_state.sync_mode = current_mode;
            sync_state.network_state = network_status.state.to_string();

            // Save updated state
            self.database.save_sync_state(&sync_state).await?;
        }

        // Cache the state
        {
            let mut cache = self.state_cache.write().await;
            cache.insert(user_id.to_string(), sync_state.clone());
        }

        Ok(Some(sync_state))
    }

    /// Update sync state for a user
    pub async fn update_sync_state(&self, sync_state: &SyncState) -> AppResult<()> {
        // Check if state actually changed to avoid unnecessary database writes
        if let Some(current_state) = self.get_sync_state(&sync_state.user_id).await? {
            if self.states_are_equivalent(&current_state, sync_state) {
                debug!(
                    "[sync_state_manager] Sync state unchanged for user: {}, skipping update",
                    sync_state.user_id
                );
                return Ok(());
            }
        }

        // Save to database
        self.database.save_sync_state(sync_state).await?;

        // Update cache
        {
            let mut cache = self.state_cache.write().await;
            cache.insert(sync_state.user_id.clone(), sync_state.clone());
        }

        debug!(
            "[sync_state_manager] Updated sync state for user: {}",
            sync_state.user_id
        );
        Ok(())
    }

    /// Check if two sync states are equivalent (ignoring minor timestamp differences)
    fn states_are_equivalent(&self, state1: &SyncState, state2: &SyncState) -> bool {
        state1.user_id == state2.user_id
            && state1.is_syncing == state2.is_syncing
            && state1.sync_mode == state2.sync_mode
            && state1.websocket_connected == state2.websocket_connected
            && state1.background_sync_enabled == state2.background_sync_enabled
            && state1.sync_interval_hours == state2.sync_interval_hours
            && state1.network_state == state2.network_state
            && state1.cached_items_count == state2.cached_items_count
    }

    /// Set sync mode for a user (with network state validation)
    pub async fn set_sync_mode(
        &self,
        user_id: &str,
        requested_mode: SyncMode,
    ) -> AppResult<SyncMode> {
        let network_status = self.network_monitor.get_status().await;
        let allowed_mode = Self::determine_sync_mode(
            &network_status.state.to_string(),
            network_status.server_reachable,
        );

        // Can't force online mode if network is offline
        let actual_mode = match (requested_mode, allowed_mode) {
            (SyncMode::Online, SyncMode::Offline) => {
                warn!("[sync_state_manager] Cannot set online mode - network is offline");
                SyncMode::Offline
            }
            (mode, _) => mode,
        };

        // Get current sync state
        let mut sync_state = match self.get_sync_state(user_id).await? {
            Some(state) => state,
            None => {
                // Create new sync state
                SyncState {
                    user_id: user_id.to_string(),
                    last_sync: None,
                    revision_date: None,
                    is_syncing: false,
                    sync_mode: actual_mode.clone(),
                    last_websocket_connection: None,
                    websocket_connected: false,
                    background_sync_enabled: true,
                    sync_interval_hours: 6,
                    last_server_notification: None,
                    server_revision_date: None,
                    network_state: network_status.state.to_string(),
                    last_online_sync: None,
                    cached_items_count: 0,
                }
            }
        };

        let old_mode = sync_state.sync_mode.clone();
        sync_state.sync_mode = actual_mode.clone();
        sync_state.network_state = network_status.state.to_string();

        // Update state
        self.update_sync_state(&sync_state).await?;

        // Emit change event if mode changed
        if old_mode != actual_mode {
            let change_event = SyncStateChangeEvent {
                user_id: user_id.to_string(),
                old_mode,
                new_mode: actual_mode.clone(),
                network_state: network_status.state.to_string(),
                timestamp: Utc::now(),
            };

            if let Err(e) = self.change_sender.send(change_event.clone()) {
                warn!(
                    "[sync_state_manager] Failed to broadcast state change: {}",
                    e
                );
            }

            if let Err(e) = self.app_handle.emit("sync_state_changed", &change_event) {
                warn!(
                    "[sync_state_manager] Failed to emit sync state event: {}",
                    e
                );
            }
        }

        Ok(actual_mode)
    }

    /// Check if user is in online mode
    pub async fn is_online_mode(&self, user_id: &str) -> AppResult<bool> {
        match self.get_sync_state(user_id).await? {
            Some(state) => Ok(state.sync_mode == SyncMode::Online),
            None => Ok(false),
        }
    }

    /// Check if user is in offline mode
    pub async fn is_offline_mode(&self, user_id: &str) -> AppResult<bool> {
        match self.get_sync_state(user_id).await? {
            Some(state) => Ok(state.sync_mode == SyncMode::Offline),
            None => Ok(true), // Default to offline if no state
        }
    }

    /// Subscribe to sync state changes
    pub fn subscribe(&self) -> broadcast::Receiver<SyncStateChangeEvent> {
        self.change_sender.subscribe()
    }

    /// Clear cached state for a user
    pub async fn clear_cache(&self, user_id: &str) {
        let mut cache = self.state_cache.write().await;
        cache.remove(user_id);
        debug!("[sync_state_manager] Cleared cache for user: {}", user_id);
    }

    /// Clear all cached states
    pub async fn clear_all_cache(&self) {
        let mut cache = self.state_cache.write().await;
        cache.clear();
        debug!("[sync_state_manager] Cleared all cached sync states");
    }

    /// Determine sync mode based on network state
    fn determine_sync_mode(network_state: &str, server_reachable: bool) -> SyncMode {
        match network_state {
            "online" if server_reachable => SyncMode::Online,
            _ => SyncMode::Offline,
        }
    }

    /// Update last sync timestamp
    pub async fn update_last_sync(&self, user_id: &str) -> AppResult<()> {
        if let Some(mut sync_state) = self.get_sync_state(user_id).await? {
            sync_state.last_sync = Some(Utc::now());

            // If currently online, also update last_online_sync
            if sync_state.sync_mode == SyncMode::Online {
                sync_state.last_online_sync = Some(Utc::now());
            }

            self.update_sync_state(&sync_state).await?;
        }
        Ok(())
    }

    /// Update cached items count
    pub async fn update_cached_items_count(&self, user_id: &str, count: u32) -> AppResult<()> {
        if let Some(mut sync_state) = self.get_sync_state(user_id).await? {
            sync_state.cached_items_count = count;
            self.update_sync_state(&sync_state).await?;
        }
        Ok(())
    }
}
