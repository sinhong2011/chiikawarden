import { useNavigate } from "@tanstack/react-router";
import { listen } from "@tauri-apps/api/event";
import { useCallback, useEffect, useRef } from "react";
import { logDebug, logError, logInfo } from "@/lib/logging";
import type {
  ActivityEvent,
  ActivitySensitivity,
  AutoLockStatusResponse,
  StartAutoLockRequest,
  UpdateAutoLockConfigRequest,
  VaultTimeout,
  VaultTimeoutEvent,
} from "@/lib/tauri-commands";
import { commands } from "@/lib/tauri-commands";
import { isTauriEnvironment } from "@/lib/tauri-environment";
import { useAuthStore } from "@/stores/auth.store";

export interface AutoLockConfig {
  enabled: boolean;
  timeout: VaultTimeout;
  activitySensitivity: ActivitySensitivity;
}

export interface AutoLockStatus {
  isMonitoring: boolean;
  currentUserId: string | null;
  config: AutoLockConfig;
}

export interface UseAutoLockReturn {
  // Status
  status: AutoLockStatus | null;
  isLoading: boolean;
  error: string | null;

  // Actions
  startMonitoring: (userId: string, config: AutoLockConfig) => Promise<void>;
  stopMonitoring: () => Promise<void>;
  updateConfig: (config: AutoLockConfig) => Promise<void>;
  resetActivityTimer: () => Promise<void>;
  triggerManualLock: (userId: string) => Promise<void>;

  // Utilities
  refreshStatus: () => Promise<void>;
  isSupported: () => Promise<boolean>;
  getRecommendedSettings: () => Promise<AutoLockConfig>;
}

/**
 * Hook for managing auto-lock functionality
 * Handles activity detection, timeout management, and automatic vault locking
 */
