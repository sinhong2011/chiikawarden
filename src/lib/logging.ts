// Frontend logging utilities for Chiikawarden
// Note: Uses direct invoke as logging commands are not exposed in typed commands
import { invoke } from "@tauri-apps/api/core";

export enum LogLevel {
  Debug = "debug",
  Info = "info",
  Warn = "warn",
  Error = "error",
}

export interface LogEntry extends Record<string, unknown> {
  level: LogLevel;
  message: string;
  context?: Record<string, unknown>;
  component?: string;
  errorId?: string;
  severity?: string;
}

/**
 * Log a message to the backend logging system
 */
export async function logMessage(entry: LogEntry): Promise<void> {
  try {
    if (typeof window !== "undefined" && "tauri" in window) {
      await invoke("log_frontend_message", entry);
    } else {
      // Fallback to console logging in non-Tauri environments
      const logFn = console[entry.level] || console.log;
      logFn(`[${entry.component || "frontend"}] ${entry.message}`, entry.context);
    }
  } catch (error) {
    console.error("Failed to log message:", error);
    console.log(`[${entry.component || "frontend"}] ${entry.message}`, entry.context);
  }
}

/**
 * Log an error with context
 */
export async function logError(
  message: string,
  error?: Error,
  context?: Record<string, unknown>,
  component?: string
): Promise<void> {
  const errorContext = {
    ...context,
    ...(error && {
      errorName: error.name,
      errorMessage: error.message,
      errorStack: error.stack,
    }),
  };

  await logMessage({
    level: LogLevel.Error,
    message,
    context: errorContext,
    component,
    severity: "high",
  });
}

/**
 * Log a warning
 */
export async function logWarning(
  message: string,
  context?: Record<string, unknown>,
  component?: string
): Promise<void> {
  await logMessage({
    level: LogLevel.Warn,
    message,
    context,
    component,
    severity: "medium",
  });
}

/**
 * Log an info message
 */
export async function logInfo(
  message: string,
  context?: Record<string, unknown>,
  component?: string
): Promise<void> {
  await logMessage({
    level: LogLevel.Info,
    message,
    context,
    component,
  });
}

/**
 * Log a debug message (only in development)
 */
export async function logDebug(
  message: string,
  context?: Record<string, unknown>,
  component?: string
): Promise<void> {
  if (import.meta.env.DEV) {
    await logMessage({
      level: LogLevel.Debug,
      message,
      context,
      component,
    });
  }
}

/**
 * Log a user action for audit purposes
 */
export async function logUserAction(
  action: string,
  resourceType: string,
  resourceId?: string,
  userId?: string,
  success: boolean = true,
  details?: string
): Promise<void> {
  try {
    if (typeof window !== "undefined" && "tauri" in window) {
      await invoke("log_user_action", {
        action,
        resourceType,
        resourceId,
        userId,
        success,
        details,
      });
    } else {
      console.log(`[UserAction] ${action} on ${resourceType}`, {
        resourceId,
        userId,
        success,
        details,
      });
    }
  } catch (error) {
    console.error("Failed to log user action:", error);
  }
}
