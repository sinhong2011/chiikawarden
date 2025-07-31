import { commands } from "@/lib/tauri-commands";
import { isTauriEnvironment, logEnvironmentWarning } from "@/lib/tauri-environment";
import type { AuthState, PersistOptions, SessionData } from "@/types/auth.types";

// Best practice: Layered storage with development optimizations
export class SessionManager {
  private readonly DEV_STORAGE_KEY = "chiikawarden_dev_session";
  private readonly PROD_STORAGE_KEY = "chiikawarden_session";
  private readonly MAX_DEV_SESSION_AGE = 24 * 60 * 60 * 1000; // 24 hours

  async persistSession(state: AuthState, options: PersistOptions = {}) {
    const sessionData: SessionData = {
      // Always safe to persist
      email: options.rememberMe ? state.email : null,
      biometricEnabled: state.biometricEnabled,
      twoFactorEnabled: state.twoFactorEnabled,
      lastActivity: new Date().toISOString(),
      rememberMe: options.rememberMe || false,
    };

    try {
      // Check if we're in a Tauri environment
      if (!isTauriEnvironment()) {
        logEnvironmentWarning("persistSession");
        // Use localStorage as fallback in browser environment
        const key = __DEV__ ? this.DEV_STORAGE_KEY : this.PROD_STORAGE_KEY;
        localStorage.setItem(key, JSON.stringify(sessionData));
        return;
      }

      // Use Tauri store for persistence
      await commands.storeValue({
        store_name: "auth-store",
        key: __DEV__ ? this.DEV_STORAGE_KEY : this.PROD_STORAGE_KEY,
        value: JSON.stringify(sessionData),
      });

      if (__DEV__) {
        console.log("[DEV] Session persisted with context:", {
          authStatus: state.authStatus,
          userId: state.userId,
          email: state.email,
        });
      }
    } catch (error) {
      console.error("Failed to persist session:", error);
    }
  }

  async loadSession(): Promise<SessionData | null> {
    try {
      // Check if we're in a Tauri environment
      if (!isTauriEnvironment()) {
        logEnvironmentWarning("loadSession");
        // Use localStorage as fallback in browser environment
        const key = __DEV__ ? this.DEV_STORAGE_KEY : this.PROD_STORAGE_KEY;
        const stored = localStorage.getItem(key);
        if (stored) {
          return JSON.parse(stored);
        }
        return null;
      }

      const result = await commands.getValue({
        store_name: "auth-store",
        key: __DEV__ ? this.DEV_STORAGE_KEY : this.PROD_STORAGE_KEY,
      });

      if (result.status === "ok" && result.data.value) {
        const session: SessionData = JSON.parse(result.data.value);

        return session;
      }
    } catch (error) {
      console.warn("Failed to load session:", error);
    }

    return null;
  }

  async clearSession(): Promise<void> {
    try {
      // Check if we're in a Tauri environment
      if (!isTauriEnvironment()) {
        logEnvironmentWarning("clearSession");
        // Use localStorage as fallback in browser environment
        const key = __DEV__ ? this.DEV_STORAGE_KEY : this.PROD_STORAGE_KEY;
        localStorage.removeItem(key);
        return;
      }

      await commands.deleteValue({
        store_name: "auth-store",
        key: __DEV__ ? this.DEV_STORAGE_KEY : this.PROD_STORAGE_KEY,
      });

      if (__DEV__) {
        console.log("[DEV] Session cleared");
      }
    } catch (error) {
      console.error("Failed to clear session:", error);
    }
  }
}

export const sessionManager = new SessionManager();
