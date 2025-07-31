use crate::error::{AppError, AppResult};
use crate::logging::{
    log_websocket_accept, log_websocket_close, log_websocket_error, log_websocket_receive,
};
use crate::services::{NetworkMonitorService, ServerProviderService, SyncStateManager};
use chrono::{DateTime, Utc};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use specta::Type;
use std::sync::Arc;
use std::time::Duration;
use tauri::{AppHandle, Emitter};
use tokio::sync::{broadcast, RwLock};
use tokio::time::interval;
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, error, info, warn};

/// WebSocket connection state
#[derive(Debug, Clone, Serialize, Deserialize, Type, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum WebSocketState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Error,
}

impl std::fmt::Display for WebSocketState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WebSocketState::Disconnected => write!(f, "disconnected"),
            WebSocketState::Connecting => write!(f, "connecting"),
            WebSocketState::Connected => write!(f, "connected"),
            WebSocketState::Reconnecting => write!(f, "reconnecting"),
            WebSocketState::Error => write!(f, "error"),
        }
    }
}

/// Update type enumeration for WebSocket notifications
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Type, PartialEq, Eq)]
#[repr(u32)]
pub enum UpdateType {
    SyncCipherUpdate = 0,
    SyncCipherCreate = 1,
    SyncLoginDelete = 2,
    SyncFolderDelete = 3,
    SyncCiphers = 4,
    SyncVault = 5,
    SyncOrgKeys = 6,
    SyncFolderCreate = 7,
    SyncFolderUpdate = 8,
    SyncCipherDelete = 9,
    LogOut = 11,
    SyncSendCreate = 12,
    SyncSendUpdate = 13,
    SyncSendDelete = 14,
    AuthRequest = 15,
    AuthRequestResponse = 16,
    None = 100, // Unknown or unhandled notification type
}

impl UpdateType {
    /// Convert from u32 value
    pub fn from_u32(value: u32) -> Option<Self> {
        match value {
            0 => Some(UpdateType::SyncCipherUpdate),
            1 => Some(UpdateType::SyncCipherCreate),
            2 => Some(UpdateType::SyncLoginDelete),
            3 => Some(UpdateType::SyncFolderDelete),
            4 => Some(UpdateType::SyncCiphers),
            5 => Some(UpdateType::SyncVault),
            6 => Some(UpdateType::SyncOrgKeys),
            7 => Some(UpdateType::SyncFolderCreate),
            8 => Some(UpdateType::SyncFolderUpdate),
            9 => Some(UpdateType::SyncCipherDelete),
            11 => Some(UpdateType::LogOut),
            12 => Some(UpdateType::SyncSendCreate),
            13 => Some(UpdateType::SyncSendUpdate),
            14 => Some(UpdateType::SyncSendDelete),
            15 => Some(UpdateType::AuthRequest),
            16 => Some(UpdateType::AuthRequestResponse),
            100 => Some(UpdateType::None),
            _ => Some(UpdateType::None), // Default to None for unknown types
        }
    }

    /// Get human-readable description
    pub fn description(&self) -> &'static str {
        match self {
            UpdateType::SyncCipherUpdate => "Cipher updated",
            UpdateType::SyncCipherCreate => "Cipher created",
            UpdateType::SyncLoginDelete => "Login deleted",
            UpdateType::SyncFolderDelete => "Folder deleted",
            UpdateType::SyncCiphers => "Bulk cipher sync",
            UpdateType::SyncVault => "Full vault sync",
            UpdateType::SyncOrgKeys => "Organization keys updated",
            UpdateType::SyncFolderCreate => "Folder created",
            UpdateType::SyncFolderUpdate => "Folder updated",
            UpdateType::SyncCipherDelete => "Cipher deleted",
            UpdateType::LogOut => "User logged out",
            UpdateType::SyncSendCreate => "Send created",
            UpdateType::SyncSendUpdate => "Send updated",
            UpdateType::SyncSendDelete => "Send deleted",
            UpdateType::AuthRequest => "Authentication request",
            UpdateType::AuthRequestResponse => "Authentication response",
            UpdateType::None => "Unknown notification",
        }
    }
}

