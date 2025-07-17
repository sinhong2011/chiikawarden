use std::fs;
use tracing::{debug, error, info, warn};
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::{
    fmt::{self, time::ChronoLocal},
    layer::SubscriberExt,
    EnvFilter, Layer,
};

/// Initialize enhanced logging that works with tauri-plugin-log
/// This is called after tauri-plugin-log has been initialized
/// Now includes colored console output support with local timezone timestamps
pub fn init_enhanced_logging() -> Result<(), crate::error::AppError> {
    // Initialize colored logging for console output
    // This works alongside tauri-plugin-log for file logging
    init_colored_logging()?;
    log::info!("Enhanced logging system with color support initialized");
    Ok(())
}

/// Get color configuration from environment variables
///
/// This function checks the RUST_LOG_COLOR environment variable to determine
/// if colored output should be enabled. It supports the following values:
/// - "true", "1", "yes", "on" -> enable colors
/// - "false", "0", "no", "off" -> disable colors
/// - not set or invalid values -> enable colors by default (for better development experience)
pub fn should_enable_colors() -> bool {
    std::env::var("RUST_LOG_COLOR")
        .map(|v| {
            let v = v.to_lowercase();
            // Only disable colors for explicit disable values, otherwise default to true
            !matches!(v.as_str(), "false" | "0" | "no" | "off")
        })
        .unwrap_or(true) // Default to true for better development experience
}

/// Initialize colored logging with environment variable support
///
/// This function provides an alternative to init_logging() that focuses on
/// colored console output with configurable color support via environment variables.
/// It maintains the structured format with timestamps and module names while
/// adding color support for different log levels:
/// - ERROR: red
/// - WARN: yellow
/// - INFO: green
/// - DEBUG: blue
/// - TRACE: magenta
pub fn init_colored_logging() -> Result<(), crate::error::AppError> {
    // Load environment variables from .env file if present (for development)
    if let Ok(env_path) = std::env::current_dir().map(|p| p.join(".env")) {
        if env_path.exists() {
            if let Err(e) = dotenvy::from_path(&env_path) {
                eprintln!("Warning: Failed to load .env file: {}", e);
            }
        }
    }

    // Initialize tracing-log bridge to forward tracing logs to log crate
    // This enables compatibility with tauri-plugin-log
    if let Err(_) = tracing_log::LogTracer::init() {
        debug!("LogTracer already initialized, skipping tracing-log bridge setup");
    }

    // Set up environment filter with RUST_LOG support
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        if cfg!(debug_assertions) {
            // In debug builds, show debug logs for our app, info for tauri, and all warnings/errors
            EnvFilter::new("chiikawarden=debug,tauri=info,sqlx=info,debug")
        } else {
            // In release builds, show info and above for our app, warnings/errors for others
            EnvFilter::new("chiikawarden=info,warn,error")
        }
    });

    // Check if color output is enabled via environment variable
    let enable_colors = should_enable_colors();

    // Console layer with color support and local timezone timestamps
    let console_layer = fmt::layer()
        .with_timer(ChronoLocal::rfc_3339())
        .with_target(true)
        .with_thread_ids(cfg!(debug_assertions))
        .with_file(cfg!(debug_assertions))
        .with_line_number(cfg!(debug_assertions))
        .with_ansi(enable_colors) // Use configurable color support
        .with_writer(std::io::stdout)
        .compact(); // Use compact format for better readability

    // Initialize tracing subscriber with colored console output
    let subscriber = tracing_subscriber::registry()
        .with(env_filter)
        .with(console_layer);

    if let Err(_) = tracing_subscriber::util::SubscriberInitExt::try_init(subscriber) {
        eprintln!("Warning: Tracing subscriber already initialized, skipping initialization");
    }

    info!("[logging] Chiikawarden colored logging initialized");
    info!(
        "[logging] Color output: {}",
        if enable_colors { "enabled" } else { "disabled" }
    );
    info!(
        "[logging] Log level: {}",
        if cfg!(debug_assertions) {
            "debug"
        } else {
            "info"
        }
    );
    info!(
        "[logging] Environment filter: {}",
        std::env::var("RUST_LOG").unwrap_or_else(|_| "default".to_string())
    );

    Ok(())
}

