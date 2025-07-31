// src/hooks/queries/use-network-aware-sync.ts

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { listen } from "@tauri-apps/api/event";
import { useEffect } from "react";
import {
  type CanWriteResponse,
  commands,
  type NetworkAwareSyncResult,
  type NetworkStatus,
  type WebSocketStatus,
} from "@/lib/tauri";
import { useAuthStore } from "@/stores/auth.store";

// Query keys for network-aware sync operations
export const networkAwareSyncKeys = {
  all: ["network-aware-sync"] as const,
  status: (userId: string) => [...networkAwareSyncKeys.all, "status", userId] as const,
  networkStatus: () => [...networkAwareSyncKeys.all, "network-status"] as const,
  syncMode: (userId: string) => [...networkAwareSyncKeys.all, "sync-mode", userId] as const,
  websocketStatus: () => [...networkAwareSyncKeys.all, "websocket-status"] as const,
  canWrite: (userId: string) => [...networkAwareSyncKeys.all, "can-write", userId] as const,
};

/**
 * Hook to get network status
 */
export function useNetworkStatus() {
  return useQuery({
    queryKey: networkAwareSyncKeys.networkStatus(),
    queryFn: async (): Promise<NetworkStatus> => {
      const result = await commands.getNetworkStatus({});
      if (result.status === "error") {
        throw result.error;
      }
      return result.data;
    },
    staleTime: 10 * 1000, // 10 seconds
    refetchInterval: 30 * 1000, // Refetch every 30 seconds
  });
}

/**
 * Hook to get network-aware sync status
 */
export function useNetworkAwareSyncStatus(userId: string | null) {
  return useQuery({
    queryKey: networkAwareSyncKeys.status(userId || ""),
    queryFn: async (): Promise<NetworkAwareSyncResult> => {
      if (!userId) {
        throw new Error("User ID is required for sync status");
      }
      const result = await commands.getNetworkAwareSyncStatus({ user_id: userId });
      if (result.status === "error") {
        throw result.error;
      }
      return result.data;
    },
    enabled: !!userId,
    staleTime: 30 * 1000, // 30 seconds
    refetchInterval: 60 * 1000, // Refetch every minute
  });
}

/**
 * Hook to get current sync mode
 */
export function useSyncMode(userId: string | null) {
  return useQuery({
    queryKey: networkAwareSyncKeys.syncMode(userId || ""),
    queryFn: async (): Promise<"online" | "offline"> => {
      if (!userId) {
        throw new Error("User ID is required for sync mode");
      }
      const result = await commands.getSyncMode({ user_id: userId });
      if (result.status === "error") {
        throw result.error;
      }
      return result.data;
    },
    enabled: !!userId,
    staleTime: 10 * 1000, // 10 seconds
  });
}

/**
 * Hook to check if user can write (create/update/delete)
 */
export function useCanWrite(userId: string | null) {
  return useQuery({
    queryKey: networkAwareSyncKeys.canWrite(userId || ""),
    queryFn: async (): Promise<CanWriteResponse> => {
      if (!userId) {
        throw new Error("User ID is required for write permissions");
      }
      const result = await commands.canWrite({ user_id: userId });
      if (result.status === "error") {
        throw result.error;
      }
      return result.data;
    },
    enabled: !!userId,
    staleTime: 5 * 1000, // 5 seconds
  });
}

/**
 * Hook to get WebSocket status
 */
export function useWebSocketStatus() {
  return useQuery({
    queryKey: networkAwareSyncKeys.websocketStatus(),
    queryFn: async (): Promise<WebSocketStatus> => {
      const result = await commands.getWebsocketStatus({});
      if (result.status === "error") {
        throw result.error;
      }
      return result.data;
    },
    staleTime: 10 * 1000, // 10 seconds
    refetchInterval: 30 * 1000, // Refetch every 30 seconds
  });
}

/**
 * Hook for network-aware vault synchronization
 */
export function useNetworkAwareSync() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (userId: string): Promise<NetworkAwareSyncResult> => {
      const result = await commands.networkAwareSyncVault({ user_id: userId });
      if (result.status === "error") {
        throw result.error;
      }
      return result.data;
    },
    onSuccess: (data, userId) => {
      // Invalidate network-aware sync queries
      queryClient.invalidateQueries({
        queryKey: networkAwareSyncKeys.status(userId),
      });

      queryClient.invalidateQueries({
        queryKey: networkAwareSyncKeys.syncMode(userId),
      });

      queryClient.invalidateQueries({
        queryKey: networkAwareSyncKeys.canWrite(userId),
      });

      // Invalidate vault-related queries to show fresh data
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
    },
    onError: (error, userId) => {
      console.error("Network-aware sync failed:", error);

      // Invalidate status queries to reflect error state
      queryClient.invalidateQueries({
        queryKey: networkAwareSyncKeys.status(userId),
      });
    },
  });
}