/// WebSocket notification payload data
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct NotificationPayload {
    pub id: Option<String>,
    pub user_id: Option<String>,
    pub organization_id: Option<String>,
    pub revision_date: Option<String>,
    pub data: Option<String>, // Store as JSON string instead of serde_json::Value
}

/// Comprehensive WebSocket notification from Vaultwarden server
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct WebSocketNotification {
    pub update_type: UpdateType,
    pub payload: NotificationPayload,
    pub timestamp: String,
}

/// WebSocket connection status
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct WebSocketStatus {
    pub state: WebSocketState,
    pub connected_at: Option<DateTime<Utc>>,
    pub last_ping: Option<DateTime<Utc>>,
    pub last_pong: Option<DateTime<Utc>>,
    pub reconnect_count: u32,
    pub error_message: Option<String>,
    pub server_url: Option<String>,
}

impl Default for WebSocketStatus {
    fn default() -> Self {
        Self {
            state: WebSocketState::Disconnected,
            connected_at: None,
            last_ping: None,
            last_pong: None,
            reconnect_count: 0,
            error_message: None,
            server_url: None,
        }
    }
}

/// WebSocket service for real-time notifications
pub struct WebSocketService {
    app_handle: AppHandle,
    server_provider_service: Arc<ServerProviderService>,
    network_monitor: Arc<NetworkMonitorService>,
    sync_state_manager: Arc<SyncStateManager>,
    status: Arc<RwLock<WebSocketStatus>>,
    notification_sender: broadcast::Sender<WebSocketNotification>,
    connection_enabled: Arc<RwLock<bool>>,
    current_user_id: Arc<RwLock<Option<String>>>,
    access_token: Arc<RwLock<Option<String>>>,
}

impl WebSocketService {
    /// Create a new WebSocket service
    pub fn new(
        app_handle: AppHandle,
        server_provider_service: Arc<ServerProviderService>,
        network_monitor: Arc<NetworkMonitorService>,
        sync_state_manager: Arc<SyncStateManager>,
    ) -> Self {
        let (notification_sender, _) = broadcast::channel(1000);

        Self {
            app_handle,
            server_provider_service,
            network_monitor,
            sync_state_manager,
            status: Arc::new(RwLock::new(WebSocketStatus::default())),
            notification_sender,
            connection_enabled: Arc::new(RwLock::new(false)),
            current_user_id: Arc::new(RwLock::new(None)),
            access_token: Arc::new(RwLock::new(None)),
        }
    }

    /// Start WebSocket connection for a user
    pub async fn connect(&self, user_id: String, access_token: String) -> AppResult<()> {
        info!(user_id = %user_id, "[websocket] Starting WebSocket connection");

        // Store user credentials
        {
            let mut current_user = self.current_user_id.write().await;
            *current_user = Some(user_id.clone());
        }
        {
            let mut token = self.access_token.write().await;
            *token = Some(access_token);
        }

        // Enable connection
        {
            let mut enabled = self.connection_enabled.write().await;
            *enabled = true;
        }

        // Check if network is online
        if !self.network_monitor.is_online().await {
            warn!(user_id = %user_id, "[websocket] Cannot connect - network is offline");
            return Ok(()); // Don't error, just wait for network
        }

        // Start connection management task
        self.start_connection_manager().await?;

        Ok(())
    }

    /// Disconnect WebSocket
    pub async fn disconnect(&self) -> AppResult<()> {
        info!("[websocket] Disconnecting WebSocket");

        // Disable connection
        {
            let mut enabled = self.connection_enabled.write().await;
            *enabled = false;
        }

        // Clear credentials
        {
            let mut current_user = self.current_user_id.write().await;
            *current_user = None;
        }
        {
            let mut token = self.access_token.write().await;
            *token = None;
        }

        // Update status
        {
            let mut status = self.status.write().await;
            status.state = WebSocketState::Disconnected;
            status.connected_at = None;
            status.error_message = None;
        }

        Ok(())
    }