/// Initialize comprehensive structured logging with tauri-plugin-log integration
/// NOTE: This function is deprecated in favor of init_enhanced_logging
/// when using tauri-plugin-log
///
/// This function sets up:
/// - tracing as the primary logging framework
/// - tracing-log bridge for compatibility with log crate
/// - Multiple file appenders for different log levels
/// - Environment variable support for dynamic log level filtering
/// - Structured log format with local timezone timestamps and module names
pub fn init_logging() -> Result<LoggingGuard, crate::error::AppError> {
    // Load environment variables from .env file if present (for development)
    if let Ok(env_path) = std::env::current_dir().map(|p| p.join(".env")) {
        if env_path.exists() {
            if let Err(e) = dotenvy::from_path(&env_path) {
                eprintln!("Warning: Failed to load .env file: {}", e);
            }
        }
    }

    // Initialize tracing-log bridge to forward tracing logs to log crate
    // This enables compatibility with tauri-plugin-log
    // Only initialize if not already set (tauri-plugin-log may have initialized it)
    if let Err(_) = tracing_log::LogTracer::init() {
        debug!("LogTracer already initialized, skipping tracing-log bridge setup");
    }

    // Set up environment filter with RUST_LOG support
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        if cfg!(debug_assertions) {
            // In debug builds, show debug logs for our app, info for tauri, and all warnings/errors
            EnvFilter::new("chiikawarden=debug,tauri=info,sqlx=info,debug")
        } else {
            // In release builds, show info and above for our app, warnings/errors for others
            EnvFilter::new("chiikawarden=info,warn,error")
        }
    });

    // Get app data directory for log files
    let app_data_dir = dirs::data_dir()
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_default())
        .join("Chiikawarden");
    let log_dir = app_data_dir.join("logs");

    // Create logs directory if it doesn't exist
    fs::create_dir_all(&log_dir).map_err(|e| crate::error::AppError::StorageError {
        message: format!("Failed to create logs directory: {}", e),
    })?;

    // Set up multiple appenders for different log levels
    let info_appender = tracing_appender::rolling::daily(&log_dir, "chiikawarden.log");
    let error_appender = tracing_appender::rolling::daily(&log_dir, "chiikawarden-error.log");

    let (info_writer, info_guard) = tracing_appender::non_blocking(info_appender);
    let (error_writer, error_guard) = tracing_appender::non_blocking(error_appender);

    // Check if color output is enabled via environment variable
    let enable_colors = std::env::var("RUST_LOG_COLOR")
        .map(|v| v.to_lowercase() == "true" || v == "1")
        .unwrap_or(true); // Default to true for better development experience

    // Console layer for development - shows all logs that pass the env_filter with local timezone
    let console_layer = fmt::layer()
        .with_timer(ChronoLocal::rfc_3339())
        .with_target(true)
        .with_thread_ids(cfg!(debug_assertions))
        .with_file(cfg!(debug_assertions))
        .with_line_number(cfg!(debug_assertions))
        .with_ansi(enable_colors) // Use configurable color support
        .with_writer(std::io::stdout)
        .compact(); // Use compact format for better readability

    // Info/Debug file layer - includes debug logs in debug builds
    let info_file_filter = if cfg!(debug_assertions) {
        EnvFilter::new("chiikawarden=debug,debug,info,warn,error")
    } else {
        EnvFilter::new("info,warn,error")
    };

    let info_file_layer = fmt::layer()
        .with_timer(ChronoLocal::rfc_3339())
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true)
        .with_ansi(false)
        .with_writer(info_writer)
        .with_filter(info_file_filter);

    // Error file layer (only errors and warnings) with local timezone
    let error_file_layer = fmt::layer()
        .with_timer(ChronoLocal::rfc_3339())
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true)
        .with_ansi(false)
        .with_writer(error_writer)
        .with_filter(EnvFilter::new("warn,error"));

    // Initialize tracing subscriber with multiple layers
    // Use try_init to avoid panic if subscriber is already set (e.g., in tests)
    let subscriber = tracing_subscriber::registry()
        .with(env_filter)
        .with(console_layer)
        .with(info_file_layer)
        .with(error_file_layer);

    if let Err(_) = tracing_subscriber::util::SubscriberInitExt::try_init(subscriber) {
        eprintln!("Warning: Tracing subscriber already initialized, skipping initialization");
    }

    info!("[logging] Chiikawarden structured logging initialized");
    info!("[logging] Log directory: {}", log_dir.display());
    info!(
        "[logging] Log level: {}",
        if cfg!(debug_assertions) {
            "debug"
        } else {
            "info"
        }
    );
    info!(
        "[logging] Environment filter: {}",
        std::env::var("RUST_LOG").unwrap_or_else(|_| "default".to_string())
    );

    Ok(LoggingGuard {
        _info_guard: info_guard,
        _error_guard: error_guard,
    })
}

