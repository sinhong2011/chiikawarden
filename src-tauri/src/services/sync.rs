use crate::api::ApiClient;
use crate::error::{AppError, AppResult};
use crate::logging::log_sync_event;
use crate::models::SyncState;
use crate::services::ServerProviderService;
use crate::storage::AppDatabase;
use chrono::Utc;
use serde_json::Value;
use std::sync::Arc;
use tauri::AppHandle;
use tracing::{debug, error, info};

/// Sync service for synchronizing data with Bitwarden server
pub struct SyncService {
    api_client: ApiClient,
    database: Arc<AppDatabase>,
    token_manager: Arc<tokio::sync::RwLock<crate::crypto::token_manager::TokenManager>>,
}

impl SyncService {
    pub fn new(
        app_handle: AppHandle,
        database: Arc<AppDatabase>,
        server_provider_service: Arc<ServerProviderService>,
        token_manager: Arc<tokio::sync::RwLock<crate::crypto::token_manager::TokenManager>>,
    ) -> Self {
        Self {
            api_client: ApiClient::new(app_handle, server_provider_service),
            database,
            token_manager,
        }
    }

    /// Sync vault data with server
    pub async fn sync_vault(&self, user_id: &str, access_token: &str) -> AppResult<()> {
        info!(user_id = user_id, "[sync] Starting vault synchronization");

        // Get current sync state
        let sync_state = self.database.get_sync_state(user_id).await?;

        // Build sync URL with revision date if available
        let mut sync_url = "/sync".to_string();
        if let Some(revision_date) = sync_state.and_then(|s| s.revision_date) {
            sync_url.push_str(&format!("?lastRevisionDate={}", revision_date.timestamp()));
            debug!(
                user_id = user_id,
                revision_date = %revision_date,
                "[sync] Using incremental sync from revision date: {}",
                revision_date
            );
        } else {
            info!(
                user_id = user_id,
                "[sync] Performing full sync (no previous revision date)"
            );
        }

        // Get sync data from server
        debug!(
            user_id = user_id,
            sync_url = %sync_url,
            "[sync] Requesting sync data from server"
        );
        let sync_data: Value = self.api_client.get(&sync_url, Some(access_token)).await?;

        // Process sync data
        self.process_sync_data(user_id, &sync_data).await?;

        // Update sync state
        let new_sync_state = SyncState {
            user_id: user_id.to_string(),
            last_sync: Some(Utc::now()),
            revision_date: Some(Utc::now()),
            is_syncing: false,
            sync_mode: crate::models::SyncMode::Online,
            last_websocket_connection: None,
            websocket_connected: false,
            background_sync_enabled: true,
            sync_interval_hours: 6,
            last_server_notification: None,
            server_revision_date: None,
            network_state: "online".to_string(),
            last_online_sync: Some(Utc::now()),
            cached_items_count: 0,
        };
        self.database.save_sync_state(&new_sync_state).await?;

        info!(
            user_id = user_id,
            "[sync] Vault synchronization completed successfully"
        );
        log_sync_event("sync_vault_completed", user_id, Some("full sync operation"));
        Ok(())
    }

    /// Get sync status
    pub async fn get_sync_status(&self, user_id: &str) -> AppResult<Option<SyncState>> {
        self.database.get_sync_state(user_id).await
    }