    /// Get current WebSocket status
    pub async fn get_status(&self) -> WebSocketStatus {
        self.status.read().await.clone()
    }

    /// Subscribe to WebSocket notifications
    pub fn subscribe(&self) -> broadcast::Receiver<WebSocketNotification> {
        self.notification_sender.subscribe()
    }

    /// Check if WebSocket is connected
    pub async fn is_connected(&self) -> bool {
        let status = self.status.read().await;
        status.state == WebSocketState::Connected
    }

    /// Start connection management task
    async fn start_connection_manager(&self) -> AppResult<()> {
        let app_handle = self.app_handle.clone();
        let server_provider_service = Arc::clone(&self.server_provider_service);
        let network_monitor = Arc::clone(&self.network_monitor);
        let sync_state_manager = Arc::clone(&self.sync_state_manager);
        let status = Arc::clone(&self.status);
        let notification_sender = self.notification_sender.clone();
        let connection_enabled = Arc::clone(&self.connection_enabled);
        let current_user_id = Arc::clone(&self.current_user_id);
        let access_token = Arc::clone(&self.access_token);

        tokio::spawn(async move {
            let mut reconnect_interval = interval(Duration::from_secs(5));
            let mut network_receiver = network_monitor.subscribe();

            loop {
                // Check if connection is still enabled
                if !*connection_enabled.read().await {
                    debug!("[websocket] Connection disabled, stopping manager");
                    break;
                }

                // Check network status
                let _network_status = network_monitor.get_status().await;
                if !network_monitor.is_online().await {
                    debug!("[websocket] Network offline, waiting for connectivity");

                    // Wait for network to come back online
                    while let Ok(_status) = network_receiver.recv().await {
                        if network_monitor.is_online().await {
                            info!("[websocket] Network back online, attempting reconnection");
                            break;
                        }
                    }
                    continue;
                }

                // Get current credentials
                let (user_id, token) = {
                    let user_guard = current_user_id.read().await;
                    let token_guard = access_token.read().await;
                    match (user_guard.as_ref(), token_guard.as_ref()) {
                        (Some(user), Some(token)) => (user.clone(), token.clone()),
                        _ => {
                            debug!(
                                "[websocket] No credentials available, stopping connection manager"
                            );
                            break;
                        }
                    }
                };

                // Check current connection status
                let current_state = {
                    let status_guard = status.read().await;
                    status_guard.state.clone()
                };

                match current_state {
                    WebSocketState::Disconnected | WebSocketState::Error => {
                        info!(user_id = %user_id, "[websocket] Attempting to connect");

                        if let Err(e) = Self::establish_connection(
                            &app_handle,
                            &server_provider_service,
                            &sync_state_manager,
                            &status,
                            &notification_sender,
                            &user_id,
                            &token,
                        )
                        .await
                        {
                            error!(user_id = %user_id, error = %e, "[websocket] Connection failed");

                            // Update status to error
                            {
                                let mut status_guard = status.write().await;
                                status_guard.state = WebSocketState::Error;
                                status_guard.error_message = Some(e.to_string());
                                status_guard.reconnect_count += 1;
                            }
                        }
                    }
                    WebSocketState::Connected => {
                        // Connection is healthy, just wait
                        reconnect_interval.tick().await;
                        continue;
                    }
                    _ => {
                        // Connecting or reconnecting, wait
                        reconnect_interval.tick().await;
                        continue;
                    }
                }

                // Wait before next attempt
                reconnect_interval.tick().await;
            }

            info!("[websocket] Connection manager stopped");
        });

        Ok(())
    }