/// Log application startup
pub fn log_startup() {
    info!("Chiikawarden starting up");
    info!("Version: {}", env!("CARGO_PKG_VERSION"));
    info!("Build target: {}", std::env::consts::OS);
    info!("Architecture: {}", std::env::consts::ARCH);
}

/// Log application shutdown
pub fn log_shutdown() {
    info!("Chiikawarden shutting down");
}

/// Log authentication events with enhanced details
pub fn log_auth_event(event: &str, user_id: Option<&str>, success: bool) {
    if success {
        info!(
            target: "chiikawarden::auth",
            event = event,
            user_id = user_id.unwrap_or("unknown"),
            "[auth] {} successful for user {}",
            event,
            user_id.unwrap_or("unknown")
        );
    } else {
        warn!(
            target: "chiikawarden::auth",
            event = event,
            user_id = user_id.unwrap_or("unknown"),
            "[auth] {} failed for user {}",
            event,
            user_id.unwrap_or("unknown")
        );
    }
}

/// Log detailed authentication events with timing and context
pub fn log_auth_event_detailed(
    event: &str,
    user_id: Option<&str>,
    email: Option<&str>,
    success: bool,
    duration_ms: Option<u64>,
    client_info: Option<&str>,
    error_details: Option<&str>,
) {
    let user_info = match (user_id, email) {
        (Some(id), Some(email)) => format!("{} ({})", email, id),
        (Some(id), None) => id.to_string(),
        (None, Some(email)) => email.to_string(),
        (None, None) => "unknown".to_string(),
    };

    let timing_info = duration_ms
        .map(|d| format!(" in {}ms", d))
        .unwrap_or_default();

    if success {
        info!(
            target: "chiikawarden::auth",
            event = event,
            user_id = user_id.unwrap_or("unknown"),
            email = email.unwrap_or("unknown"),
            duration_ms = duration_ms.unwrap_or(0),
            client_info = client_info.unwrap_or("unknown"),
            "[auth] {} successful for {}{} (client: {})",
            event,
            user_info,
            timing_info,
            client_info.unwrap_or("unknown")
        );
    } else {
        warn!(
            target: "chiikawarden::auth",
            event = event,
            user_id = user_id.unwrap_or("unknown"),
            email = email.unwrap_or("unknown"),
            duration_ms = duration_ms.unwrap_or(0),
            client_info = client_info.unwrap_or("unknown"),
            error_details = error_details.unwrap_or("unknown"),
            "[auth] {} failed for {}{} (client: {}, error: {})",
            event,
            user_info,
            timing_info,
            client_info.unwrap_or("unknown"),
            error_details.unwrap_or("unknown")
        );
    }
}

/// Log token-related events
pub fn log_token_event(
    event: &str,
    token_type: &str,
    user_id: Option<&str>,
    expires_in: Option<u64>,
    success: bool,
) {
    if success {
        info!(
            target: "chiikawarden::auth::token",
            event = event,
            token_type = token_type,
            user_id = user_id.unwrap_or("unknown"),
            expires_in = expires_in.unwrap_or(0),
            "[auth:token] {} {} for user {} (expires in {}s)",
            event,
            token_type,
            user_id.unwrap_or("unknown"),
            expires_in.unwrap_or(0)
        );
    } else {
        warn!(
            target: "chiikawarden::auth::token",
            event = event,
            token_type = token_type,
            user_id = user_id.unwrap_or("unknown"),
            "[auth:token] {} {} failed for user {}",
            event,
            token_type,
            user_id.unwrap_or("unknown")
        );
    }
}

