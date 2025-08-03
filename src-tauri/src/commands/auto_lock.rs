use crate::app_state::AppState;
use crate::error::AppError;
use crate::models::settings::{VaultTimeout, ActivitySensitivity};
use crate::services::{ActivityDetectionConfig, VaultTimeoutConfig, ActivityEvent, VaultTimeoutEvent};
use crate::services::vault_timeout_manager::LockReason;
use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::{command, State};
use tracing::{debug, info};

/// Request to start auto-lock monitoring
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct StartAutoLockRequest {
    pub user_id: String,
    pub timeout: VaultTimeout,
    pub enabled: bool,
}

/// Request to update auto-lock configuration
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct UpdateAutoLockConfigRequest {
    pub timeout: VaultTimeout,
    pub enabled: bool,
    pub activity_sensitivity: ActivitySensitivity,
}

/// Response for auto-lock status
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct AutoLockStatusResponse {
    pub monitoring_enabled: bool,
    pub current_user_id: Option<String>,
    pub timeout_config: VaultTimeout,
    pub activity_sensitivity: ActivitySensitivity,
}

/// Start auto-lock monitoring for a user
#[command]
#[specta::specta]
pub async fn start_auto_lock_monitoring(
    request: StartAutoLockRequest,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    info!(
        user_id = request.user_id,
        timeout = ?request.timeout,
        enabled = request.enabled,
        "[auto_lock] Starting auto-lock monitoring"
    );

    // Update vault timeout manager configuration
    let timeout_config = VaultTimeoutConfig {
        timeout: request.timeout.clone(),
        enabled: request.enabled,
    };

    state
        .vault_timeout_manager
        .update_config(timeout_config)
        .await?;

    // Start monitoring if enabled
    if request.enabled && !request.timeout.is_never() {
        state
            .vault_timeout_manager
            .start_monitoring(request.user_id.clone())
            .await?;
        
        info!(
            user_id = request.user_id,
            "[auto_lock] Auto-lock monitoring started successfully"
        );
    } else {
        debug!(
            user_id = request.user_id,
            "[auto_lock] Auto-lock monitoring not started (disabled or timeout set to 'Never')"
        );
    }

    Ok(())
}

/// Stop auto-lock monitoring
#[command]
#[specta::specta]
pub async fn stop_auto_lock_monitoring(state: State<'_, AppState>) -> Result<(), AppError> {
    info!("[auto_lock] Stopping auto-lock monitoring");

    state.vault_timeout_manager.stop_monitoring().await?;

    info!("[auto_lock] Auto-lock monitoring stopped successfully");
    Ok(())
}

/// Reset the activity timer (called when user activity is detected)
#[command]
#[specta::specta]
pub async fn reset_activity_timer(state: State<'_, AppState>) -> Result<(), AppError> {
    debug!("[auto_lock] Resetting activity timer");

    // Record activity in the activity detection service
    state.activity_detection_service.record_activity().await?;

    // Reset timeout in the vault timeout manager
    state.vault_timeout_manager.reset_timeout().await?;

    Ok(())
}

/// Update auto-lock configuration
#[command]
#[specta::specta]
pub async fn update_auto_lock_config(
    request: UpdateAutoLockConfigRequest,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    info!(
        timeout = ?request.timeout,
        enabled = request.enabled,
        sensitivity = ?request.activity_sensitivity,
        "[auto_lock] Updating auto-lock configuration"
    );

    // Update vault timeout manager configuration
    let timeout_config = VaultTimeoutConfig {
        timeout: request.timeout.clone(),
        enabled: request.enabled,
    };
    
    state
        .vault_timeout_manager
        .update_config(timeout_config)
        .await?;

    // Update activity detection configuration
    let activity_config = ActivityDetectionConfig {
        sensitivity: request.activity_sensitivity,
        check_interval_ms: 1000, // 1 second
        idle_threshold_ms: 30000, // 30 seconds
    };
    
    state
        .activity_detection_service
        .update_config(activity_config)
        .await?;

    info!("[auto_lock] Auto-lock configuration updated successfully");
    Ok(())
}