    /// Process sync data from server
    async fn process_sync_data(&self, user_id: &str, sync_data: &Value) -> AppResult<()> {
        info!(user_id = user_id, "[sync] Processing sync data from server");

        // Process ciphers
        if let Some(ciphers) = sync_data.get("ciphers").and_then(|c| c.as_array()) {
            info!(
                user_id = user_id,
                cipher_count = ciphers.len(),
                "[sync] Processing {} ciphers",
                ciphers.len()
            );

            for cipher_data in ciphers {
                match self.convert_and_save_cipher(user_id, cipher_data).await {
                    Ok(cipher_id) => {
                        debug!(
                            user_id = user_id,
                            cipher_id = %cipher_id,
                            "[sync] Successfully saved cipher: {}",
                            cipher_id
                        );
                    }
                    Err(e) => {
                        error!(
                            user_id = user_id,
                            error = %e,
                            "[sync] Failed to save cipher: {}",
                            e
                        );
                    }
                }
            }
        }

        // Process folders
        if let Some(folders) = sync_data.get("folders").and_then(|f| f.as_array()) {
            info!(
                user_id = user_id,
                folder_count = folders.len(),
                "[sync] Processing {} folders",
                folders.len()
            );

            for folder_data in folders {
                match self.convert_and_save_folder(user_id, folder_data).await {
                    Ok(folder_id) => {
                        debug!(
                            user_id = user_id,
                            folder_id = %folder_id,
                            "[sync] Successfully saved folder: {}",
                            folder_id
                        );
                    }
                    Err(e) => {
                        error!(
                            user_id = user_id,
                            error = %e,
                            "[sync] Failed to save folder: {}",
                            e
                        );
                    }
                }
            }
        }

        // Process collections
        if let Some(collections) = sync_data.get("collections").and_then(|c| c.as_array()) {
            info!(
                user_id = user_id,
                collection_count = collections.len(),
                "[sync] Processing {} collections",
                collections.len()
            );

            for collection_data in collections {
                if let Some(collection_id) = collection_data.get("id") {
                    debug!(
                        user_id = user_id,
                        collection_id = %collection_id,
                        "[sync] Processing collection: {}",
                        collection_id
                    );
                    // Convert and save collection
                    // TODO: Implement actual collection processing
                }
            }
        }

        info!(user_id = user_id, "[sync] Sync data processing completed");
        Ok(())
    }

    /// Convert Vaultwarden cipher data to local Cipher model and save to database
    async fn convert_and_save_cipher(&self, user_id: &str, cipher_data: &Value) -> AppResult<String> {
        use crate::models::Cipher;
        use chrono::{DateTime, Utc};

        // Extract required fields from Vaultwarden API response
        let id = cipher_data
            .get("id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AppError::SyncError {
                message: "Missing cipher ID".to_string(),
            })?
            .to_string();

        let name = cipher_data
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("Untitled")
            .to_string();

        let notes = cipher_data
            .get("notes")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        let cipher_type = cipher_data
            .get("type")
            .and_then(|v| v.as_i64())
            .unwrap_or(1) as i32;

        let organization_id = cipher_data
            .get("organizationId")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        let folder_id = cipher_data
            .get("folderId")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        let favorite = cipher_data
            .get("favorite")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        let reprompt = cipher_data
            .get("reprompt")
            .and_then(|v| v.as_i64())
            .unwrap_or(0) != 0;

        // Parse dates
        let revision_date = cipher_data
            .get("revisionDate")
            .and_then(|v| v.as_str())
            .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
            .map(|dt| dt.with_timezone(&Utc))
            .unwrap_or_else(Utc::now);

        let created_date = cipher_data
            .get("creationDate")
            .and_then(|v| v.as_str())
            .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
            .map(|dt| dt.with_timezone(&Utc))
            .unwrap_or_else(Utc::now);

        // Store the entire cipher data as encrypted JSON for now
        // In a real implementation, you would properly encrypt this data
        let encrypted_data = serde_json::to_string(cipher_data).map_err(|e| AppError::SyncError {
            message: format!("Failed to serialize cipher data: {}", e),
        })?;

        let cipher = Cipher {
            id: id.clone(),
            user_id: user_id.to_string(),
            organization_id,
            folder_id,
            name,
            notes,
            cipher_type,
            encrypted_data,
            favorite,
            reprompt,
            revision_date,
            created_date,
            deleted_date: None,
            enc_type: 2, // Default encryption type
            mac: None,
        };

        // Save to database
        self.database.save_cipher(user_id, &cipher).await?;

        debug!(
            user_id = user_id,
            cipher_id = %id,
            cipher_name = %cipher.name,
            cipher_type = cipher_type,
            "[sync] Converted and saved cipher to database"
        );