/// Log two-factor authentication events
pub fn log_2fa_event(
    event: &str,
    user_id: Option<&str>,
    method: &str,
    success: bool,
    attempts: Option<u32>,
) {
    let attempt_info = attempts
        .map(|a| format!(" (attempt {})", a))
        .unwrap_or_default();

    if success {
        info!(
            target: "chiikawarden::auth::2fa",
            event = event,
            user_id = user_id.unwrap_or("unknown"),
            method = method,
            attempts = attempts.unwrap_or(0),
            "[auth:2fa] {} {} for user {} using {}{}",
            event,
            if success { "successful" } else { "failed" },
            user_id.unwrap_or("unknown"),
            method,
            attempt_info
        );
    } else {
        warn!(
            target: "chiikawarden::auth::2fa",
            event = event,
            user_id = user_id.unwrap_or("unknown"),
            method = method,
            attempts = attempts.unwrap_or(0),
            "[auth:2fa] {} failed for user {} using {}{}",
            event,
            user_id.unwrap_or("unknown"),
            method,
            attempt_info
        );
    }
}

/// Log security events
pub fn log_security_event(event: &str, details: &str, severity: SecuritySeverity) {
    match severity {
        SecuritySeverity::Info => info!(event = event, details = details, "Security event"),
        SecuritySeverity::Warning => warn!(event = event, details = details, "Security warning"),
        SecuritySeverity::Critical => error!(event = event, details = details, "Security alert"),
    }
}

/// Log vault operations
pub fn log_vault_operation(operation: &str, item_type: &str, item_id: Option<&str>, success: bool) {
    if success {
        info!(
            operation = operation,
            item_type = item_type,
            item_id = item_id.unwrap_or("unknown"),
            "Vault operation successful"
        );
    } else {
        error!(
            operation = operation,
            item_type = item_type,
            item_id = item_id.unwrap_or("unknown"),
            "Vault operation failed"
        );
    }
}

/// Log sync operations
pub fn log_sync_event(event: &str, user_id: &str, details: Option<&str>) {
    info!(
        event = event,
        user_id = user_id,
        details = details.unwrap_or(""),
        "Sync event"
    );
}

/// Log crypto operations
pub fn log_crypto_operation(operation: &str, success: bool, error_msg: Option<&str>) {
    if success {
        info!(operation = operation, "Crypto operation successful");
    } else {
        error!(
            operation = operation,
            error = error_msg.unwrap_or("unknown error"),
            "Crypto operation failed"
        );
    }
}

/// Log database operations
pub fn log_database_operation(
    operation: &str,
    table: &str,
    success: bool,
    error_msg: Option<&str>,
) {
    if success {
        debug!(
            operation = operation,
            table = table,
            "Database operation successful"
        );
    } else {
        error!(
            operation = operation,
            table = table,
            error = error_msg.unwrap_or("unknown error"),
            "Database operation failed"
        );
    }
}

/// Log HTTP request details in Vaultwarden-style format
pub fn log_http_request(method: &str, url: &str, has_auth: bool) {
    info!(
        target: "chiikawarden::api::request",
        method = method,
        url = url,
        has_auth = has_auth,
        "[request] {} {} (auth: {})",
        method,
        url,
        if has_auth { "yes" } else { "no" }
    );
}

/// Log HTTP request with additional context
pub fn log_http_request_with_context(
    method: &str,
    url: &str,
    has_auth: bool,
    user_agent: Option<&str>,
    content_type: Option<&str>,
) {
    info!(
        target: "chiikawarden::api::request",
        method = method,
        url = url,
        has_auth = has_auth,
        user_agent = user_agent.unwrap_or("unknown"),
        content_type = content_type.unwrap_or("unknown"),
        "[request] {} {} (auth: {}, user-agent: {}, content-type: {})",
        method,
        url,
        if has_auth { "yes" } else { "no" },
        user_agent.unwrap_or("unknown"),
        content_type.unwrap_or("unknown")
    );
}