/// Get current auto-lock status
#[command]
#[specta::specta]
pub async fn get_auto_lock_status(
    state: State<'_, AppState>,
) -> Result<AutoLockStatusResponse, AppError> {
    debug!("[auto_lock] Getting auto-lock status");

    let monitoring_enabled = state.vault_timeout_manager.is_monitoring().await;
    let current_user_id = state.vault_timeout_manager.get_current_user_id().await;
    let timeout_config = state.vault_timeout_manager.get_config().await;
    let activity_config = state.activity_detection_service.get_config().await;

    let response = AutoLockStatusResponse {
        monitoring_enabled,
        current_user_id,
        timeout_config: timeout_config.timeout,
        activity_sensitivity: activity_config.sensitivity,
    };

    debug!("[auto_lock] Auto-lock status retrieved: {:?}", response);
    Ok(response)
}

/// Manually trigger vault lock
#[command]
#[specta::specta]
pub async fn trigger_manual_lock(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    info!(
        user_id = user_id,
        "[auto_lock] Manually triggering vault lock"
    );

    use crate::services::LockReason;
    
    state
        .vault_timeout_manager
        .trigger_lock(LockReason::ManualLock)
        .await?;

    info!(
        user_id = user_id,
        "[auto_lock] Manual vault lock triggered successfully"
    );
    Ok(())
}

/// Check if auto-lock is supported on the current platform
#[command]
#[specta::specta]
pub async fn check_auto_lock_support() -> Result<bool, AppError> {
    // For now, we support auto-lock on all platforms
    // In the future, we might have platform-specific limitations
    Ok(true)
}

/// Get recommended auto-lock settings based on system capabilities
#[command]
#[specta::specta]
pub async fn get_recommended_auto_lock_settings() -> Result<UpdateAutoLockConfigRequest, AppError> {
    // Return recommended settings based on platform and security best practices
    Ok(UpdateAutoLockConfigRequest {
        timeout: VaultTimeout::Minutes(15), // 15 minutes default
        enabled: true,
        activity_sensitivity: ActivitySensitivity::Medium,
    })
}

/// Get auto-lock event types (for TypeScript type generation)
/// This command exists solely to ensure auto-lock event types are exported to TypeScript
#[command]
#[specta::specta]
pub async fn get_auto_lock_event_types() -> Result<AutoLockEventTypes, AppError> {
    // This is a dummy command that returns example types to ensure they're exported
    Ok(AutoLockEventTypes {
        activity_event: ActivityEvent::UserActive,
        vault_timeout_event: VaultTimeoutEvent::VaultLockTriggered {
            user_id: "example-user-id".to_string(),
            reason: LockReason::InactivityTimeout,
        },
    })
}

/// Container for auto-lock event types (for TypeScript export)
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct AutoLockEventTypes {
    pub activity_event: ActivityEvent,
    pub vault_timeout_event: VaultTimeoutEvent,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app_state::AppState;
    use tauri::test::{mock_app, MockRuntime};

    async fn create_test_app_state() -> AppState {
        let app = mock_app();
        AppState::new(app.handle().clone()).await.unwrap()
    }

    #[tokio::test]
    async fn test_start_auto_lock_monitoring() {
        let state = create_test_app_state().await;
        let request = StartAutoLockRequest {
            user_id: "test_user".to_string(),
            timeout: VaultTimeout::Minutes(15),
            enabled: true,
        };

        let result = start_auto_lock_monitoring(request, State::from(&state)).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_get_auto_lock_status() {
        let state = create_test_app_state().await;
        let result = get_auto_lock_status(State::from(&state)).await;
        
        assert!(result.is_ok());
        let status = result.unwrap();
        assert!(!status.monitoring_enabled);
        assert!(status.current_user_id.is_none());
    }

    #[tokio::test]
    async fn test_check_auto_lock_support() {
        let result = check_auto_lock_support().await;
        assert!(result.is_ok());
        assert!(result.unwrap());
    }

    #[tokio::test]
    async fn test_get_recommended_settings() {
        let result = get_recommended_auto_lock_settings().await;
        assert!(result.is_ok());
        
        let settings = result.unwrap();
        assert!(settings.enabled);
        assert_eq!(settings.activity_sensitivity, ActivitySensitivity::Medium);
        assert_eq!(settings.timeout, VaultTimeout::Minutes(15));
    }
}
