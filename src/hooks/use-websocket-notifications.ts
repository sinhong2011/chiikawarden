import { useQueryClient } from "@tanstack/react-query";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { useCallback, useEffect, useRef, useState } from "react";
import { commands, type WebSocketNotification, type WebSocketStatus } from "@/lib/tauri";
import { useAuthStore } from "@/stores/auth.store";

interface WebSocketNotificationHook {
  status: WebSocketStatus | null;
  isConnected: boolean;
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
  lastNotification: WebSocketNotification | null;
}

export function useWebSocketNotifications(): WebSocketNotificationHook {
  const [status, setStatus] = useState<WebSocketStatus | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [lastNotification, setLastNotification] = useState<WebSocketNotification | null>(null);

  const queryClient = useQueryClient();
  const { user } = useAuthStore();
  const unlistenersRef = useRef<UnlistenFn[]>([]);

  // Update WebSocket status
  const updateStatus = useCallback(async () => {
    try {
      const result = await commands.getWebsocketStatus({});
      if (result.status === "ok") {
        setStatus(result.data);
        setIsConnected(result.data.state === "connected");
      } else {
        console.error("[websocket] Failed to get status:", result.error);
        setStatus(null);
        setIsConnected(false);
      }
    } catch (error) {
      console.error("[websocket] Failed to get status:", error);
      setStatus(null);
      setIsConnected(false);
    }
  }, []);

  // Connect to WebSocket
  const connect = useCallback(async () => {
    if (!user?.id) {
      console.warn("[websocket] Cannot connect: no current user");
      return;
    }

    try {
      await commands.connectWebsocket({
        user_id: user.id,
      });

      // Update status after connection
      await updateStatus();

      console.log("[websocket] Connected successfully");
    } catch (error) {
      console.error("[websocket] Failed to connect:", error);
      console.error("[websocket] Failed to connect to real-time notifications");
    }
  }, [user?.id, updateStatus]);

  // Disconnect from WebSocket
  const disconnect = useCallback(async () => {
    try {
      await commands.disconnectWebsocket({});
      await updateStatus();
      console.log("[websocket] Disconnected successfully");
    } catch (error) {
      console.error("[websocket] Failed to disconnect:", error);
    }
  }, [updateStatus]);

  // Handle specific notification types
  const handleNotification = useCallback(
    (notification: WebSocketNotification) => {
      setLastNotification(notification);

      console.log(`[websocket] Received ${notification.update_type} notification:`, notification);

      // Invalidate relevant queries based on notification type
      switch (notification.update_type) {
        case "SyncCipherUpdate":
        case "SyncCipherCreate":
          queryClient.invalidateQueries({ queryKey: ["ciphers"] });
          queryClient.invalidateQueries({ queryKey: ["vault"] });
          console.log("[websocket] Cipher updated");
          break;

        case "SyncCipherDelete":
          queryClient.invalidateQueries({ queryKey: ["ciphers"] });
          queryClient.invalidateQueries({ queryKey: ["vault"] });
          console.log("[websocket] Cipher deleted");
          break;

        case "SyncFolderCreate":
        case "SyncFolderUpdate":
          queryClient.invalidateQueries({ queryKey: ["folders"] });
          queryClient.invalidateQueries({ queryKey: ["vault"] });
          console.log("[websocket] Folder updated");
          break;

        case "SyncFolderDelete":
          queryClient.invalidateQueries({ queryKey: ["folders"] });
          queryClient.invalidateQueries({ queryKey: ["vault"] });
          console.log("[websocket] Folder deleted");
          break;

        case "SyncVault":
          queryClient.invalidateQueries({ queryKey: ["vault"] });
          queryClient.invalidateQueries({ queryKey: ["ciphers"] });
          queryClient.invalidateQueries({ queryKey: ["folders"] });
          console.log("[websocket] Vault synchronized");
          break;

        case "SyncCiphers":
          queryClient.invalidateQueries({ queryKey: ["ciphers"] });
          queryClient.invalidateQueries({ queryKey: ["vault"] });
          console.log("[websocket] Ciphers synchronized");
          break;

        case "SyncOrgKeys":
          queryClient.invalidateQueries({ queryKey: ["organizations"] });
          console.log("[websocket] Organization keys updated");
          break;

        case "LogOut":
          // Force logout
          console.error("[websocket] You have been logged out from another device");
          // The auth store should handle this via the event listener
          break;

        case "SyncSendCreate":
        case "SyncSendUpdate":
          queryClient.invalidateQueries({ queryKey: ["sends"] });
          console.log("[websocket] Send updated");
          break;

        case "SyncSendDelete":
          queryClient.invalidateQueries({ queryKey: ["sends"] });
          console.log("[websocket] Send deleted");
          break;

        case "AuthRequest":
          console.log("[websocket] Authentication request received");
          break;

        case "AuthRequestResponse":
          console.log("[websocket] Authentication request processed");
          break;

        case "SyncLoginDelete":
          queryClient.invalidateQueries({ queryKey: ["ciphers"] });
          queryClient.invalidateQueries({ queryKey: ["vault"] });
          console.log("[websocket] Login deleted");
          break;

        default:
          console.log(`[websocket] Unhandled notification type: ${notification.update_type}`);
      }
    },
    [queryClient]
  );

  // Set up event listeners
  useEffect(() => {
    const setupListeners = async () => {
      try {
        // Clean up existing listeners
        unlistenersRef.current.forEach((unlisten) => unlisten());
        unlistenersRef.current = [];

        // Listen for WebSocket notifications
        const notificationUnlisten = await listen<WebSocketNotification>(
          "websocket_notification",
          (event) => {
            handleNotification(event.payload);
          }
        );
        unlistenersRef.current.push(notificationUnlisten);

        // Listen for WebSocket status changes
        const statusUnlisten = await listen<WebSocketStatus>(
          "websocket_status_changed",
          (event) => {
            setStatus(event.payload);
            setIsConnected(event.payload.state === "connected");
          }
        );
        unlistenersRef.current.push(statusUnlisten);

        // Listen for vault changes (generic event)
        const vaultUnlisten = await listen<string>("vault_changed", () => {
          queryClient.invalidateQueries({ queryKey: ["vault"] });
        });
        unlistenersRef.current.push(vaultUnlisten);

        // Listen for force logout events
        const logoutUnlisten = await listen<string>("force_logout", () => {
          // This should trigger the auth store to handle logout
          queryClient.clear();
          console.error("[websocket] You have been logged out");
        });
        unlistenersRef.current.push(logoutUnlisten);
      } catch (error) {
        console.error("[websocket] Failed to setup event listeners:", error);
      }
    };

    setupListeners();

    // Initial status check
    updateStatus();

    // Cleanup on unmount
    return () => {
      unlistenersRef.current.forEach((unlisten) => unlisten());
      unlistenersRef.current = [];
    };
  }, [queryClient, handleNotification, updateStatus]);

  // Auto-connect when user is available
  useEffect(() => {
    if (user?.id && !isConnected) {
      connect();
    }
  }, [user?.id, isConnected, connect]);

  return {
    status,
    isConnected,
    connect,
    disconnect,
    lastNotification,
  };
}