    /// Establish WebSocket connection
    async fn establish_connection(
        app_handle: &AppHandle,
        server_provider_service: &ServerProviderService,
        sync_state_manager: &Arc<SyncStateManager>,
        status: &Arc<RwLock<WebSocketStatus>>,
        notification_sender: &broadcast::Sender<WebSocketNotification>,
        user_id: &str,
        access_token: &str,
    ) -> AppResult<()> {
        // Update status to connecting
        {
            let mut status_guard = status.write().await;
            status_guard.state = WebSocketState::Connecting;
            status_guard.error_message = None;
        }

        // Get WebSocket URL
        let base_url = server_provider_service.get_api_url().await;
        let ws_url = base_url
            .replace("http://", "ws://")
            .replace("https://", "wss://");
        let notifications_url =
            format!("{}/notifications/hub?access_token={}", ws_url, access_token);

        debug!(user_id = %user_id, url = %notifications_url, "[websocket] Connecting to WebSocket");

        // Attempt connection
        let (ws_stream, _) =
            connect_async(&notifications_url)
                .await
                .map_err(|e| AppError::NetworkError {
                    status: 0,
                    message: format!("WebSocket connection failed: {}", e),
                })?;

        log_websocket_accept("127.0.0.1", Some("Chiikawarden/1.0.0"));

        // Update status to connected
        {
            let mut status_guard = status.write().await;
            status_guard.state = WebSocketState::Connected;
            status_guard.connected_at = Some(Utc::now());
            status_guard.server_url = Some(notifications_url.clone());
            status_guard.error_message = None;

            // Emit status change event
            if let Err(e) = app_handle.emit("websocket_status_changed", &*status_guard) {
                warn!("[websocket] Failed to emit status change event: {}", e);
            }
        }

        // Update sync state
        if let Ok(Some(mut sync_state)) = sync_state_manager.get_sync_state(user_id).await {
            sync_state.websocket_connected = true;
            sync_state.last_websocket_connection = Some(Utc::now());
            let _ = sync_state_manager.update_sync_state(&sync_state).await;
        }

        info!(user_id = %user_id, "[websocket] WebSocket connected successfully");

        // Emit connection event
        if let Err(e) = app_handle.emit("websocket_connected", user_id) {
            warn!("[websocket] Failed to emit connection event: {}", e);
        }

        // Handle messages
        let (mut ws_sender, mut ws_receiver) = ws_stream.split();
        let app_handle_clone = app_handle.clone();
        let notification_sender_clone = notification_sender.clone();
        let sync_state_manager_clone = Arc::clone(sync_state_manager);
        let status_clone = Arc::clone(status);
        let user_id_clone = user_id.to_string();

        tokio::spawn(async move {
            while let Some(message) = ws_receiver.next().await {
                match message {
                    Ok(Message::Text(text)) => {
                        log_websocket_receive("127.0.0.1", "notification", text.len());

                        if let Err(e) = Self::handle_notification(
                            &app_handle_clone,
                            &sync_state_manager_clone,
                            &notification_sender_clone,
                            &user_id_clone,
                            &text,
                        )
                        .await
                        {
                            error!(user_id = %user_id_clone, error = %e, "[websocket] Failed to handle notification");
                        }
                    }
                    Ok(Message::Ping(data)) => {
                        log_websocket_receive("127.0.0.1", "ping", data.len());

                        // Respond with pong
                        if let Err(e) = ws_sender.send(Message::Pong(data)).await {
                            error!(user_id = %user_id_clone, error = %e, "[websocket] Failed to send pong");
                            break;
                        }

                        // Update last ping time
                        {
                            let mut status_guard = status_clone.write().await;
                            status_guard.last_ping = Some(Utc::now());
                        }
                    }
                    Ok(Message::Pong(_)) => {
                        // Update last pong time
                        {
                            let mut status_guard = status_clone.write().await;
                            status_guard.last_pong = Some(Utc::now());
                        }
                    }
                    Ok(Message::Close(_)) => {
                        info!(user_id = %user_id_clone, "[websocket] WebSocket closed by server");
                        break;
                    }
                    Err(e) => {
                        error!(user_id = %user_id_clone, error = %e, "[websocket] WebSocket error");
                        log_websocket_error("127.0.0.1", &e.to_string());
                        break;
                    }
                    _ => {}
                }
            }

            // Connection closed
            {
                let mut status_guard = status_clone.write().await;
                status_guard.state = WebSocketState::Disconnected;
                status_guard.connected_at = None;
            }

            // Update sync state
            if let Ok(Some(mut sync_state)) = sync_state_manager_clone
                .get_sync_state(&user_id_clone)
                .await
            {
                sync_state.websocket_connected = false;
                let _ = sync_state_manager_clone
                    .update_sync_state(&sync_state)
                    .await;
            }

            log_websocket_close("127.0.0.1", Some("connection_closed"), None);

            if let Err(e) = app_handle_clone.emit("websocket_disconnected", &user_id_clone) {
                warn!("[websocket] Failed to emit disconnection event: {}", e);
            }
        });

        Ok(())
    }

