use crate::app_state::AppState;
use crate::error::AppError;
use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::{command, State};
use tracing::{debug, error, info};

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SyncVaultRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct GetSyncStatusRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SyncStatusResponse {
    pub last_sync: Option<String>,
    pub is_syncing: bool,
    pub revision_date: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SyncResult {
    pub success: bool,
    pub last_sync: String,
    pub revision_date: Option<String>,
    pub message: String,
}

/// Sync vault data with server
/// Note: Access tokens are retrieved internally from secure storage
#[command]
#[specta::specta]
pub async fn sync_vault(
    request: SyncVaultRequest,
    state: State<'_, AppState>,
) -> Result<SyncResult, AppError> {
    info!(
        user_id = request.user_id,
        operation = "sync_vault",
        "Starting vault synchronization for user"
    );

    // Use sync service with automatic token refresh
    match state
        .sync_service()
        .sync_vault_with_auto_refresh(&request.user_id)
        .await
    {
        Ok(()) => {
            info!(
                user_id = request.user_id,
                operation = "sync_vault",
                "Vault synchronization completed successfully"
            );

            // Get updated sync state to return current status
            let sync_state = state
                .database()
                .get_sync_state(&request.user_id)
                .await
                .unwrap_or(None);

            let last_sync = sync_state
                .as_ref()
                .and_then(|s| s.last_sync)
                .map(|dt| dt.to_rfc3339())
                .unwrap_or_else(|| chrono::Utc::now().to_rfc3339());

            let revision_date = sync_state
                .and_then(|s| s.revision_date)
                .map(|dt| dt.to_rfc3339());

            Ok(SyncResult {
                success: true,
                last_sync,
                revision_date,
                message: "Vault synchronized successfully".to_string(),
            })
        }
        Err(e) => {
            error!(
                user_id = request.user_id,
                operation = "sync_vault",
                error = %e,
                "Vault synchronization failed"
            );

            Err(AppError::SyncError {
                message: format!("Sync failed: {}", e),
            })
        }
    }
}

/// Get sync status for a user
#[command]
#[specta::specta]
pub async fn get_sync_status(
    request: GetSyncStatusRequest,
    state: State<'_, AppState>,
) -> Result<SyncStatusResponse, AppError> {
    debug!(
        user_id = request.user_id,
        operation = "get_sync_status",
        "Getting sync status for user"
    );

    match state.database().get_sync_state(&request.user_id).await {
        Ok(sync_state) => {
            let last_sync = sync_state
                .as_ref()
                .and_then(|s| s.last_sync)
                .map(|dt| dt.to_rfc3339());

            let revision_date = sync_state
                .and_then(|s| s.revision_date)
                .map(|dt| dt.to_rfc3339());

            debug!(
                user_id = request.user_id,
                has_last_sync = last_sync.is_some(),
                has_revision_date = revision_date.is_some(),
                "Retrieved sync status successfully"
            );

            Ok(SyncStatusResponse {
                last_sync,
                is_syncing: false, // TODO: Implement actual sync state tracking
                revision_date,
            })
        }
        Err(e) => {
            error!(
                user_id = request.user_id,
                operation = "get_sync_status",
                error = %e,
                "Failed to get sync status"
            );

            Err(AppError::DatabaseError {
                message: format!("Failed to get sync status: {}", e),
            })
        }
    }
}