export const useAutoLock = (): UseAutoLockReturn => {
  const navigate = useNavigate();
  const authStore = useAuthStore();

  // State
  const statusRef = useRef<AutoLockStatus | null>(null);
  const isLoadingRef = useRef(false);
  const errorRef = useRef<string | null>(null);
  const unlistenersRef = useRef<Array<() => void>>([]);

  // Initialize event listeners
  useEffect(() => {
    if (!isTauriEnvironment()) {
      logDebug("Auto-lock not available in non-Tauri environment", {}, "useAutoLock");
      return;
    }

    const setupEventListeners = async () => {
      try {
        // Listen for vault timeout events
        const unlistenTimeout = await listen<VaultTimeoutEvent>("vault_timeout_event", (event) => {
          logDebug("Received vault timeout event", { event: event.payload }, "useAutoLock");

          if ("VaultLockTriggered" in event.payload) {
            handleVaultLockTriggered(
              event.payload.VaultLockTriggered.user_id,
              event.payload.VaultLockTriggered.reason
            );
          } else if ("TimeoutReset" in event.payload) {
            logDebug(
              "Timeout reset",
              {
                userId: event.payload.TimeoutReset.user_id,
                remainingMs: event.payload.TimeoutReset.remaining_ms,
              },
              "useAutoLock"
            );
          } else if ("MonitoringStarted" in event.payload) {
            logInfo(
              "Auto-lock monitoring started",
              {
                userId: event.payload.MonitoringStarted.user_id,
                timeoutMs: event.payload.MonitoringStarted.timeout_ms,
              },
              "useAutoLock"
            );
          } else if ("MonitoringStopped" in event.payload) {
            logInfo(
              "Auto-lock monitoring stopped",
              {
                userId: event.payload.MonitoringStopped.user_id,
              },
              "useAutoLock"
            );
          }
        });

        // Listen for activity events
        const unlistenActivity = await listen<ActivityEvent>("activity_event", (event) => {
          logDebug("Received activity event", { event: event.payload }, "useAutoLock");

          if (event.payload === "UserActive") {
            logDebug("User activity detected", {}, "useAutoLock");
          } else if (typeof event.payload === "object" && "UserIdle" in event.payload) {
            logDebug(
              "User idle detected",
              {
                idleDurationMs: event.payload.UserIdle.idle_duration_ms,
              },
              "useAutoLock"
            );
          } else if (event.payload === "MonitoringStarted") {
            logInfo("Activity monitoring started", {}, "useAutoLock");
          } else if (event.payload === "MonitoringStopped") {
            logInfo("Activity monitoring stopped", {}, "useAutoLock");
          }
        });

        unlistenersRef.current = [unlistenTimeout, unlistenActivity];
      } catch (error) {
        logError(
          "Failed to setup auto-lock event listeners",
          error instanceof Error ? error : new Error(String(error)),
          {},
          "useAutoLock"
        );
        errorRef.current = `Failed to setup event listeners: ${error}`;
      }
    };

    setupEventListeners();

    // Cleanup on unmount
    return () => {
      unlistenersRef.current.forEach((unlisten) => unlisten());
      unlistenersRef.current = [];
    };
  }, []);

  // Handle vault lock triggered
  const handleVaultLockTriggered = useCallback(
    async (userId: string, reason: string) => {
      try {
        logInfo("Vault lock triggered", { userId, reason }, "useAutoLock");

        // Lock the vault in the auth store
        if (authStore.userId === userId) {
          await authStore.lockVault();

          // Navigate to unlock screen
          navigate({ to: "/unlock" });

          logInfo(
            "Successfully locked vault and navigated to unlock screen",
            { userId },
            "useAutoLock"
          );
        } else {
          logDebug(
            "Lock triggered for different user, ignoring",
            {
              triggeredUserId: userId,
              currentUserId: authStore.userId,
            },
            "useAutoLock"
          );
        }
      } catch (error) {
        logError(
          "Failed to handle vault lock trigger",
          error instanceof Error ? error : new Error(String(error)),
          { userId, reason },
          "useAutoLock"
        );
        errorRef.current = `Failed to lock vault: ${error}`;
      }
    },
    [authStore, navigate]
  );

  // Start monitoring
  const startMonitoring = useCallback(async (userId: string, config: AutoLockConfig) => {
    if (!isTauriEnvironment()) {
      throw new Error("Auto-lock not available in non-Tauri environment");
    }

    try {
      isLoadingRef.current = true;
      errorRef.current = null;

      const request: StartAutoLockRequest = {
        user_id: userId,
        timeout: config.timeout,
        enabled: config.enabled,
      };

      const result = await commands.startAutoLockMonitoring(request);
      if (result.status === "error") {
        throw new Error(JSON.stringify(result.error));
      }

      logInfo("Auto-lock monitoring started", { userId, config }, "useAutoLock");

      // Refresh status
      await refreshStatus();
    } catch (error) {
      logError(
        "Failed to start auto-lock monitoring",
        error instanceof Error ? error : new Error(String(error)),
        { userId, config },
        "useAutoLock"
      );
      errorRef.current = `Failed to start monitoring: ${error}`;
      throw error;
    } finally {
      isLoadingRef.current = false;
    }
  }, []);

  // Stop monitoring
  const stopMonitoring = useCallback(async () => {
    if (!isTauriEnvironment()) {
      throw new Error("Auto-lock not available in non-Tauri environment");
    }

    try {
      isLoadingRef.current = true;
      errorRef.current = null;

      const result = await commands.stopAutoLockMonitoring();
      if (result.status === "error") {
        throw new Error(JSON.stringify(result.error));
      }

      logInfo("Auto-lock monitoring stopped", {}, "useAutoLock");

      // Refresh status
      await refreshStatus();
    } catch (error) {
      logError(
        "Failed to stop auto-lock monitoring",
        error instanceof Error ? error : new Error(String(error)),
        {},
        "useAutoLock"
      );
      errorRef.current = `Failed to stop monitoring: ${error}`;
      throw error;
    } finally {
      isLoadingRef.current = false;
    }
  }, []);

  // Update configuration
  const updateConfig = useCallback(async (config: AutoLockConfig) => {
    if (!isTauriEnvironment()) {
      throw new Error("Auto-lock not available in non-Tauri environment");
    }

    try {
      isLoadingRef.current = true;
      errorRef.current = null;

      const request: UpdateAutoLockConfigRequest = {
        timeout: config.timeout,
        enabled: config.enabled,
        activity_sensitivity: config.activitySensitivity,
      };

      const result = await commands.updateAutoLockConfig(request);
      if (result.status === "error") {
        throw new Error(JSON.stringify(result.error));
      }

      logInfo("Auto-lock configuration updated", { config }, "useAutoLock");

      // Refresh status
      await refreshStatus();
    } catch (error) {
      logError(
        "Failed to update auto-lock configuration",
        error instanceof Error ? error : new Error(String(error)),
        { config },
        "useAutoLock"
      );
      errorRef.current = `Failed to update configuration: ${error}`;
      throw error;
    } finally {
      isLoadingRef.current = false;
    }
  }, []);

  // Reset activity timer
  const resetActivityTimer = useCallback(async () => {
    if (!isTauriEnvironment()) {
      return; // Silently ignore in non-Tauri environment
    }

    try {
      const result = await commands.resetActivityTimer();
      if (result.status === "error") {
        logError(
          "Failed to reset activity timer",
          new Error(JSON.stringify(result.error)),
          {},
          "useAutoLock"
        );
      }
    } catch (error) {
      logError(
        "Failed to reset activity timer",
        error instanceof Error ? error : new Error(String(error)),
        {},
        "useAutoLock"
      );
    }
  }, []);

  // Trigger manual lock
  const triggerManualLock = useCallback(async (userId: string) => {
    if (!isTauriEnvironment()) {
      throw new Error("Auto-lock not available in non-Tauri environment");
    }

    try {
      const result = await commands.triggerManualLock(userId);
      if (result.status === "error") {
        throw new Error(JSON.stringify(result.error));
      }

      logInfo("Manual vault lock triggered", { userId }, "useAutoLock");
    } catch (error) {
      logError(
        "Failed to trigger manual lock",
        error instanceof Error ? error : new Error(String(error)),
        { userId },
        "useAutoLock"
      );
      errorRef.current = `Failed to trigger manual lock: ${error}`;
      throw error;
    }
  }, []);

  // Refresh status
  const refreshStatus = useCallback(async () => {
    if (!isTauriEnvironment()) {
      statusRef.current = null;
      return;
    }

    try {
      const result = await commands.getAutoLockStatus();
      if (result.status === "error") {
        throw new Error(JSON.stringify(result.error));
      }

      const response = result.data;
      statusRef.current = {
        isMonitoring: response.monitoring_enabled,
        currentUserId: response.current_user_id,
        config: {
          enabled: response.monitoring_enabled,
          timeout: response.timeout_config,
          activitySensitivity: response.activity_sensitivity,
        },
      };

      logDebug("Auto-lock status refreshed", { status: statusRef.current }, "useAutoLock");
    } catch (error) {
      logError(
        "Failed to refresh auto-lock status",
        error instanceof Error ? error : new Error(String(error)),
        {},
        "useAutoLock"
      );
      errorRef.current = `Failed to refresh status: ${error}`;
    }
  }, []);

  // Check if auto-lock is supported
  const isSupported = useCallback(async (): Promise<boolean> => {
    if (!isTauriEnvironment()) {
      return false;
    }

    try {
      const result = await commands.checkAutoLockSupport();
      return result.status === "ok" ? result.data : false;
    } catch (error) {
      logError(
        "Failed to check auto-lock support",
        error instanceof Error ? error : new Error(String(error)),
        {},
        "useAutoLock"
      );
      return false;
    }
  }, []);

  // Get recommended settings
  const getRecommendedSettings = useCallback(async (): Promise<AutoLockConfig> => {
    if (!isTauriEnvironment()) {
      return {
        enabled: true,
        timeout: { Minutes: 15 },
        activitySensitivity: "Medium",
      };
    }

    try {
      const result = await commands.getRecommendedAutoLockSettings();
      if (result.status === "error") {
        throw new Error(JSON.stringify(result.error));
      }

      const response = result.data;
      return {
        enabled: response.enabled,
        timeout: response.timeout,
        activitySensitivity: response.activity_sensitivity,
      };
    } catch (error) {
      logError(
        "Failed to get recommended auto-lock settings",
        error instanceof Error ? error : new Error(String(error)),
        {},
        "useAutoLock"
      );
      // Return default settings
      return {
        enabled: true,
        timeout: { Minutes: 15 },
        activitySensitivity: "Medium",
      };
    }
  }, []);

  return {
    status: statusRef.current,
    isLoading: isLoadingRef.current,
    error: errorRef.current,
    startMonitoring,
    stopMonitoring,
    updateConfig,
    resetActivityTimer,
    triggerManualLock,
    refreshStatus,
    isSupported,
    getRecommendedSettings,
  };
};
