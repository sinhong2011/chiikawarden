// Frontend logging integration with Tauri backend
// This module bridges frontend console logs to the structured backend logging system
// Note: Uses direct invoke as log_frontend_message is not exposed in typed commands

import { invoke } from "@tauri-apps/api/core";
import { attachConsole } from "@tauri-apps/plugin-log";
import { type LogEntry, LogLevel } from "./logging";

// Track if console integration is already set up
let consoleIntegrationSetup = false;

// Rate limiting for duplicate log prevention
const logRateLimiter = new Map<string, { count: number; lastLogged: number }>();
const RATE_LIMIT_WINDOW = 5000; // 5 seconds
const MAX_LOGS_PER_WINDOW = 3;

// Store original console methods
const originalConsole = {
  log: console.log,
  debug: console.debug,
  info: console.info,
  warn: console.warn,
  error: console.error,
};

/**
 * Enhanced log entry interface for console integration
 */
interface ConsoleLogEntry extends Omit<LogEntry, "level"> {
  level: LogLevel;
  timestamp?: string;
  source: "console" | "manual";
  args?: unknown[];
}

/**
 * Extract component name from stack trace or use default
 */
function extractComponentFromStack(stack?: string): string {
  if (!stack) return "frontend";

  // Try to extract component from stack trace
  const stackLines = stack.split("\n");
  for (const line of stackLines) {
    // Look for patterns like /src/components/ComponentName.tsx
    const match = line.match(/\/src\/(?:components|pages|lib)\/([^/]+)\.(?:tsx?|jsx?)/);
    if (match) {
      return match[1].toLowerCase();
    }
  }

  return "frontend";
}

/**
 * Format console arguments into a readable message
 */
function formatConsoleArgs(args: unknown[]): {
  message: string;
  context?: Record<string, unknown>;
} {
  if (args.length === 0) {
    return { message: "" };
  }

  const message = args[0]?.toString() || "";
  const context: Record<string, unknown> = {};

  // If there are additional arguments, include them as context
  if (args.length > 1) {
    args.slice(1).forEach((arg, index) => {
      if (typeof arg === "object" && arg !== null) {
        // Merge object arguments into context
        if (Array.isArray(arg)) {
          context[`arg_${index + 1}`] = arg;
        } else {
          Object.assign(context, arg);
        }
      } else {
        context[`arg_${index + 1}`] = arg;
      }
    });
  }

  return {
    message,
    context: Object.keys(context).length > 0 ? context : undefined,
  };
}

/**
 * Check if we're running in a Tauri environment
 */
function isTauriEnvironment(): boolean {
  return typeof window !== "undefined" && "tauri" in window && "__TAURI__" in window;
}

/**
 * Check if a log should be rate limited
 */
function shouldRateLimit(message: string): boolean {
  const now = Date.now();
  const key = message.substring(0, 100); // Use first 100 chars as key
  const existing = logRateLimiter.get(key);

  if (!existing) {
    logRateLimiter.set(key, { count: 1, lastLogged: now });
    return false;
  }

  // Reset if outside time window
  if (now - existing.lastLogged > RATE_LIMIT_WINDOW) {
    logRateLimiter.set(key, { count: 1, lastLogged: now });
    return false;
  }

  // Check if we've exceeded the limit
  if (existing.count >= MAX_LOGS_PER_WINDOW) {
    return true;
  }

  // Increment count
  existing.count++;
  return false;
}

/**
 * Send log entry to backend with error handling and rate limiting
 */
async function sendLogToBackend(entry: ConsoleLogEntry): Promise<void> {
  // Rate limit repetitive messages
  if (shouldRateLimit(entry.message as string)) {
    return;
  }

  // Only try to send to backend if we're in a Tauri environment
  if (!isTauriEnvironment()) {
    // In browser mode, just use console logging (don't duplicate)
    return;
  }

  try {
    // Convert to the format expected by log_frontend_message
    const backendEntry: LogEntry = {
      level: entry.level,
      message: entry.message as string,
      context: entry.context as Record<string, unknown> | undefined,
      component: entry.component as string | undefined,
      errorId: entry.errorId as string | undefined,
      severity: entry.severity as string | undefined,
    };

    await invoke("log_frontend_message", { entry: backendEntry });
  } catch (error) {
    // Fallback to original console if backend logging fails (but don't duplicate)
    if (import.meta.env.DEV) {
      originalConsole.error("Failed to send log to backend:", error);
    }
  }
}