/**
 * Hook to force online synchronization
 */
export function useForceOnlineSync() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (userId: string): Promise<NetworkAwareSyncResult> => {
      const result = await commands.forceOnlineSync({ user_id: userId });
      if (result.status === "error") {
        throw result.error;
      }
      return result.data;
    },
    onSuccess: (data, userId) => {
      // Invalidate all sync-related queries
      queryClient.invalidateQueries({
        queryKey: networkAwareSyncKeys.all,
      });

      // Invalidate vault-related queries
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
    },
    onError: (error) => {
      console.error("Force online sync failed:", error);
    },
  });
}

/**
 * Hook to connect WebSocket for real-time notifications
 */
export function useConnectWebSocket() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (userId: string): Promise<void> => {
      const result = await commands.connectWebsocket({ user_id: userId });
      if (result.status === "error") {
        throw result.error;
      }
    },
    onSuccess: () => {
      // Invalidate WebSocket status
      queryClient.invalidateQueries({
        queryKey: networkAwareSyncKeys.websocketStatus(),
      });
    },
    onError: (error) => {
      console.error("WebSocket connection failed:", error);
    },
  });
}

/**
 * Hook to disconnect WebSocket
 */
export function useDisconnectWebSocket() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (): Promise<void> => {
      const result = await commands.disconnectWebsocket({});
      if (result.status === "error") {
        throw result.error;
      }
    },
    onSuccess: () => {
      // Invalidate WebSocket status
      queryClient.invalidateQueries({
        queryKey: networkAwareSyncKeys.websocketStatus(),
      });
    },
    onError: (error) => {
      console.error("WebSocket disconnection failed:", error);
    },
  });
}

/**
 * Hook to listen for real-time events and update queries accordingly
 */
export function useNetworkAwareEventListeners() {
  const queryClient = useQueryClient();
  const { userId } = useAuthStore();

  useEffect(() => {
    const unlistenPromises: Promise<() => void>[] = [];

    // Listen for network status changes
    unlistenPromises.push(
      listen<NetworkStatus>("network_status_changed", (event) => {
        console.log("Network status changed:", event.payload);
        queryClient.invalidateQueries({
          queryKey: networkAwareSyncKeys.networkStatus(),
        });

        if (userId) {
          queryClient.invalidateQueries({
            queryKey: networkAwareSyncKeys.syncMode(userId),
          });
          queryClient.invalidateQueries({
            queryKey: networkAwareSyncKeys.canWrite(userId),
          });
        }
      })
    );

    // Listen for sync mode changes
    unlistenPromises.push(
      listen<string>("sync_mode_changed", (event) => {
        console.log("Sync mode changed:", event.payload);
        if (userId) {
          queryClient.invalidateQueries({
            queryKey: networkAwareSyncKeys.syncMode(userId),
          });
          queryClient.invalidateQueries({
            queryKey: networkAwareSyncKeys.canWrite(userId),
          });
          queryClient.invalidateQueries({
            queryKey: networkAwareSyncKeys.status(userId),
          });
        }
      })
    );

    // Listen for vault changes (WebSocket notifications)
    unlistenPromises.push(
      listen<string>("vault_changed", (event) => {
        console.log("Vault changed:", event.payload);
        if (userId) {
          // Invalidate all vault-related queries
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
        }
      })
    );

    // Listen for WebSocket connection changes
    unlistenPromises.push(
      listen<string>("websocket_connected", (event) => {
        console.log("WebSocket connected:", event.payload);
        queryClient.invalidateQueries({
          queryKey: networkAwareSyncKeys.websocketStatus(),
        });
      })
    );

    unlistenPromises.push(
      listen<string>("websocket_disconnected", (event) => {
        console.log("WebSocket disconnected:", event.payload);
        queryClient.invalidateQueries({
          queryKey: networkAwareSyncKeys.websocketStatus(),
        });
      })
    );

    // Cleanup listeners on unmount
    return () => {
      Promise.all(unlistenPromises).then((unlisteners) => {
        unlisteners.forEach((unlisten) => unlisten());
      });
    };
  }, [queryClient, userId]);
}
