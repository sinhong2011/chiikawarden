// Application initialization utilities
// Handles setup of logging integration and other app-wide configurations

import { appInitializationService } from "../services/app-initialization.service";
import { logError, logInfo } from "./logging";
import { initializeConsoleIntegration } from "./logging-integration";

/**
 * Initialize all app-wide systems
 */
export async function initializeApp(): Promise<void> {
  const startTime = performance.now();

  try {
    // Initialize console logging integration
    await initializeConsoleIntegration();

    // Initialize app services including preferences migration
    await appInitializationService.initialize();

    const duration = performance.now() - startTime;

    // Use the enhanced console.info which will now forward to backend
    console.info(`App initialization completed in ${duration.toFixed(2)}ms`);

    // Also log through our structured logging system
    await logInfo(
      "Application initialization completed successfully",
      {
        duration_ms: Math.round(duration),
        systems_initialized: ["console_integration", "preferences_migration"],
      },
      "app_initialization"
    );
  } catch (error) {
    const duration = performance.now() - startTime;

    // Log error through console (fallback logging)
    console.error("App initialization encountered an error:", error);

    // Try to log through our structured system if possible
    try {
      await logError(
        "Application initialization encountered an error",
        error instanceof Error ? error : new Error(String(error)),
        {
          duration_ms: Math.round(duration),
          failed_at: "console_integration",
        },
        "app_initialization"
      );
    } catch (logError) {
      console.error("Failed to log initialization error:", logError);
    }

    // Don't throw - allow the app to continue with basic functionality
    console.warn(
      "App initialization completed with errors, but continuing with basic functionality"
    );
  }
}

/**
 * Test logging integration by sending test messages at different levels
 */
export async function testLoggingIntegration(): Promise<void> {
  console.info("Testing logging integration...");

  // Test different console methods
  console.debug("Debug message from console.debug()", { test: "debug_data" });
  console.info("Info message from console.info()", { test: "info_data" });
  console.log("Log message from console.log()", { test: "log_data" });
  console.warn("Warning message from console.warn()", { test: "warn_data" });
  console.error("Error message from console.error()", { test: "error_data" });

  // Test with multiple arguments
  console.info("Multi-argument test:", { key: "value" }, [1, 2, 3], "additional string");

  console.info("Logging integration test completed");
}
