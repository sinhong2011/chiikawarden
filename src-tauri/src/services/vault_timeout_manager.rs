use crate::error::{AppError, AppResult};
use crate::models::settings::VaultTimeout;
use crate::services::activity_detection::{ActivityDetectionService, ActivityEvent};
use serde::{Deserialize, Serialize};
use specta::Type;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter};
use tokio::sync::{broadcast, RwLock};
use tracing::{debug, error, info, warn};

/// Events emitted by the vault timeout manager
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub enum VaultTimeoutEvent {
    /// Vault should be locked due to timeout
    VaultLockTriggered {
        user_id: String,
        reason: LockReason,
    },
    /// Timeout timer was reset due to activity
    TimeoutReset {
        user_id: String,
        remaining_ms: u32,
    },
    /// Timeout monitoring started
    MonitoringStarted {
        user_id: String,
        timeout_ms: u32,
    },
    /// Timeout monitoring stopped
    MonitoringStopped {
        user_id: String,
    },
}

/// Reasons why the vault was locked
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub enum LockReason {
    /// User inactivity timeout
    InactivityTimeout,
    /// Manual lock request
    ManualLock,
    /// System event (sleep, shutdown, etc.)
    SystemEvent,
}

/// Configuration for vault timeout management
#[derive(Debug, Clone)]
pub struct VaultTimeoutConfig {
    pub timeout: VaultTimeout,
    pub enabled: bool,
}

impl Default for VaultTimeoutConfig {
    fn default() -> Self {
        Self {
            timeout: VaultTimeout::default(), // 15 minutes
            enabled: true,
        }
    }
}

/// Vault timeout manager service
pub struct VaultTimeoutManager {
    app_handle: AppHandle,
    activity_detection: Arc<ActivityDetectionService>,
    config: Arc<RwLock<VaultTimeoutConfig>>,
    current_user_id: Arc<RwLock<Option<String>>>,
    timeout_start: Arc<RwLock<Option<Instant>>>,
    monitoring_enabled: Arc<RwLock<bool>>,
    timeout_sender: broadcast::Sender<VaultTimeoutEvent>,
    _timeout_receiver: broadcast::Receiver<VaultTimeoutEvent>, // Keep receiver to prevent channel closure
}

impl VaultTimeoutManager {
    /// Create a new vault timeout manager
    pub fn new(app_handle: AppHandle, activity_detection: Arc<ActivityDetectionService>) -> Self {
        let (timeout_sender, timeout_receiver) = broadcast::channel(100);
        
        Self {
            app_handle,
            activity_detection,
            config: Arc::new(RwLock::new(VaultTimeoutConfig::default())),
            current_user_id: Arc::new(RwLock::new(None)),
            timeout_start: Arc::new(RwLock::new(None)),
            monitoring_enabled: Arc::new(RwLock::new(false)),
            timeout_sender,
            _timeout_receiver: timeout_receiver,
        }
    }

    /// Start timeout monitoring for a specific user
    pub async fn start_monitoring(&self, user_id: String) -> AppResult<()> {
        let config = self.config.read().await.clone();
        
        // Check if timeout is disabled or set to "Never"
        if !config.enabled || config.timeout.is_never() {
            debug!("[vault_timeout] Timeout monitoring disabled or set to 'Never' for user: {}", user_id);
            return Ok(());
        }

        let timeout_ms = config.timeout.minutes().unwrap_or(15) as u32 * 60 * 1000; // Convert to milliseconds

        info!("[vault_timeout] Starting timeout monitoring for user: {} with timeout: {}ms", user_id, timeout_ms);

        // Update state
        *self.current_user_id.write().await = Some(user_id.clone());
        *self.timeout_start.write().await = Some(Instant::now());
        *self.monitoring_enabled.write().await = true;

        // Start activity detection
        self.activity_detection.start_monitoring().await?;

        // Emit monitoring started event
        let event = VaultTimeoutEvent::MonitoringStarted {
            user_id: user_id.clone(),
            timeout_ms,
        };
        self.emit_timeout_event(event).await?;

        // Start the timeout monitoring loop
        self.start_timeout_loop(user_id, timeout_ms).await?;

        // Start listening to activity events
        self.start_activity_listener().await?;

        Ok(())
    }

    /// Stop timeout monitoring
    pub async fn stop_monitoring(&self) -> AppResult<()> {
        let user_id = self.current_user_id.read().await.clone();
        
        if let Some(user_id) = user_id {
            info!("[vault_timeout] Stopping timeout monitoring for user: {}", user_id);
            
            *self.monitoring_enabled.write().await = false;
            *self.current_user_id.write().await = None;
            *self.timeout_start.write().await = None;

            // Stop activity detection
            self.activity_detection.stop_monitoring().await?;

            // Emit monitoring stopped event
            let event = VaultTimeoutEvent::MonitoringStopped { user_id };
            self.emit_timeout_event(event).await?;
        }

        Ok(())
    }

    /// Reset the timeout timer (called when user activity is detected)
    pub async fn reset_timeout(&self) -> AppResult<()> {
        let monitoring_enabled = *self.monitoring_enabled.read().await;
        if !monitoring_enabled {
            return Ok(());
        }

        let user_id = self.current_user_id.read().await.clone();
        if let Some(user_id) = user_id {
            debug!("[vault_timeout] Resetting timeout for user: {}", user_id);
            
            // Reset timeout start time
            *self.timeout_start.write().await = Some(Instant::now());

            // Calculate remaining time
            let config = self.config.read().await.clone();
            let timeout_ms = config.timeout.minutes().unwrap_or(15) as u32 * 60 * 1000;

            // Emit timeout reset event
            let event = VaultTimeoutEvent::TimeoutReset {
                user_id,
                remaining_ms: timeout_ms,
            };
            self.emit_timeout_event(event).await?;
        }

        Ok(())
    }