        Ok(id)
    }

    /// Convert Vaultwarden folder data to local Folder model and save to database
    async fn convert_and_save_folder(&self, user_id: &str, folder_data: &Value) -> AppResult<String> {
        use crate::models::Folder;
        use chrono::{DateTime, Utc};

        let id = folder_data
            .get("id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AppError::SyncError {
                message: "Missing folder ID".to_string(),
            })?
            .to_string();

        let name = folder_data
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("Untitled Folder")
            .to_string();

        let revision_date = folder_data
            .get("revisionDate")
            .and_then(|v| v.as_str())
            .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
            .map(|dt| dt.with_timezone(&Utc))
            .unwrap_or_else(Utc::now);

        let folder = Folder {
            id: id.clone(),
            user_id: user_id.to_string(),
            name,
            revision_date,
        };

        // Save to database
        self.database.save_folder(&folder).await?;

        debug!(
            user_id = user_id,
            folder_id = %id,
            folder_name = %folder.name,
            "[sync] Converted and saved folder to database"
        );

        Ok(id)
    }

    /// Sync vault data with automatic token refresh
    pub async fn sync_vault_with_auto_refresh(
        &self,
        user_id: &str,
    ) -> AppResult<()> {
        use tracing::{debug, info};

        info!(user_id = user_id, "[sync] Starting vault synchronization with auto-refresh");

        // Get current sync state
        let sync_state = self.database.get_sync_state(user_id).await?;

        // Build sync URL with revision date if available
        let mut sync_url = "/sync".to_string();
        if let Some(revision_date) = sync_state.and_then(|s| s.revision_date) {
            sync_url.push_str(&format!("?lastRevisionDate={}", revision_date.timestamp()));
            debug!(
                user_id = user_id,
                revision_date = %revision_date,
                "[sync] Using incremental sync from revision date: {}",
                revision_date
            );
        } else {
            info!(
                user_id = user_id,
                "[sync] Performing full sync (no previous revision date)"
            );
        }

        // Get sync data from server using auto-refresh
        info!(
            user_id = user_id,
            sync_url = %sync_url,
            "[sync] Requesting sync data from server with auto-refresh - this requires valid access token"
        );

        let sync_data: Value = match self
            .api_client
            .get_with_auto_refresh(&sync_url, user_id, &self.token_manager)
            .await {
                Ok(data) => {
                    info!(
                        user_id = user_id,
                        sync_url = %sync_url,
                        "[sync] Successfully received sync data from server - processing vault data"
                    );
                    data
                }
                Err(e) => {
                    error!(
                        user_id = user_id,
                        sync_url = %sync_url,
                        error = %e,
                        "[sync] CRITICAL: Failed to get sync data from server - this usually means token issues: {}", e
                    );
                    return Err(e);
                }
            };

        // Process sync data
        self.process_sync_data(user_id, &sync_data).await?;

        // Update sync state
        let new_sync_state = SyncState {
            user_id: user_id.to_string(),
            last_sync: Some(Utc::now()),
            revision_date: Some(Utc::now()),
            is_syncing: false,
            sync_mode: crate::models::SyncMode::Online,
            last_websocket_connection: None,
            websocket_connected: false,
            background_sync_enabled: true,
            sync_interval_hours: 6,
            last_server_notification: None,
            server_revision_date: None,
            network_state: "online".to_string(),
            last_online_sync: Some(Utc::now()),
            cached_items_count: 0,
        };

        self.database.save_sync_state(&new_sync_state).await?;

        info!(user_id = user_id, "[sync] Vault synchronization completed successfully with auto-refresh");
        Ok(())
    }

    /// Force full sync (ignores revision dates)
    pub async fn force_sync(&self, user_id: &str, access_token: &str) -> AppResult<()> {
        // Clear sync state to force full sync
        self.database.clear_sync_state(user_id).await?;

        // Perform sync
        self.sync_vault(user_id, access_token).await
    }

    /// Force full sync with automatic token refresh
    pub async fn force_sync_with_auto_refresh(
        &self,
        user_id: &str,
    ) -> AppResult<()> {
        // Clear sync state to force full sync
        self.database.clear_sync_state(user_id).await?;

        // Perform sync with auto-refresh
        self.sync_vault_with_auto_refresh(user_id).await
    }
}

// Note: SyncService requires a database instance, so no Default implementation
