// src/services/network-aware-sync.service.ts

import {
  type CanWriteResponse,
  commands,
  type NetworkAwareSyncResult,
  type NetworkStatus,
  type WebSocketStatus,
} from "@/lib/tauri";

export const networkAwareSyncService = {
  /**
   * Perform network-aware vault synchronization
   * Automatically detects online/offline mode and syncs accordingly
   */
  async syncVault(userId: string): Promise<NetworkAwareSyncResult> {
    const result = await commands.networkAwareSyncVault({ user_id: userId });

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Force online synchronization (will fail if network is unavailable)
   */
  async forceOnlineSync(userId: string): Promise<NetworkAwareSyncResult> {
    const result = await commands.forceOnlineSync({ user_id: userId });

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Get network-aware sync status
   */
  async getSyncStatus(userId: string): Promise<NetworkAwareSyncResult> {
    const result = await commands.getNetworkAwareSyncStatus({ user_id: userId });

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Get current network status
   */
  async getNetworkStatus(): Promise<NetworkStatus> {
    const result = await commands.getNetworkStatus({});

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Get current sync mode for a user
   */
  async getSyncMode(userId: string): Promise<"online" | "offline"> {
    const result = await commands.getSyncMode({ user_id: userId });

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Set sync mode for a user (with network validation)
   */
  async setSyncMode(userId: string, mode: "online" | "offline"): Promise<"online" | "offline"> {
    const result = await commands.setSyncMode({ user_id: userId, mode });

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Check if user can perform write operations
   */
  async canWrite(userId: string): Promise<CanWriteResponse> {
    const result = await commands.canWrite({ user_id: userId });

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Connect WebSocket for real-time notifications
   */
  async connectWebSocket(userId: string): Promise<void> {
    const result = await commands.connectWebsocket({ user_id: userId });

    if (result.status === "error") {
      throw result.error;
    }
  },

  /**
   * Disconnect WebSocket
   */
  async disconnectWebSocket(): Promise<void> {
    const result = await commands.disconnectWebsocket({});

    if (result.status === "error") {
      throw result.error;
    }
  },

  /**
   * Get WebSocket connection status
   */
  async getWebSocketStatus(): Promise<WebSocketStatus> {
    const result = await commands.getWebsocketStatus({});

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Check if currently online (network available and server reachable)
   */
  async isOnline(): Promise<boolean> {
    try {
      const networkStatus = await this.getNetworkStatus();
      return networkStatus.state === "online" && networkStatus.server_reachable;
    } catch {
      return false;
    }
  },

  /**
   * Check if currently offline
   */
  async isOffline(): Promise<boolean> {
    try {
      const networkStatus = await this.getNetworkStatus();
      return networkStatus.state === "offline" || !networkStatus.server_reachable;
    } catch {
      return true; // Assume offline if we can't check
    }
  },

  /**
   * Check if user is in online mode (can perform full CRUD operations)
   */
  async isOnlineMode(userId: string): Promise<boolean> {
    try {
      const syncMode = await this.getSyncMode(userId);
      return syncMode === "online";
    } catch {
      return false;
    }
  },

  /**
   * Check if user is in offline mode (read-only access)
   */
  async isOfflineMode(userId: string): Promise<boolean> {
    try {
      const syncMode = await this.getSyncMode(userId);
      return syncMode === "offline";
    } catch {
      return true; // Assume offline mode if we can't check
    }
  },

  /**
   * Get connection quality information
   */
  async getConnectionQuality() {
    try {
      const networkStatus = await this.getNetworkStatus();
      return networkStatus.quality;
    } catch {
      return {
        latency_ms: null,
        last_successful_ping: null,
        success_rate: 0,
        consecutive_failures: 999,
      };
    }
  },

  /**
   * Check if WebSocket is connected
   */
  async isWebSocketConnected(): Promise<boolean> {
    try {
      const wsStatus = await this.getWebSocketStatus();
      return wsStatus.state === "connected";
    } catch {
      return false;
    }
  },

  /**
   * Get human-readable sync status message
   */
  async getSyncStatusMessage(userId: string): Promise<string> {
    try {
      const syncStatus = await this.getSyncStatus(userId);
      return syncStatus.message;
    } catch (error) {
      return `Sync status unavailable: ${error}`;
    }
  },

  /**
   * Get human-readable network status message
   */
  async getNetworkStatusMessage(): Promise<string> {
    try {
      const networkStatus = await this.getNetworkStatus();

      switch (networkStatus.state) {
        case "online":
          return networkStatus.server_reachable
            ? "Online - Full access available"
            : "Limited connectivity - Server unreachable";
        case "offline":
          return "Offline - No network connection";
        case "limited":
          return "Limited connectivity - Using cached data";
        case "unknown":
        default:
          return "Network status unknown";
      }
    } catch (error) {
      return `Network status unavailable: ${error}`;
    }
  },

  /**
   * Attempt to restore online connectivity
   * This will trigger a network check and potentially reconnect WebSocket
   */
  async attemptReconnection(userId: string): Promise<boolean> {
    try {
      // First check if we can go online
      const networkStatus = await this.getNetworkStatus();

      if (networkStatus.state === "online" && networkStatus.server_reachable) {
        // Try to set online mode
        const actualMode = await this.setSyncMode(userId, "online");

        if (actualMode === "online") {
          // Try to connect WebSocket for real-time updates
          try {
            await this.connectWebSocket(userId);
          } catch (wsError) {
            console.warn("WebSocket connection failed during reconnection:", wsError);
            // Don't fail the whole reconnection if WebSocket fails
          }

          return true;
        }
      }

      return false;
    } catch (error) {
      console.error("Reconnection attempt failed:", error);
      return false;
    }
  },
};
