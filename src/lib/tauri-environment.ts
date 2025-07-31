/**
 * Tauri Environment Detection and Graceful Handling
 *
 * This module provides utilities to detect if the application is running
 * in a Tauri environment and handle browser fallbacks gracefully.
 */

// Extend Window interface to include Tauri
declare global {
  interface Window {
    __TAURI__?: {
      core?: {
        invoke?: (...args: unknown[]) => unknown;
      };
    };
  }
}

// Check if we're running in Tauri environment
export const isTauriEnvironment = (): boolean => {
  try {
    return (
      typeof window !== "undefined" &&
      window.__TAURI__ !== undefined &&
      typeof window.__TAURI__.core?.invoke === "function"
    );
  } catch {
    return false;
  }
};

// Check if we're in development mode
export const isDevelopmentMode = (): boolean => {
  return (
    process.env.NODE_ENV === "development" || (typeof __DEV__ !== "undefined" && Boolean(__DEV__))
  );
};

// Browser environment error for Tauri commands
export class TauriEnvironmentError extends Error {
  constructor(command: string) {
    super(
      `Tauri command '${command}' called in browser environment. ` +
        `This application requires the Tauri desktop runtime to function properly.`
    );
    this.name = "TauriEnvironmentError";
  }
}

// Mock result for browser environment
export const createBrowserMockResult = (
  command: string
): { status: "error"; error: TauriEnvironmentError } => {
  return {
    status: "error" as const,
    error: new TauriEnvironmentError(command),
  };
};

// Environment-aware logging
export const logEnvironmentWarning = (command: string): void => {
  if (isDevelopmentMode()) {
    console.warn(
      `[TauriEnvironment] Command '${command}' called in browser mode. ` +
        `Run 'bun run tauri dev' to use the desktop application.`
    );
  }
};

// Safe environment check with user-friendly messaging
export const checkTauriEnvironment = (command: string): boolean => {
  const isAvailable = isTauriEnvironment();

  if (!isAvailable) {
    logEnvironmentWarning(command);
  }

  return isAvailable;
};
