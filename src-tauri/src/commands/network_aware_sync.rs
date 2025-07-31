use crate::app_state::AppState;
use crate::error::AppError;
use crate::models::SyncMode;
use crate::services::{
    NetworkAwareSyncResult, NetworkStatus, NotificationPayload, UpdateType, WebSocketNotification,
    WebSocketStatus,
};
use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::{command, State};
use tracing::{debug, error, info};

// Request/Response types for network-aware sync commands

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct NetworkAwareSyncRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct ForceOnlineSyncRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct GetNetworkStatusRequest {}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct GetSyncModeRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SetSyncModeRequest {
    pub user_id: String,
    pub mode: SyncMode,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct ConnectWebSocketRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct GetWebSocketStatusRequest {}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct CanWriteRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct CanWriteResponse {
    pub can_write: bool,
    pub sync_mode: SyncMode,
    pub reason: String,
}

/// Network-aware vault synchronization with automatic mode detection
#[command]
#[specta::specta]
pub async fn network_aware_sync_vault(
    request: NetworkAwareSyncRequest,
    state: State<'_, AppState>,
) -> Result<NetworkAwareSyncResult, AppError> {
    info!(
        user_id = request.user_id,
        operation = "network_aware_sync_vault",
        "Starting network-aware vault synchronization"
    );

    // Perform network-aware sync with auto-refresh
    match state
        .network_aware_sync_service()
        .sync_vault_with_auto_refresh(&request.user_id)
        .await
    {
        Ok(result) => {
            info!(
                user_id = request.user_id,
                sync_mode = %result.sync_mode,
                success = result.success,
                "Network-aware vault synchronization completed"
            );
            Ok(result)
        }
        Err(e) => {
            error!(
                user_id = request.user_id,
                error = %e,
                "Network-aware vault synchronization failed"
            );
            Err(e)
        }
    }
}

/// Force online synchronization (will fail if network is unavailable)
#[command]
#[specta::specta]
pub async fn force_online_sync(
    request: ForceOnlineSyncRequest,
    state: State<'_, AppState>,
) -> Result<NetworkAwareSyncResult, AppError> {
    info!(
        user_id = request.user_id,
        operation = "force_online_sync",
        "Forcing online vault synchronization"
    );

    // Force online sync with auto-refresh
    match state
        .network_aware_sync_service()
        .force_online_sync_with_auto_refresh(&request.user_id)
        .await
    {
        Ok(result) => {
            info!(
                user_id = request.user_id,
                "Forced online synchronization completed successfully"
            );
            Ok(result)
        }
        Err(e) => {
            error!(
                user_id = request.user_id,
                error = %e,
                "Forced online synchronization failed"
            );
            Err(e)
        }
    }
}

/// Get current network status
#[command]
#[specta::specta]
pub async fn get_network_status(
    _request: GetNetworkStatusRequest,
    state: State<'_, AppState>,
) -> Result<NetworkStatus, AppError> {
    debug!("Getting network status");

    let status = state.network_monitor().get_status().await;

    debug!(
        network_state = %status.state,
        server_reachable = status.server_reachable,
        "Retrieved network status"
    );

    Ok(status)
}

/// Get sync status with network awareness
#[command]
#[specta::specta]
pub async fn get_network_aware_sync_status(
    request: NetworkAwareSyncRequest,
    state: State<'_, AppState>,
) -> Result<NetworkAwareSyncResult, AppError> {
    debug!(
        user_id = request.user_id,
        operation = "get_network_aware_sync_status",
        "Getting network-aware sync status"
    );

    match state
        .network_aware_sync_service()
        .get_sync_status(&request.user_id)
        .await
    {
        Ok(status) => {
            debug!(
                user_id = request.user_id,
                sync_mode = %status.sync_mode,
                network_state = %status.network_state,
                "Retrieved network-aware sync status"
            );
            Ok(status)
        }
        Err(e) => {
            error!(
                user_id = request.user_id,
                error = %e,
                "Failed to get network-aware sync status"
            );
            Err(e)
        }
    }
}

/// Get current sync mode for a user
#[command]
#[specta::specta]
pub async fn get_sync_mode(
    request: GetSyncModeRequest,
    state: State<'_, AppState>,
) -> Result<SyncMode, AppError> {
    debug!(
        user_id = request.user_id,
        operation = "get_sync_mode",
        "Getting sync mode for user"
    );

    match state
        .sync_state_manager()
        .get_sync_state(&request.user_id)
        .await
    {
        Ok(Some(sync_state)) => {
            debug!(
                user_id = request.user_id,
                sync_mode = %sync_state.sync_mode,
                "Retrieved sync mode"
            );
            Ok(sync_state.sync_mode)
        }
        Ok(None) => {
            debug!(
                user_id = request.user_id,
                "No sync state found, defaulting to offline mode"
            );
            Ok(SyncMode::Offline)
        }
        Err(e) => {
            error!(
                user_id = request.user_id,
                error = %e,
                "Failed to get sync mode"
            );
            Err(e)
        }
    }
}

/// Set sync mode for a user (with network validation)
#[command]
#[specta::specta]
pub async fn set_sync_mode(
    request: SetSyncModeRequest,
    state: State<'_, AppState>,
) -> Result<SyncMode, AppError> {
    info!(
        user_id = request.user_id,
        requested_mode = %request.mode,
        operation = "set_sync_mode",
        "Setting sync mode for user"
    );

    match state
        .sync_state_manager()
        .set_sync_mode(&request.user_id, request.mode)
        .await
    {
        Ok(actual_mode) => {
            info!(
                user_id = request.user_id,
                actual_mode = %actual_mode,
                "Sync mode set successfully"
            );
            Ok(actual_mode)
        }
        Err(e) => {
            error!(
                user_id = request.user_id,
                error = %e,
                "Failed to set sync mode"
            );
            Err(e)
        }
    }
}

/// Connect WebSocket for real-time notifications
#[command]
#[specta::specta]
pub async fn connect_websocket(
    request: ConnectWebSocketRequest,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    info!(
        user_id = request.user_id,
        operation = "connect_websocket",
        "Connecting WebSocket for user"
    );

    // Get access token using TokenManager
    let access_token = {
        let token_manager = state.token_manager();
        let token_manager = token_manager.read().await;

        match token_manager.retrieve_access_token(&request.user_id).await {
            Ok(Some(token)) => token,
            Ok(None) => {
                return Err(AppError::AuthenticationError {
                    message: "No access token found for user".to_string(),
                });
            }
            Err(e) => {
                error!(
                    user_id = request.user_id,
                    error = %e,
                    "Failed to retrieve access token for WebSocket using TokenManager"
                );
                return Err(AppError::AuthenticationError {
                    message: "Failed to retrieve access token".to_string(),
                });
            }
        }
    };

    // Connect WebSocket
    match state
        .websocket_service()
        .connect(request.user_id.clone(), access_token)
        .await
    {
        Ok(()) => {
            info!(
                user_id = request.user_id,
                "WebSocket connection initiated successfully"
            );
            Ok(())
        }
        Err(e) => {
            error!(
                user_id = request.user_id,
                error = %e,
                "Failed to connect WebSocket"
            );
            Err(e)
        }
    }
}

/// Disconnect WebSocket
#[command]
#[specta::specta]
pub async fn disconnect_websocket(
    _request: GetWebSocketStatusRequest,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    info!(
        operation = "disconnect_websocket",
        "Disconnecting WebSocket"
    );

    match state.websocket_service().disconnect().await {
        Ok(()) => {
            info!("WebSocket disconnected successfully");
            Ok(())
        }
        Err(e) => {
            error!(error = %e, "Failed to disconnect WebSocket");
            Err(e)
        }
    }
}

/// Get WebSocket connection status
#[command]
#[specta::specta]
pub async fn get_websocket_status(
    _request: GetWebSocketStatusRequest,
    state: State<'_, AppState>,
) -> Result<WebSocketStatus, AppError> {
    debug!(
        operation = "get_websocket_status",
        "Getting WebSocket status"
    );

    let status = state.websocket_service().get_status().await;

    debug!(
        websocket_state = %status.state,
        connected = %status.connected_at.is_some(),
        "Retrieved WebSocket status"
    );

    Ok(status)
}

/// Check if user can perform write operations
#[command]
#[specta::specta]
pub async fn can_write(
    request: CanWriteRequest,
    state: State<'_, AppState>,
) -> Result<CanWriteResponse, AppError> {
    debug!(
        user_id = request.user_id,
        operation = "can_write",
        "Checking write permissions for user"
    );

    let can_write = state
        .network_aware_sync_service()
        .can_write(&request.user_id)
        .await?;

    let sync_mode = match state
        .sync_state_manager()
        .get_sync_state(&request.user_id)
        .await?
    {
        Some(state) => state.sync_mode,
        None => SyncMode::Offline,
    };

    let reason = match (can_write, &sync_mode) {
        (true, SyncMode::Online) => "Online mode - full access available".to_string(),
        (false, SyncMode::Offline) => "Offline mode - read-only access only".to_string(),
        _ => "Unknown state".to_string(),
    };

    let response = CanWriteResponse {
        can_write,
        sync_mode: sync_mode.clone(),
        reason,
    };

    debug!(
        user_id = request.user_id,
        can_write = can_write,
        sync_mode = %sync_mode,
        "Write permissions checked"
    );

    Ok(response)
}

/// Get WebSocket notification types (for TypeScript type generation)
/// This command exists solely to ensure WebSocket notification types are exported to TypeScript
#[command]
#[specta::specta]
pub async fn get_websocket_notification_types() -> Result<WebSocketNotificationTypes, AppError> {
    // This is a dummy command that returns example types to ensure they're exported
    Ok(WebSocketNotificationTypes {
        notification: WebSocketNotification {
            update_type: UpdateType::SyncVault,
            payload: NotificationPayload {
                id: Some("example-id".to_string()),
                user_id: Some("example-user-id".to_string()),
                organization_id: None,
                revision_date: Some("2024-01-01T00:00:00Z".to_string()),
                data: Some("{}".to_string()),
            },
            timestamp: "2024-01-01T00:00:00Z".to_string(),
        },
        update_types: vec![
            UpdateType::SyncCipherUpdate,
            UpdateType::SyncCipherCreate,
            UpdateType::SyncLoginDelete,
            UpdateType::SyncFolderDelete,
            UpdateType::SyncCiphers,
            UpdateType::SyncVault,
            UpdateType::SyncOrgKeys,
            UpdateType::SyncFolderCreate,
            UpdateType::SyncFolderUpdate,
            UpdateType::SyncCipherDelete,
            UpdateType::SyncSendCreate,
            UpdateType::SyncSendUpdate,
            UpdateType::SyncSendDelete,
            UpdateType::AuthRequest,
            UpdateType::AuthRequestResponse,
            UpdateType::LogOut,
            UpdateType::None,
        ],
    })
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct WebSocketNotificationTypes {
    pub notification: WebSocketNotification,
    pub update_types: Vec<UpdateType>,
}