    /// Handle incoming WebSocket notification
    async fn handle_notification(
        app_handle: &AppHandle,
        sync_state_manager: &SyncStateManager,
        notification_sender: &broadcast::Sender<WebSocketNotification>,
        user_id: &str,
        message: &str,
    ) -> AppResult<()> {
        debug!(user_id = %user_id, message = %message, "[websocket] Received notification");

        // Parse the incoming message as JSON
        let parsed_message: serde_json::Value =
            serde_json::from_str(message).map_err(|e| AppError::InternalError {
                message: format!("Failed to parse WebSocket message: {}", e),
            })?;

        // Extract notification data
        let notification = Self::parse_notification(&parsed_message)?;

        // Send notification to subscribers
        if let Err(e) = notification_sender.send(notification.clone()) {
            warn!("[websocket] Failed to broadcast notification: {}", e);
        }

        // Emit notification event to frontend
        if let Err(e) = app_handle.emit("websocket_notification", &notification) {
            warn!("[websocket] Failed to emit notification event: {}", e);
        }

        // Handle specific notification types
        Self::handle_notification_type(app_handle, sync_state_manager, user_id, &notification)
            .await?;

        // Update last server notification time
        if let Ok(Some(mut sync_state)) = sync_state_manager.get_sync_state(user_id).await {
            sync_state.last_server_notification = Some(Utc::now());
            sync_state_manager.update_sync_state(&sync_state).await?;
        }

        Ok(())
    }

    /// Parse raw WebSocket message into structured notification
    fn parse_notification(message: &serde_json::Value) -> AppResult<WebSocketNotification> {
        // Extract type field
        let type_value = message
            .get("Type")
            .or_else(|| message.get("type"))
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AppError::InternalError {
                message: "Missing or invalid 'Type' field in WebSocket message".to_string(),
            })? as u32;

        let update_type =
            UpdateType::from_u32(type_value).ok_or_else(|| AppError::InternalError {
                message: format!("Unknown notification type: {}", type_value),
            })?;

