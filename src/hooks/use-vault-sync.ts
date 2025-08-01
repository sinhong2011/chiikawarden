import { useMutation } from "@tanstack/react-query";
import { useCallback, useEffect, useRef, useState } from "react";
import { queryClient } from "@/lib/query-client";
import { queryKeys } from "@/lib/query-key";
import { networkAwareSyncService } from "@/services/network-aware-sync.service";
import { useAuthStore } from "@/stores/auth.store";
import type { SyncConfig, SyncOptions, SyncState, SyncTrigger } from "@/types/sync.types";

// Default sync configuration
const DEFAULT_SYNC_CONFIG: SyncConfig = {
  syncThresholdMinutes: 5,
  periodicSyncIntervalMinutes: 15,
  enableBackgroundSync: true,
  enablePeriodicSync: true,
  maxRetryAttempts: 3,
  retryDelayMs: 1000,
};

export const useVaultSync = (config: Partial<SyncConfig> = {}) => {
  const authStore = useAuthStore();
  const syncConfig = { ...DEFAULT_SYNC_CONFIG, ...config };

  // Sync state
  const [syncState, setSyncState] = useState<SyncState>({
    isLoading: false,
    lastSyncTime: null,
    error: null,
    hasChanges: false,
    syncMode: "manual",
    itemsUpdated: 0,
    success: false,
  });

  // Refs for cleanup
  const periodicSyncInterval = useRef<NodeJS.Timeout | null>(null);
  const lastSyncTimeRef = useRef<Date | null>(null);

  // Update last sync time ref when state changes
  useEffect(() => {
    lastSyncTimeRef.current = syncState.lastSyncTime;
  }, [syncState.lastSyncTime]);

  // Sync mutation with network awareness
  const syncMutation = useMutation({
    mutationFn: async ({
      trigger: _trigger,
      options: _options,
    }: {
      trigger: SyncTrigger;
      options?: SyncOptions;
    }) => {
      if (!authStore.userId) {
        throw new Error("No user ID available for sync");
      }

      // Use network-aware sync service for better reliability
      const result = await networkAwareSyncService.syncVault(authStore.userId);

      return {
        success: result.success,
        hasChanges: result.items_synced > 0,
        itemsUpdated: result.items_synced,
        lastSyncTime: new Date(),
        syncMode: result.sync_mode,
      };
    },
    onMutate: ({ trigger }) => {
      setSyncState((prev) => ({
        ...prev,
        isLoading: true,
        error: null,
        syncMode: trigger,
      }));
    },
    onSuccess: (result) => {
      setSyncState((prev) => ({
        ...prev,
        isLoading: false,
        lastSyncTime: result.lastSyncTime,
        hasChanges: result.hasChanges,
        itemsUpdated: result.itemsUpdated,
        success: true,
        error: null,
      }));

      // Invalidate vault queries to refresh UI
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.vault(authStore.userId) });
        queryClient.invalidateQueries({ queryKey: queryKeys.ciphers(authStore.userId) });
        queryClient.invalidateQueries({ queryKey: queryKeys.folders(authStore.userId) });
      }

      // Store last sync time in localStorage for persistence
      try {
        localStorage.setItem("lastVaultSyncTime", result.lastSyncTime.toISOString());
      } catch (error) {
        console.warn("Failed to store last sync time:", error);
      }
    },
    onError: (error, { trigger }) => {
      const errorMessage = error instanceof Error ? error.message : "Sync failed";

      setSyncState((prev) => ({
        ...prev,
        isLoading: false,
        error: errorMessage,
        success: false,
      }));

      console.error(`Vault sync failed (${trigger}):`, error);
    },
  });

  // Get stored last sync time from localStorage
  const getStoredLastSyncTime = useCallback((): Date | null => {
    try {
      const stored = localStorage.getItem("lastVaultSyncTime");
      return stored ? new Date(stored) : null;
    } catch {
      return null;
    }
  }, []);

  // Check if sync is needed based on time threshold
  const shouldSyncAfterUnlock = useCallback((): boolean => {
    if (!syncConfig.enableBackgroundSync) return false;

    const lastSyncTime = lastSyncTimeRef.current || getStoredLastSyncTime();
    if (!lastSyncTime) return true;

    const timeSinceLastSync = Date.now() - lastSyncTime.getTime();
    const thresholdMs = syncConfig.syncThresholdMinutes * 60 * 1000;

    return timeSinceLastSync > thresholdMs;
  }, [syncConfig.enableBackgroundSync, syncConfig.syncThresholdMinutes, getStoredLastSyncTime]);

  // Sync functions for different triggers
  const syncAfterLogin = useCallback(
    async (options: SyncOptions = {}) => {
      return syncMutation.mutateAsync({
        trigger: "login",
        options: { ...options, showProgress: true },
      });
    },
    [syncMutation]
  );

  const syncAfterUnlock = useCallback(
    async (options: SyncOptions = {}) => {
      if (!shouldSyncAfterUnlock() && !options.force) {
        return Promise.resolve({
          success: true,
          hasChanges: false,
          itemsUpdated: 0,
          lastSyncTime: lastSyncTimeRef.current || new Date(),
        });
      }

      return syncMutation.mutateAsync({
        trigger: "unlock",
        options: { ...options, background: true },
      });
    },
    [syncMutation, shouldSyncAfterUnlock]
  );

  const syncManual = useCallback(
    async (options: SyncOptions = {}) => {
      return syncMutation.mutateAsync({
        trigger: "manual",
        options: { ...options, force: true, showProgress: true },
      });
    },
    [syncMutation]
  );

  const syncInBackground = useCallback(
    async (options: SyncOptions = {}) => {
      if (!syncConfig.enableBackgroundSync) return;

      return syncMutation.mutateAsync({
        trigger: "background",
        options: { ...options, background: true },
      });
    },
    [syncMutation, syncConfig.enableBackgroundSync]
  );

  // Create a stable reference to the sync function to avoid dependency issues
  const syncMutateRef = useRef(syncMutation.mutate);
  syncMutateRef.current = syncMutation.mutate;

  // Setup periodic sync
  useEffect(() => {
    if (!syncConfig.enablePeriodicSync || !authStore.isAuthenticated || !authStore.userId) {
      return;
    }

    const intervalMs = syncConfig.periodicSyncIntervalMinutes * 60 * 1000;

    periodicSyncInterval.current = setInterval(() => {
      if (authStore.isAuthenticated && authStore.userId) {
        syncMutateRef.current({ trigger: "periodic", options: { background: true } });
      }
    }, intervalMs);

    return () => {
      if (periodicSyncInterval.current) {
        clearInterval(periodicSyncInterval.current);
        periodicSyncInterval.current = null;
      }
    };
  }, [
    syncConfig.enablePeriodicSync,
    syncConfig.periodicSyncIntervalMinutes,
    authStore.isAuthenticated,
    authStore.userId,
  ]);

  // Load initial sync state from storage
  useEffect(() => {
    const storedLastSyncTime = getStoredLastSyncTime();
    if (storedLastSyncTime) {
      setSyncState((prev) => ({
        ...prev,
        lastSyncTime: storedLastSyncTime,
      }));
    }
  }, [getStoredLastSyncTime]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (periodicSyncInterval.current) {
        clearInterval(periodicSyncInterval.current);
      }
    };
  }, []);

  return {
    // State
    syncState,
    isLoading: syncState.isLoading,
    lastSyncTime: syncState.lastSyncTime,
    error: syncState.error,
    hasChanges: syncState.hasChanges,

    // Actions
    syncAfterLogin,
    syncAfterUnlock,
    syncManual,
    syncInBackground,
    shouldSyncAfterUnlock,

    // Utilities
    clearError: () => setSyncState((prev) => ({ ...prev, error: null })),
    resetSyncState: () =>
      setSyncState({
        isLoading: false,
        lastSyncTime: null,
        error: null,
        hasChanges: false,
        syncMode: "manual",
        itemsUpdated: 0,
        success: false,
      }),
  };
};