/// Log HTTP response details in Vaultwarden-style format
pub fn log_http_response(method: &str, url: &str, status: u16, duration_ms: u64) {
    if status >= 200 && status < 300 {
        info!(
            target: "chiikawarden::api::response",
            method = method,
            url = url,
            status = status,
            duration_ms = duration_ms,
            "[response] {} {} {} ({}ms)",
            method,
            url,
            status,
            duration_ms
        );
    } else if status >= 400 {
        warn!(
            target: "chiikawarden::api::response",
            method = method,
            url = url,
            status = status,
            duration_ms = duration_ms,
            "[response] {} {} {} ({}ms) - Request failed",
            method,
            url,
            status,
            duration_ms
        );
    } else {
        info!(
            target: "chiikawarden::api::response",
            method = method,
            url = url,
            status = status,
            duration_ms = duration_ms,
            "[response] {} {} {} ({}ms)",
            method,
            url,
            status,
            duration_ms
        );
    }
}

/// Log HTTP response with additional details
pub fn log_http_response_with_details(
    method: &str,
    url: &str,
    status: u16,
    duration_ms: u64,
    content_length: Option<u64>,
    content_type: Option<&str>,
) {
    let content_info = match (content_length, content_type) {
        (Some(len), Some(ct)) => format!(" ({}ms, {} bytes, {})", duration_ms, len, ct),
        (Some(len), None) => format!(" ({}ms, {} bytes)", duration_ms, len),
        (None, Some(ct)) => format!(" ({}ms, {})", duration_ms, ct),
        (None, None) => format!(" ({}ms)", duration_ms),
    };

    if status >= 200 && status < 300 {
        info!(
            target: "chiikawarden::api::response",
            method = method,
            url = url,
            status = status,
            duration_ms = duration_ms,
            content_length = content_length.unwrap_or(0),
            content_type = content_type.unwrap_or("unknown"),
            "[response] {} {} {}{}",
            method,
            url,
            status,
            content_info
        );
    } else if status >= 400 {
        warn!(
            target: "chiikawarden::api::response",
            method = method,
            url = url,
            status = status,
            duration_ms = duration_ms,
            content_length = content_length.unwrap_or(0),
            content_type = content_type.unwrap_or("unknown"),
            "[response] {} {} {}{} - Request failed",
            method,
            url,
            status,
            content_info
        );
    } else {
        info!(
            target: "chiikawarden::api::response",
            method = method,
            url = url,
            status = status,
            duration_ms = duration_ms,
            content_length = content_length.unwrap_or(0),
            content_type = content_type.unwrap_or("unknown"),
            "[response] {} {} {}{}",
            method,
            url,
            status,
            content_info
        );
    }
}

/// Log WebSocket connection accept
pub fn log_websocket_accept(client_ip: &str, user_agent: Option<&str>) {
    info!(
        target: "chiikawarden::api::notifications",
        client_ip = client_ip,
        user_agent = user_agent.unwrap_or("unknown"),
        "[notifications] WebSocket connection accepted from {} (user-agent: {})",
        client_ip,
        user_agent.unwrap_or("unknown")
    );
}

/// Log WebSocket connection closure
pub fn log_websocket_close(client_ip: &str, reason: Option<&str>, duration_ms: Option<u64>) {
    let duration_info = duration_ms
        .map(|d| format!(" after {}ms", d))
        .unwrap_or_default();

    info!(
        target: "chiikawarden::api::notifications",
        client_ip = client_ip,
        reason = reason.unwrap_or("unknown"),
        duration_ms = duration_ms.unwrap_or(0),
        "[notifications] WebSocket connection closed from {}{} (reason: {})",
        client_ip,
        duration_info,
        reason.unwrap_or("unknown")
    );
}

