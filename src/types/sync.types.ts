/**
 * Sync-related types for vault synchronization
 */

export interface SyncState {
  isLoading: boolean;
  lastSyncTime: Date | null;
  error: string | null;
  hasChanges: boolean;
  syncMode: "login" | "unlock" | "background" | "manual" | "periodic";
  itemsUpdated: number;
  success: boolean;
}

export interface SyncResult {
  success: boolean;
  hasChanges: boolean;
  itemsUpdated: number;
  lastSyncTime: Date;
  error?: string;
}

export interface SyncOptions {
  force?: boolean;
  background?: boolean;
  showProgress?: boolean;
}

export interface SyncNotification {
  type: "success" | "error" | "info" | "warning";
  message: string;
  details?: string;
  duration?: number;
}

export type SyncTrigger = "login" | "unlock" | "manual" | "periodic" | "background";

export interface SyncConfig {
  syncThresholdMinutes: number;
  periodicSyncIntervalMinutes: number;
  enableBackgroundSync: boolean;
  enablePeriodicSync: boolean;
  maxRetryAttempts: number;
  retryDelayMs: number;
}
