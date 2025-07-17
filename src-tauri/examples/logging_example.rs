// Example demonstrating the integrated logging system
// Run with: cargo run --example logging_example

use chiikawarden_lib::logging;
use tracing::{debug, error, info, warn};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize the comprehensive logging system
    let _logging_guard = logging::init_logging()?;

    // Log application startup
    logging::log_startup();

    // Demonstrate various logging levels and structured logging
    info!("[example] Starting logging demonstration");

    // Basic logging
    debug!("[example] This is a debug message");
    info!("[example] This is an info message");
    warn!("[example] This is a warning message");
    error!("[example] This is an error message");

    // Structured logging with fields
    info!(
        component = "auth",
        user_id = "example_user",
        action = "login",
        success = true,
        duration_ms = 125,
        "[example] Structured authentication log"
    );

    // Use the specialized logging functions
    logging::log_auth_event("example_login", Some("test_user"), true);
    logging::log_http_request("GET", "/api/vault", true);
    logging::log_http_response("GET", "/api/vault", 200, 45);

    // Demonstrate the integration
    logging::demonstrate_logging_integration();

    info!("[example] Logging demonstration completed");

    // Keep the program running briefly to ensure all logs are flushed
    std::thread::sleep(std::time::Duration::from_millis(500));

    Ok(())
}