/// Log WebSocket message send
pub fn log_websocket_send(client_ip: &str, message_type: &str, message_size: usize) {
    debug!(
        target: "chiikawarden::api::notifications",
        client_ip = client_ip,
        message_type = message_type,
        message_size = message_size,
        "[notifications] Sending {} message to {} ({} bytes)",
        message_type,
        client_ip,
        message_size
    );
}

/// Log WebSocket message receive
pub fn log_websocket_receive(client_ip: &str, message_type: &str, message_size: usize) {
    debug!(
        target: "chiikawarden::api::notifications",
        client_ip = client_ip,
        message_type = message_type,
        message_size = message_size,
        "[notifications] Received {} message from {} ({} bytes)",
        message_type,
        client_ip,
        message_size
    );
}

/// Log WebSocket error
pub fn log_websocket_error(client_ip: &str, error: &str) {
    warn!(
        target: "chiikawarden::api::notifications",
        client_ip = client_ip,
        error = error,
        "[notifications] WebSocket error for {}: {}",
        client_ip,
        error
    );
}

/// Log network operations
pub fn log_network_operation(
    operation: &str,
    endpoint: &str,
    status_code: Option<u16>,
    success: bool,
) {
    if success {
        info!(
            operation = operation,
            endpoint = endpoint,
            status_code = status_code.unwrap_or(0),
            "Network operation successful"
        );
    } else {
        warn!(
            operation = operation,
            endpoint = endpoint,
            status_code = status_code.unwrap_or(0),
            "Network operation failed"
        );
    }
}

/// Log parameter validation warnings (similar to Vaultwarden's parameter guard warnings)
pub fn log_parameter_validation_warning(
    endpoint: &str,
    parameter: &str,
    expected: &str,
    received: &str,
) {
    warn!(
        target: "chiikawarden::api::validation",
        endpoint = endpoint,
        parameter = parameter,
        expected = expected,
        received = received,
        "[WARN] Parameter validation failed for {} on {}: expected {}, got {}",
        parameter,
        endpoint,
        expected,
        received
    );
}

/// Log icon download failures (similar to Vaultwarden's icon warnings)
pub fn log_icon_download_failure(domain: &str, error: &str) {
    warn!(
        target: "chiikawarden::api::icons",
        domain = domain,
        error = error,
        "[WARN] Failed to download icon for {}: {}",
        domain,
        error
    );
}

/// Log database operation warnings
pub fn log_database_warning(operation: &str, table: &str, warning: &str) {
    warn!(
        target: "chiikawarden::database",
        operation = operation,
        table = table,
        warning = warning,
        "[WARN] Database {} operation on {}: {}",
        operation,
        table,
        warning
    );
}

/// Log configuration warnings
pub fn log_config_warning(config_key: &str, issue: &str, suggestion: Option<&str>) {
    if let Some(suggestion) = suggestion {
        warn!(
            target: "chiikawarden::config",
            config_key = config_key,
            issue = issue,
            suggestion = suggestion,
            "[WARN] Configuration issue with {}: {}. Suggestion: {}",
            config_key,
            issue,
            suggestion
        );
    } else {
        warn!(
            target: "chiikawarden::config",
            config_key = config_key,
            issue = issue,
            "[WARN] Configuration issue with {}: {}",
            config_key,
            issue
        );
    }
}

/// Log network timeout warnings
pub fn log_network_timeout_warning(endpoint: &str, timeout_ms: u64, operation: &str) {
    warn!(
        target: "chiikawarden::api::network",
        endpoint = endpoint,
        timeout_ms = timeout_ms,
        operation = operation,
        "[WARN] Network timeout after {}ms for {} operation on {}",
        timeout_ms,
        operation,
        endpoint
    );
}

/// Log rate limiting warnings
pub fn log_rate_limit_warning(endpoint: &str, client_info: &str, retry_after: Option<u64>) {
    if let Some(retry_after) = retry_after {
        warn!(
            target: "chiikawarden::api::ratelimit",
            endpoint = endpoint,
            client_info = client_info,
            retry_after = retry_after,
            "[WARN] Rate limit exceeded for {} on {} (retry after {}s)",
            client_info,
            endpoint,
            retry_after
        );
    } else {
        warn!(
            target: "chiikawarden::api::ratelimit",
            endpoint = endpoint,
            client_info = client_info,
            "[WARN] Rate limit exceeded for {} on {}",
            client_info,
            endpoint
        );
    }
}

