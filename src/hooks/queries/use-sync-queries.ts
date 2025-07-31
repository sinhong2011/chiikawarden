// src/hooks/queries/use-sync-queries.ts

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { syncService } from "@/services/sync.service";
import type { SyncResult, SyncStatusResponse } from "@/services/sync.service";

// Query keys for sync operations
export const syncKeys = {
  all: ["sync"] as const,
  status: (userId: string) => [...syncKeys.all, "status", userId] as const,
};

/**
 * Hook to get sync status for a user
 */
export function useSyncStatus(userId: string | null) {
  return useQuery({
    queryKey: syncKeys.status(userId || ""),
    queryFn: () => {
      if (!userId) {
        throw new Error("User ID is required for sync status");
      }
      return syncService.getSyncStatus(userId);
    },
    enabled: !!userId,
    staleTime: 30 * 1000, // 30 seconds
    refetchInterval: 60 * 1000, // Refetch every minute
  });
}

/**
 * Hook to sync vault data
 */
export function useSyncVault() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (userId: string): Promise<SyncResult> => {
      return syncService.syncVault(userId);
    },
    onSuccess: (data, userId) => {
      // Invalidate sync status to get fresh data
      queryClient.invalidateQueries({
        queryKey: syncKeys.status(userId),
      });

      // Invalidate vault-related queries to show fresh data
      queryClient.invalidateQueries({
        queryKey: ["vault"],
      });

      // Invalidate cipher queries
      queryClient.invalidateQueries({
        queryKey: ["ciphers"],
      });

      // Invalidate folder queries
      queryClient.invalidateQueries({
        queryKey: ["folders"],
      });

      // Invalidate collection queries
      queryClient.invalidateQueries({
        queryKey: ["collections"],
      });
    },
    onError: (error, userId) => {
      console.error("Vault sync failed:", error);
      
      // Invalidate sync status to reflect error state
      queryClient.invalidateQueries({
        queryKey: syncKeys.status(userId),
      });
    },
  });
}

/**
 * Hook to trigger automatic sync after login
 * This is a specialized version that handles post-login sync
 */
export function usePostLoginSync() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (userId: string): Promise<SyncResult> => {
      return syncService.syncVault(userId);
    },
    onSuccess: (data, userId) => {
      // Invalidate all vault-related data after successful login sync
      queryClient.invalidateQueries({
        queryKey: ["vault"],
      });

      queryClient.invalidateQueries({
        queryKey: ["ciphers"],
      });

      queryClient.invalidateQueries({
        queryKey: ["folders"],
      });

      queryClient.invalidateQueries({
        queryKey: ["collections"],
      });

      queryClient.invalidateQueries({
        queryKey: syncKeys.status(userId),
      });

      // Prefetch sync status for immediate availability
      queryClient.prefetchQuery({
        queryKey: syncKeys.status(userId),
        queryFn: () => syncService.getSyncStatus(userId),
        staleTime: 30 * 1000,
      });
    },
    onError: (error, userId) => {
      console.error("Post-login sync failed:", error);
      
      // Still invalidate sync status to reflect current state
      queryClient.invalidateQueries({
        queryKey: syncKeys.status(userId),
      });
    },
  });
}
