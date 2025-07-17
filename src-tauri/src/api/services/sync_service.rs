use crate::api::repositories::traits::{FolderRepository, VaultRepository};
use crate::error::{AppError, AppResult};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;
use tracing::{debug, error, info, warn};

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncRequest {
    pub access_token: String,
    pub last_revision: Option<String>,
    pub force_full_sync: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncResult {
    pub success: bool,
    pub revision_date: String,
    pub ciphers_updated: usize,
    pub folders_updated: usize,
    pub collections_updated: usize,
    pub errors: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncStatus {
    pub is_syncing: bool,
    pub last_sync: Option<String>,
    pub next_sync: Option<String>,
    pub sync_errors: Vec<String>,
}

/// API sync service for handling complex synchronization business logic
pub struct ApiSyncService {
    vault_repository: Arc<dyn VaultRepository + Send + Sync>,
    folder_repository: Arc<dyn FolderRepository + Send + Sync>,
}

impl ApiSyncService {
    pub fn new(
        vault_repository: Arc<dyn VaultRepository + Send + Sync>,
        folder_repository: Arc<dyn FolderRepository + Send + Sync>,
    ) -> Self {
        Self {
            vault_repository,
            folder_repository,
        }
    }

    /// Perform intelligent sync based on last revision
    pub async fn sync(&self, request: SyncRequest) -> AppResult<SyncResult> {
        debug!(
            has_last_revision = request.last_revision.is_some(),
            force_full_sync = request.force_full_sync,
            "Starting sync operation"
        );

        let mut errors = Vec::new();
        let mut ciphers_updated = 0;
        let mut folders_updated = 0;
        let mut collections_updated = 0;

        // Determine if we need a full sync
        let last_revision = if request.force_full_sync {
            debug!("Performing full sync (forced)");
            None
        } else {
            debug!(
                last_revision = request.last_revision.as_deref().unwrap_or("none"),
                "Performing incremental sync"
            );
            request.last_revision.as_deref()
        };

        // Perform sync
        match self
            .vault_repository
            .sync_vault(&request.access_token, last_revision)
            .await
        {
            Ok(sync_data) => {
                debug!("Sync vault response received, processing data");

                // Parse sync response
                let revision_date = sync_data
                    .get("RevisionDate")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                // Count updated items
                if let Some(ciphers) = sync_data.get("Ciphers").and_then(|v| v.as_array()) {
                    ciphers_updated = ciphers.len();
                    debug!(
                        ciphers_count = ciphers_updated,
                        "Processed ciphers from sync"
                    );
                }

                if let Some(folders) = sync_data.get("Folders").and_then(|v| v.as_array()) {
                    folders_updated = folders.len();
                    debug!(
                        folders_count = folders_updated,
                        "Processed folders from sync"
                    );
                }

                if let Some(collections) = sync_data.get("Collections").and_then(|v| v.as_array()) {
                    collections_updated = collections.len();
                    debug!(
                        collections_count = collections_updated,
                        "Processed collections from sync"
                    );
                }

                // Validate sync data
                if let Err(e) = self.validate_sync_data(&sync_data).await {
                    warn!(error = %e, "Sync validation failed");
                    errors.push(format!("Sync validation failed: {}", e));
                }

                let result = SyncResult {
                    success: errors.is_empty(),
                    revision_date: revision_date.clone(),
                    ciphers_updated,
                    folders_updated,
                    collections_updated,
                    errors: errors.clone(),
                };

                if result.success {
                    info!(
                        revision_date = revision_date,
                        ciphers_updated = ciphers_updated,
                        folders_updated = folders_updated,
                        collections_updated = collections_updated,
                        "Sync completed successfully"
                    );
                } else {
                    warn!(errors_count = errors.len(), "Sync completed with errors");
                }

                Ok(result)
            }
            Err(e) => {
                error!(error = %e, "Sync operation failed");
                errors.push(format!("Sync failed: {}", e));

                let result = SyncResult {
                    success: false,
                    revision_date: String::new(),
                    ciphers_updated: 0,
                    folders_updated: 0,
                    collections_updated: 0,
                    errors,
                };

                Ok(result)
            }
        }
    }

    /// Perform incremental sync (only changed items)
    pub async fn incremental_sync(
        &self,
        access_token: &str,
        last_revision: &str,
    ) -> AppResult<SyncResult> {
        let request = SyncRequest {
            access_token: access_token.to_string(),
            last_revision: Some(last_revision.to_string()),
            force_full_sync: false,
        };

        self.sync(request).await
    }

    /// Perform full sync (all items)
    pub async fn full_sync(&self, access_token: &str) -> AppResult<SyncResult> {
        let request = SyncRequest {
            access_token: access_token.to_string(),
            last_revision: None,
            force_full_sync: true,
        };

        self.sync(request).await
    }

    /// Check if sync is needed based on last revision
    pub async fn is_sync_needed(&self, access_token: &str, last_revision: &str) -> AppResult<bool> {
        // This is a simplified check - in a real implementation, you might
        // call a lightweight endpoint to check the current revision
        match self
            .vault_repository
            .sync_vault(access_token, Some(last_revision))
            .await
        {
            Ok(sync_data) => {
                let current_revision = sync_data
                    .get("RevisionDate")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");

                Ok(current_revision != last_revision)
            }
            Err(_) => Ok(true), // Assume sync is needed if we can't check
        }
    }

    /// Get sync status
    pub async fn get_sync_status(&self, _access_token: &str) -> AppResult<SyncStatus> {
        // In a real implementation, this would track sync state
        // For now, return a basic status
        Ok(SyncStatus {
            is_syncing: false,
            last_sync: Some(Utc::now().to_rfc3339()),
            next_sync: None,
            sync_errors: Vec::new(),
        })
    }

    /// Validate sync data integrity
    async fn validate_sync_data(&self, sync_data: &Value) -> AppResult<()> {
        // Validate required fields are present
        if sync_data.get("RevisionDate").is_none() {
            return Err(AppError::ValidationError {
                field: "RevisionDate".to_string(),
                message: "Missing RevisionDate in sync data".to_string(),
            });
        }

        // Validate ciphers structure
        if let Some(ciphers) = sync_data.get("Ciphers").and_then(|v| v.as_array()) {
            for cipher in ciphers {
                if cipher.get("Id").is_none() {
                    return Err(AppError::ValidationError {
                        field: "Cipher.Id".to_string(),
                        message: "Cipher missing required Id field".to_string(),
                    });
                }
                if cipher.get("Name").is_none() {
                    return Err(AppError::ValidationError {
                        field: "Cipher.Name".to_string(),
                        message: "Cipher missing required Name field".to_string(),
                    });
                }
            }
        }

        // Validate folders structure
        if let Some(folders) = sync_data.get("Folders").and_then(|v| v.as_array()) {
            for folder in folders {
                if folder.get("Id").is_none() {
                    return Err(AppError::ValidationError {
                        field: "Folder.Id".to_string(),
                        message: "Folder missing required Id field".to_string(),
                    });
                }
                if folder.get("Name").is_none() {
                    return Err(AppError::ValidationError {
                        field: "Folder.Name".to_string(),
                        message: "Folder missing required Name field".to_string(),
                    });
                }
            }
        }

        // Validate profile structure
        if let Some(profile) = sync_data.get("Profile") {
            if profile.get("Id").is_none() {
                return Err(AppError::ValidationError {
                    field: "Profile.Id".to_string(),
                    message: "Profile missing required Id field".to_string(),
                });
            }
        }

        Ok(())
    }

    /// Calculate sync priority based on data age and importance
    pub async fn calculate_sync_priority(&self, last_revision: Option<&str>) -> AppResult<u8> {
        match last_revision {
            None => Ok(10), // High priority for first sync
            Some(revision) => {
                // Parse revision date and calculate age
                match DateTime::parse_from_rfc3339(revision) {
                    Ok(last_sync) => {
                        let now = Utc::now();
                        let age = now.signed_duration_since(last_sync.with_timezone(&Utc));

                        // Priority based on age (0-10 scale)
                        let priority = if age.num_hours() > 24 {
                            10 // High priority if older than 24 hours
                        } else if age.num_hours() > 6 {
                            7 // Medium-high priority if older than 6 hours
                        } else if age.num_hours() > 1 {
                            5 // Medium priority if older than 1 hour
                        } else {
                            2 // Low priority if recent
                        };

                        Ok(priority)
                    }
                    Err(_) => Ok(8), // Medium-high priority for invalid dates
                }
            }
        }
    }
}
