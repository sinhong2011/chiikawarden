// src/services/sync.service.ts

import { commands } from "@/lib/tauri-commands";

// Re-export types from tauri-commands for convenience
export type {
  AppError,
  SyncVaultRequest,
  GetSyncStatusRequest,
  SyncStatusResponse,
  SyncResult,
} from "@/lib/tauri-commands";

export const syncService = {
  /**
   * Sync vault data with server
   * Access tokens are retrieved internally from secure storage
   */
  async syncVault(userId: string) {
    const request = {
      user_id: userId,
    };

    const result = await commands.syncVault(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Get sync status for a user
   */
  async getSyncStatus(userId: string) {
    const request = {
      user_id: userId,
    };

    const result = await commands.getSyncStatus(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },
};
