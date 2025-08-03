use crate::error::{AppError, AppResult};
use crate::models::settings::ActivitySensitivity;
use serde::{Deserialize, Serialize};
use specta::Type;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter};
use tokio::sync::{broadcast, RwLock};

use tracing::{debug, error, info, warn};

/// Activity event types that can be detected
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub enum ActivityEvent {
    /// User performed an action (mouse, keyboard, UI interaction)
    UserActive,
    /// User has been idle for the specified duration
    UserIdle { idle_duration_ms: u32 },
    /// Activity detection started
    MonitoringStarted,
    /// Activity detection stopped
    MonitoringStopped,
}



/// Configuration for activity detection
#[derive(Debug, Clone)]
pub struct ActivityDetectionConfig {
    pub sensitivity: ActivitySensitivity,
    pub check_interval_ms: u64,
    pub idle_threshold_ms: u64,
}

impl Default for ActivityDetectionConfig {
    fn default() -> Self {
        Self {
            sensitivity: ActivitySensitivity::Medium,
            check_interval_ms: 1000, // Check every second
            idle_threshold_ms: 30000, // 30 seconds of inactivity before considering idle
        }
    }
}

/// Activity detection service for monitoring user activity
pub struct ActivityDetectionService {
    app_handle: AppHandle,
    config: Arc<RwLock<ActivityDetectionConfig>>,
    last_activity: Arc<RwLock<Instant>>,
    monitoring_enabled: Arc<RwLock<bool>>,
    activity_sender: broadcast::Sender<ActivityEvent>,
    _activity_receiver: broadcast::Receiver<ActivityEvent>, // Keep receiver to prevent channel closure
}

impl ActivityDetectionService {
    /// Create a new activity detection service
    pub fn new(app_handle: AppHandle) -> Self {
        let (activity_sender, activity_receiver) = broadcast::channel(100);
        
        Self {
            app_handle,
            config: Arc::new(RwLock::new(ActivityDetectionConfig::default())),
            last_activity: Arc::new(RwLock::new(Instant::now())),
            monitoring_enabled: Arc::new(RwLock::new(false)),
            activity_sender,
            _activity_receiver: activity_receiver,
        }
    }

    /// Start activity monitoring
    pub async fn start_monitoring(&self) -> AppResult<()> {
        let mut monitoring_enabled = self.monitoring_enabled.write().await;
        if *monitoring_enabled {
            debug!("[activity_detection] Monitoring already started");
            return Ok(());
        }

        *monitoring_enabled = true;
        drop(monitoring_enabled);

        info!("[activity_detection] Starting activity monitoring");

        // Reset last activity time
        *self.last_activity.write().await = Instant::now();

        // Emit monitoring started event
        self.emit_activity_event(ActivityEvent::MonitoringStarted).await?;

        // Start the monitoring loop
        self.start_monitoring_loop().await?;

        Ok(())
    }

    /// Stop activity monitoring
    pub async fn stop_monitoring(&self) -> AppResult<()> {
        let mut monitoring_enabled = self.monitoring_enabled.write().await;
        if !*monitoring_enabled {
            debug!("[activity_detection] Monitoring already stopped");
            return Ok(());
        }

        *monitoring_enabled = false;
        drop(monitoring_enabled);

        info!("[activity_detection] Stopping activity monitoring");

        // Emit monitoring stopped event
        self.emit_activity_event(ActivityEvent::MonitoringStopped).await?;

        Ok(())
    }

    /// Record user activity (called from UI interactions)
    pub async fn record_activity(&self) -> AppResult<()> {
        let monitoring_enabled = *self.monitoring_enabled.read().await;
        if !monitoring_enabled {
            return Ok(());
        }

        debug!("[activity_detection] Recording user activity");
        
        // Update last activity time
        *self.last_activity.write().await = Instant::now();

        // Emit user active event
        self.emit_activity_event(ActivityEvent::UserActive).await?;

        Ok(())
    }

    /// Update activity detection configuration
    pub async fn update_config(&self, config: ActivityDetectionConfig) -> AppResult<()> {
        debug!("[activity_detection] Updating configuration: {:?}", config);
        *self.config.write().await = config;
        Ok(())
    }

    /// Get current configuration
    pub async fn get_config(&self) -> ActivityDetectionConfig {
        self.config.read().await.clone()
    }