/**
 * Create enhanced console method that forwards to backend
 */
function createEnhancedConsoleMethod(
  level: LogLevel,
  originalMethod: (...args: unknown[]) => void
) {
  return (...args: unknown[]) => {
    // Always call original method for immediate feedback
    originalMethod.apply(console, args);

    // Extract component from stack trace
    const stack = new Error().stack;
    const component = extractComponentFromStack(stack);

    // Format arguments
    const { message, context } = formatConsoleArgs(args);

    // Create log entry
    const entry: ConsoleLogEntry = {
      level,
      message,
      context,
      component,
      source: "console",
      timestamp: new Date().toISOString(),
      args,
    };

    // Send to backend asynchronously (don't block console output)
    sendLogToBackend(entry).catch(() => {
      // Error already handled in sendLogToBackend
    });
  };
}

/**
 * Initialize console integration with backend logging
 */
export async function initializeConsoleIntegration(): Promise<void> {
  if (consoleIntegrationSetup) {
    return;
  }

  try {
    // Only try Tauri-specific operations if we're in a Tauri environment
    if (isTauriEnvironment()) {
      // Try to set up Tauri's attachConsole for basic integration
      // This may fail due to Origin header issues in some configurations
      try {
        await attachConsole();
        originalConsole.info("Tauri console attachment successful");
      } catch (attachError) {
        originalConsole.warn(
          "Tauri console attachment failed, continuing with fallback logging:",
          attachError
        );
        // Continue with setup even if attachConsole fails
      }
    } else {
      originalConsole.info("Running in browser mode, skipping Tauri console attachment");
    }

    // Set up enhanced console methods to forward to our structured backend
    console.debug = createEnhancedConsoleMethod(LogLevel.Debug, originalConsole.debug);
    console.info = createEnhancedConsoleMethod(LogLevel.Info, originalConsole.info);
    console.log = createEnhancedConsoleMethod(LogLevel.Info, originalConsole.log); // Treat log as info
    console.warn = createEnhancedConsoleMethod(LogLevel.Warn, originalConsole.warn);
    console.error = createEnhancedConsoleMethod(LogLevel.Error, originalConsole.error);

    consoleIntegrationSetup = true;

    // Log successful initialization
    console.info("Frontend console logging integration initialized successfully");
  } catch (error) {
    originalConsole.error("Failed to initialize console integration:", error);

    // Set up basic fallback logging even if everything fails
    consoleIntegrationSetup = true;
    originalConsole.warn("Using fallback console logging due to initialization failure");

    // Don't throw the error - allow the app to continue
  }
}

/**
 * Restore original console methods (for testing or cleanup)
 */
export function restoreOriginalConsole(): void {
  console.log = originalConsole.log;
  console.debug = originalConsole.debug;
  console.info = originalConsole.info;
  console.warn = originalConsole.warn;
  console.error = originalConsole.error;
  consoleIntegrationSetup = false;
}

/**
 * Check if console integration is active
 */
export function isConsoleIntegrationActive(): boolean {
  return consoleIntegrationSetup;
}

/**
 * Manual logging function that bypasses console integration
 * Useful for internal logging that shouldn't trigger the enhanced console
 */
export async function logDirect(entry: Omit<ConsoleLogEntry, "source">): Promise<void> {
  const fullEntry: ConsoleLogEntry = {
    ...entry,
    source: "manual",
    timestamp: (entry.timestamp as string) || new Date().toISOString(),
  } as ConsoleLogEntry;

  await sendLogToBackend(fullEntry);
}

// Export types for external use
export type { ConsoleLogEntry };