        // Extract payload data
        let payload = NotificationPayload {
            id: message
                .get("Id")
                .or_else(|| message.get("id"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
            user_id: message
                .get("UserId")
                .or_else(|| message.get("user_id"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
            organization_id: message
                .get("OrganizationId")
                .or_else(|| message.get("organization_id"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
            revision_date: message
                .get("RevisionDate")
                .or_else(|| message.get("revision_date"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
            data: message
                .get("Data")
                .or_else(|| message.get("data"))
                .and_then(|v| serde_json::to_string(v).ok()),
        };

        Ok(WebSocketNotification {
            update_type,
            payload,
            timestamp: Utc::now().to_rfc3339(),
        })
    }

    /// Handle specific notification types with appropriate actions
    async fn handle_notification_type(
        app_handle: &AppHandle,
        sync_state_manager: &SyncStateManager,
        user_id: &str,
        notification: &WebSocketNotification,
    ) -> AppResult<()> {
        let event_name = match notification.update_type {
            UpdateType::SyncCipherUpdate | UpdateType::SyncCipherCreate => {
                info!(user_id = %user_id, cipher_id = ?notification.payload.id,
                      "[websocket] Cipher {} notification", notification.update_type.description());
                "cipher_changed"
            }
            UpdateType::SyncCipherDelete => {
                info!(user_id = %user_id, cipher_id = ?notification.payload.id,
                      "[websocket] Cipher deleted notification");
                "cipher_deleted"
            }
            UpdateType::SyncFolderCreate | UpdateType::SyncFolderUpdate => {
                info!(user_id = %user_id, folder_id = ?notification.payload.id,
                      "[websocket] Folder {} notification", notification.update_type.description());
                "folder_changed"
            }
            UpdateType::SyncFolderDelete => {
                info!(user_id = %user_id, folder_id = ?notification.payload.id,
                      "[websocket] Folder deleted notification");
                "folder_deleted"
            }
            UpdateType::SyncVault => {
                info!(user_id = %user_id, "[websocket] Full vault sync notification");
                "vault_sync_required"
            }
            UpdateType::SyncCiphers => {
                info!(user_id = %user_id, "[websocket] Bulk cipher sync notification");
                "ciphers_sync_required"
            }
            UpdateType::SyncOrgKeys => {
                info!(user_id = %user_id, org_id = ?notification.payload.organization_id,
                      "[websocket] Organization keys updated");
                "org_keys_changed"
            }
            UpdateType::LogOut => {
                warn!(user_id = %user_id, "[websocket] Logout notification received");
                "force_logout"
            }
            UpdateType::SyncSendCreate | UpdateType::SyncSendUpdate => {
                info!(user_id = %user_id, send_id = ?notification.payload.id,
                      "[websocket] Send {} notification", notification.update_type.description());
                "send_changed"
            }
            UpdateType::SyncSendDelete => {
                info!(user_id = %user_id, send_id = ?notification.payload.id,
                      "[websocket] Send deleted notification");
                "send_deleted"
            }
            UpdateType::AuthRequest => {
                info!(user_id = %user_id, "[websocket] Authentication request notification");
                "auth_request"
            }
            UpdateType::AuthRequestResponse => {
                info!(user_id = %user_id, "[websocket] Authentication response notification");
                "auth_response"
            }
            UpdateType::SyncLoginDelete => {
                info!(user_id = %user_id, "[websocket] Login deleted notification");
                "login_deleted"
            }
            UpdateType::None => {
                warn!(user_id = %user_id, "[websocket] Unknown notification type received");
                "unknown_notification"
            }
        };

        // Emit specific event
        if let Err(e) = app_handle.emit(event_name, notification) {
            warn!("[websocket] Failed to emit {} event: {}", event_name, e);
        }

        // Also emit generic vault change event for UI updates
        if let Err(e) = app_handle.emit("vault_changed", user_id) {
            warn!("[websocket] Failed to emit vault change event: {}", e);
        }

        // Trigger sync state updates based on notification type
        Self::update_sync_state_for_notification(sync_state_manager, user_id, notification).await?;

        Ok(())
    }

    /// Update sync state based on notification type
    async fn update_sync_state_for_notification(
        sync_state_manager: &SyncStateManager,
        user_id: &str,
        notification: &WebSocketNotification,
    ) -> AppResult<()> {
        if let Ok(Some(mut sync_state)) = sync_state_manager.get_sync_state(user_id).await {
            match notification.update_type {
                UpdateType::SyncVault | UpdateType::SyncCiphers => {
                    // Update last sync timestamp for full vault sync
                    sync_state.last_sync = Some(Utc::now());
                    sync_state.last_server_notification = Some(Utc::now());
                }
                UpdateType::SyncCipherUpdate
                | UpdateType::SyncCipherCreate
                | UpdateType::SyncCipherDelete => {
                    // Update sync timestamp for cipher changes
                    sync_state.last_sync = Some(Utc::now());
                    sync_state.last_server_notification = Some(Utc::now());
                }
                UpdateType::SyncFolderCreate
                | UpdateType::SyncFolderUpdate
                | UpdateType::SyncFolderDelete => {
                    // Update sync timestamp for folder changes
                    sync_state.last_sync = Some(Utc::now());
                    sync_state.last_server_notification = Some(Utc::now());
                }
                UpdateType::LogOut => {
                    // Clear sync state on logout
                    sync_state.websocket_connected = false;
                    sync_state.last_server_notification = Some(Utc::now());
                }
                _ => {
                    // Update general notification timestamp
                    sync_state.last_server_notification = Some(Utc::now());
                }
            }

            sync_state_manager.update_sync_state(&sync_state).await?;
        }

        Ok(())
    }
}