    /// Update timeout configuration
    pub async fn update_config(&self, config: VaultTimeoutConfig) -> AppResult<()> {
        debug!("[vault_timeout] Updating configuration: {:?}", config);
        *self.config.write().await = config;
        Ok(())
    }

    /// Get current configuration
    pub async fn get_config(&self) -> VaultTimeoutConfig {
        self.config.read().await.clone()
    }

    /// Check if monitoring is currently enabled
    pub async fn is_monitoring(&self) -> bool {
        *self.monitoring_enabled.read().await
    }

    /// Get current user ID being monitored
    pub async fn get_current_user_id(&self) -> Option<String> {
        self.current_user_id.read().await.clone()
    }

    /// Get a receiver for timeout events
    pub fn subscribe_to_events(&self) -> broadcast::Receiver<VaultTimeoutEvent> {
        self.timeout_sender.subscribe()
    }

    /// Manually trigger vault lock
    pub async fn trigger_lock(&self, reason: LockReason) -> AppResult<()> {
        let user_id = self.current_user_id.read().await.clone();
        if let Some(user_id) = user_id {
            info!("[vault_timeout] Manually triggering vault lock for user: {} (reason: {:?})", user_id, reason);
            
            let event = VaultTimeoutEvent::VaultLockTriggered { user_id, reason };
            self.emit_timeout_event(event).await?;
        }
        Ok(())
    }

    /// Start the timeout monitoring loop
    async fn start_timeout_loop(&self, user_id: String, timeout_ms: u32) -> AppResult<()> {
        let app_handle = self.app_handle.clone();
        let timeout_start = self.timeout_start.clone();
        let monitoring_enabled = self.monitoring_enabled.clone();
        let timeout_sender = self.timeout_sender.clone();
        let timeout_duration = Duration::from_millis(timeout_ms.into());

        tokio::spawn(async move {
            let mut check_interval = tokio::time::interval(Duration::from_secs(1)); // Check every second
            
            loop {
                check_interval.tick().await;

                // Check if monitoring is still enabled
                if !*monitoring_enabled.read().await {
                    debug!("[vault_timeout] Timeout loop stopped for user: {}", user_id);
                    break;
                }

                // Check if timeout has elapsed
                if let Some(start_time) = *timeout_start.read().await {
                    let elapsed = start_time.elapsed();
                    
                    if elapsed >= timeout_duration {
                        info!("[vault_timeout] Timeout elapsed for user: {} ({}ms)", user_id, elapsed.as_millis());
                        
                        let event = VaultTimeoutEvent::VaultLockTriggered {
                            user_id: user_id.clone(),
                            reason: LockReason::InactivityTimeout,
                        };

                        // Send to internal subscribers
                        if let Err(e) = timeout_sender.send(event.clone()) {
                            warn!("[vault_timeout] Failed to send timeout event: {}", e);
                        }

                        // Emit Tauri event for frontend
                        if let Err(e) = app_handle.emit("vault_timeout_event", &event) {
                            warn!("[vault_timeout] Failed to emit timeout event to frontend: {}", e);
                        }

                        // Stop monitoring after triggering lock
                        *monitoring_enabled.write().await = false;
                        break;
                    }
                }
            }
        });

        Ok(())
    }

    /// Start listening to activity events and reset timeout accordingly
    async fn start_activity_listener(&self) -> AppResult<()> {
        let mut activity_receiver = self.activity_detection.subscribe_to_events();
        let timeout_manager = Arc::new(self.clone());

        tokio::spawn(async move {
            while let Ok(event) = activity_receiver.recv().await {
                match event {
                    ActivityEvent::UserActive => {
                        if let Err(e) = timeout_manager.reset_timeout().await {
                            warn!("[vault_timeout] Failed to reset timeout on user activity: {}", e);
                        }
                    }
                    ActivityEvent::UserIdle { .. } => {
                        // We don't need to do anything special for idle events
                        // The timeout loop will handle the actual timeout
                        debug!("[vault_timeout] User idle detected, timeout continues");
                    }
                    _ => {
                        // Handle other activity events if needed
                    }
                }
            }
        });

        Ok(())
    }

    /// Emit a timeout event to both internal subscribers and frontend
    async fn emit_timeout_event(&self, event: VaultTimeoutEvent) -> AppResult<()> {
        // Send to internal subscribers
        if let Err(e) = self.timeout_sender.send(event.clone()) {
            warn!("[vault_timeout] Failed to send timeout event: {}", e);
        }

        // Emit Tauri event for frontend
        if let Err(e) = self.app_handle.emit("vault_timeout_event", &event) {
            error!("[vault_timeout] Failed to emit timeout event to frontend: {}", e);
            return Err(AppError::InternalError {
                message: format!("Failed to emit timeout event: {}", e),
            });
        }

        debug!("[vault_timeout] Emitted timeout event: {:?}", event);
        Ok(())
    }
}

// Implement Clone for VaultTimeoutManager to use in async tasks
impl Clone for VaultTimeoutManager {
    fn clone(&self) -> Self {
        Self {
            app_handle: self.app_handle.clone(),
            activity_detection: self.activity_detection.clone(),
            config: self.config.clone(),
            current_user_id: self.current_user_id.clone(),
            timeout_start: self.timeout_start.clone(),
            monitoring_enabled: self.monitoring_enabled.clone(),
            timeout_sender: self.timeout_sender.clone(),
            _timeout_receiver: self.timeout_sender.subscribe(),
        }
    }
}