/// Log application errors
pub fn log_application_error(error: &dyn std::error::Error, context: &str) {
    error!(
        error = %error,
        context = context,
        "Application error occurred"
    );
}

/// Security event severity levels
#[derive(Debug, Clone, Copy)]
pub enum SecuritySeverity {
    Info,
    Warning,
    Critical,
}

/// Audit log entry for compliance
#[derive(Debug, Clone)]
pub struct AuditLogEntry {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub user_id: Option<String>,
    pub action: String,
    pub resource_type: String,
    pub resource_id: Option<String>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub success: bool,
    pub details: Option<String>,
}

impl AuditLogEntry {
    pub fn new(action: String, resource_type: String) -> Self {
        Self {
            timestamp: chrono::Utc::now(),
            user_id: None,
            action,
            resource_type,
            resource_id: None,
            ip_address: None,
            user_agent: None,
            success: true,
            details: None,
        }
    }

    pub fn with_user_id(mut self, user_id: String) -> Self {
        self.user_id = Some(user_id);
        self
    }

    pub fn with_resource_id(mut self, resource_id: String) -> Self {
        self.resource_id = Some(resource_id);
        self
    }

    pub fn with_success(mut self, success: bool) -> Self {
        self.success = success;
        self
    }

    pub fn with_details(mut self, details: String) -> Self {
        self.details = Some(details);
        self
    }

    pub fn log(self) {
        info!(
            timestamp = %self.timestamp,
            user_id = self.user_id.as_deref().unwrap_or("unknown"),
            action = %self.action,
            resource_type = %self.resource_type,
            resource_id = self.resource_id.as_deref().unwrap_or("unknown"),
            success = self.success,
            details = self.details.as_deref().unwrap_or(""),
            "Audit log entry"
        );
    }
}

/// Logging guard to ensure proper cleanup of log writers
#[derive(Debug)]
pub struct LoggingGuard {
    _info_guard: WorkerGuard,
    _error_guard: WorkerGuard,
}

/// Demonstrate the logging integration with tauri-plugin-log
///
/// This function shows how tracing logs are automatically forwarded to the log crate
/// via the tracing-log bridge, making them available to tauri-plugin-log for
/// frontend console output and file logging.
pub fn demonstrate_logging_integration() {
    // These tracing logs will be automatically forwarded to the log crate
    // and captured by tauri-plugin-log for frontend display

    info!("[demo] This info message will appear in both file logs and frontend console");
    warn!("[demo] This warning will be captured by tauri-plugin-log");
    error!("[demo] This error will be visible in the frontend console");

    // Structured logging with fields
    info!(
        user_id = "demo_user",
        action = "login",
        success = true,
        duration_ms = 150,
        "[demo] Structured log entry with fields"
    );

    // Authentication event logging
    log_auth_event("demo_login", Some("demo_user"), true);
}

/// Test function to verify local timezone logging is working
/// This function logs a message and can be used to verify that timestamps
/// are displayed in the local timezone rather than UTC
pub fn test_local_timezone_logging() {
    info!("Testing local timezone logging - this timestamp should be in your local timezone");
    warn!("Warning message with local timezone");
    error!("Error message with local timezone");
    debug!("Debug message with local timezone");
}

/// Test function specifically for the new Chiikawarden timestamp format
/// This function tests the custom timestamp formatter
pub fn test_chiikawarden_timestamp_format() {
    // Initialize the colored logging to test our custom formatter
    if let Err(e) = init_colored_logging() {
        eprintln!("Failed to initialize logging: {}", e);
        return;
    }

    info!("Testing Chiikawarden timestamp format - should show [YYYY-MM-DD][HH:MM:SS]");
    warn!("Warning with Chiikawarden format");
    error!("Error with Chiikawarden format");
    debug!("Debug with Chiikawarden format");
}
