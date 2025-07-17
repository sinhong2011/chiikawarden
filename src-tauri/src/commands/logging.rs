use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::command;
use tracing::{debug, error, info, warn};

/// Log level enum for frontend logging
#[derive(Debug, Serialize, Deserialize, Type)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

/// Log entry structure for frontend logging
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct LogEntry {
    pub level: LogLevel,
    pub message: String,
    pub context: Option<String>, // Changed from serde_json::Value to String
    pub component: Option<String>,
    pub error_id: Option<String>,
    pub severity: Option<String>,
}

/// Log a message from the frontend to the backend logging system
#[command]
#[specta::specta]
pub async fn log_frontend_message(entry: LogEntry) -> Result<(), String> {
    let component = entry.component.as_deref().unwrap_or("frontend");
    let context_str = entry
        .context
        .as_ref()
        .map(|c| serde_json::to_string(c).unwrap_or_default())
        .unwrap_or_default();

    // Enhanced logging with better structure for console integration
    match entry.level {
        LogLevel::Debug => {
            debug!(
                target: "chiikawarden::frontend",
                component = component,
                context = context_str,
                error_id = entry.error_id.as_deref().unwrap_or(""),
                severity = entry.severity.as_deref().unwrap_or(""),
                source = "console",
                "[frontend] {}",
                entry.message
            );
        }
        LogLevel::Info => {
            info!(
                target: "chiikawarden::frontend",
                component = component,
                context = context_str,
                error_id = entry.error_id.as_deref().unwrap_or(""),
                severity = entry.severity.as_deref().unwrap_or(""),
                source = "console",
                "[frontend] {}",
                entry.message
            );
        }
        LogLevel::Warn => {
            warn!(
                target: "chiikawarden::frontend",
                component = component,
                context = context_str,
                error_id = entry.error_id.as_deref().unwrap_or(""),
                severity = entry.severity.as_deref().unwrap_or(""),
                source = "console",
                "[frontend] {}",
                entry.message
            );
        }
        LogLevel::Error => {
            error!(
                target: "chiikawarden::frontend",
                component = component,
                context = context_str,
                error_id = entry.error_id.as_deref().unwrap_or(""),
                severity = entry.severity.as_deref().unwrap_or(""),
                source = "console",
                "[frontend] {}",
                entry.message
            );
        }
    }

    Ok(())
}

/// Log an error from the frontend error boundary
#[command]
#[specta::specta]
pub async fn log_error_boundary(
    category: String,
    technical_message: String,
    error_id: String,
    severity: String,
    context: Option<serde_json::Value>,
) -> Result<(), String> {
    let context_str = context
        .as_ref()
        .map(|c| serde_json::to_string(c).unwrap_or_default())
        .unwrap_or_default();

    error!(
        component = "ErrorBoundary",
        category = category,
        error_id = error_id,
        severity = severity,
        context = context_str,
        "Frontend Error Boundary: {}",
        technical_message
    );

    Ok(())
}

/// Log a user action for audit purposes
#[command]
pub async fn log_user_action(
    action: String,
    resource_type: String,
    resource_id: Option<String>,
    user_id: Option<String>,
    success: bool,
    details: Option<String>,
) -> Result<(), String> {
    if success {
        info!(
            action = action,
            resource_type = resource_type,
            resource_id = resource_id.as_deref().unwrap_or("unknown"),
            user_id = user_id.as_deref().unwrap_or("unknown"),
            details = details.as_deref().unwrap_or(""),
            "Frontend User Action: Success"
        );
    } else {
        warn!(
            action = action,
            resource_type = resource_type,
            resource_id = resource_id.as_deref().unwrap_or("unknown"),
            user_id = user_id.as_deref().unwrap_or("unknown"),
            details = details.as_deref().unwrap_or(""),
            "Frontend User Action: Failed"
        );
    }

    Ok(())
}

/// Test command to verify local timezone logging is working
/// This command logs messages at different levels to verify that timestamps
/// are displayed in the local timezone rather than UTC
#[command]
pub async fn test_timezone_logging() -> Result<String, String> {
    use crate::logging::test_local_timezone_logging;

    info!("Testing local timezone logging from command");
    test_local_timezone_logging();

    Ok("Local timezone logging test completed. Check console and log files for timestamps in your local timezone.".to_string())
}