    /// Check if monitoring is currently enabled
    pub async fn is_monitoring(&self) -> bool {
        *self.monitoring_enabled.read().await
    }

    /// Get a receiver for activity events
    pub fn subscribe_to_events(&self) -> broadcast::Receiver<ActivityEvent> {
        self.activity_sender.subscribe()
    }

    /// Start the monitoring loop that checks for idle state
    async fn start_monitoring_loop(&self) -> AppResult<()> {
        let app_handle = self.app_handle.clone();
        let config = self.config.clone();
        let last_activity = self.last_activity.clone();
        let monitoring_enabled = self.monitoring_enabled.clone();
        let activity_sender = self.activity_sender.clone();

        tokio::spawn(async move {
            let mut last_idle_check = Instant::now();
            
            loop {
                // Check if monitoring is still enabled
                if !*monitoring_enabled.read().await {
                    debug!("[activity_detection] Monitoring loop stopped");
                    break;
                }

                let config_snapshot = config.read().await.clone();
                let check_interval = Duration::from_millis(config_snapshot.check_interval_ms);
                
                // Wait for the next check interval
                tokio::time::sleep(check_interval).await;

                // Check for idle state
                let last_activity_time = *last_activity.read().await;
                let idle_duration = last_activity_time.elapsed();
                let idle_threshold = Duration::from_millis(config_snapshot.idle_threshold_ms);

                if idle_duration >= idle_threshold {
                    // Only emit idle event if we haven't recently checked
                    if last_idle_check.elapsed() >= Duration::from_secs(5) {
                        let idle_event = ActivityEvent::UserIdle {
                            idle_duration_ms: idle_duration.as_millis() as u32,
                        };

                        // Emit idle event
                        if let Err(e) = activity_sender.send(idle_event.clone()) {
                            warn!("[activity_detection] Failed to send idle event: {}", e);
                        }

                        // Emit Tauri event for frontend
                        if let Err(e) = app_handle.emit("activity_event", &idle_event) {
                            warn!("[activity_detection] Failed to emit idle event to frontend: {}", e);
                        }

                        last_idle_check = Instant::now();
                    }
                }
            }
        });

        Ok(())
    }

    /// Emit an activity event to both internal subscribers and frontend
    async fn emit_activity_event(&self, event: ActivityEvent) -> AppResult<()> {
        // Send to internal subscribers
        if let Err(e) = self.activity_sender.send(event.clone()) {
            warn!("[activity_detection] Failed to send activity event: {}", e);
        }

        // Emit Tauri event for frontend
        if let Err(e) = self.app_handle.emit("activity_event", &event) {
            error!("[activity_detection] Failed to emit activity event to frontend: {}", e);
            return Err(AppError::InternalError {
                message: format!("Failed to emit activity event: {}", e),
            });
        }

        debug!("[activity_detection] Emitted activity event: {:?}", event);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tauri::test::{mock_app, MockRuntime};

    #[tokio::test]
    async fn test_activity_detection_service_creation() {
        let app = mock_app();
        let service = ActivityDetectionService::new(app.handle().clone());
        
        assert!(!service.is_monitoring().await);
        assert_eq!(service.get_config().await.sensitivity, ActivitySensitivity::Medium);
    }

    #[tokio::test]
    async fn test_start_stop_monitoring() {
        let app = mock_app();
        let service = ActivityDetectionService::new(app.handle().clone());
        
        // Start monitoring
        service.start_monitoring().await.unwrap();
        assert!(service.is_monitoring().await);
        
        // Stop monitoring
        service.stop_monitoring().await.unwrap();
        assert!(!service.is_monitoring().await);
    }

    #[tokio::test]
    async fn test_config_update() {
        let app = mock_app();
        let service = ActivityDetectionService::new(app.handle().clone());
        
        let new_config = ActivityDetectionConfig {
            sensitivity: ActivitySensitivity::High,
            check_interval_ms: 2000,
            idle_threshold_ms: 60000,
        };
        
        service.update_config(new_config.clone()).await.unwrap();
        let updated_config = service.get_config().await;
        
        assert_eq!(updated_config.sensitivity, ActivitySensitivity::High);
        assert_eq!(updated_config.check_interval_ms, 2000);
        assert_eq!(updated_config.idle_threshold_ms, 60000);
    }
}
