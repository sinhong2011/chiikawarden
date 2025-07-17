// src/lib/storage.ts
// Client-side storage utilities for non-sensitive data only
// Sensitive data should always be handled by the Rust backend

import type { StateStorage } from "zustand/middleware";

export interface StorageAdapter {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
  clear(): void;
}

// Zustand-compatible storage adapter
export interface ZustandStorage extends StateStorage {
  name: string;
  isAvailable(): boolean;
}

class LocalStorageAdapter implements StorageAdapter {
  getItem(key: string): string | null {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  setItem(key: string, value: string): void {
    try {
      localStorage.setItem(key, value);
    } catch {
      // Silently fail if localStorage is not available
    }
  }

  removeItem(key: string): void {
    try {
      localStorage.removeItem(key);
    } catch {
      // Silently fail if localStorage is not available
    }
  }

  clear(): void {
    try {
      localStorage.clear();
    } catch {
      // Silently fail if localStorage is not available
    }
  }
}

class SessionStorageAdapter implements StorageAdapter {
  getItem(key: string): string | null {
    try {
      return sessionStorage.getItem(key);
    } catch {
      return null;
    }
  }

  setItem(key: string, value: string): void {
    try {
      sessionStorage.setItem(key, value);
    } catch {
      // Silently fail if sessionStorage is not available
    }
  }

  removeItem(key: string): void {
    try {
      sessionStorage.removeItem(key);
    } catch {
      // Silently fail if sessionStorage is not available
    }
  }

  clear(): void {
    try {
      sessionStorage.clear();
    } catch {
      // Silently fail if sessionStorage is not available
    }
  }
}

// Storage service for managing non-sensitive application data
export class StorageService {
  private adapter: StorageAdapter;
  private prefix: string;

  constructor(adapter: StorageAdapter, prefix = "chiikawarden_") {
    this.adapter = adapter;
    this.prefix = prefix;
  }

  private getKey(key: string): string {
    return `${this.prefix}${key}`;
  }

  // Generic methods
  getString(key: string): string | null {
    return this.adapter.getItem(this.getKey(key));
  }

  setString(key: string, value: string): void {
    this.adapter.setItem(this.getKey(key), value);
  }

  getObject<T>(key: string): T | null {
    const value = this.getString(key);
    if (!value) return null;

    try {
      return JSON.parse(value) as T;
    } catch {
      return null;
    }
  }

  setObject<T>(key: string, value: T): void {
    try {
      this.setString(key, JSON.stringify(value));
    } catch {
      // Silently fail if serialization fails
    }
  }

  getBoolean(key: string): boolean | null {
    const value = this.getString(key);
    if (value === null) return null;
    return value === "true";
  }

  setBoolean(key: string, value: boolean): void {
    this.setString(key, value.toString());
  }

  getNumber(key: string): number | null {
    const value = this.getString(key);
    if (!value) return null;

    const parsed = Number(value);
    return Number.isNaN(parsed) ? null : parsed;
  }

  setNumber(key: string, value: number): void {
    this.setString(key, value.toString());
  }

  remove(key: string): void {
    this.adapter.removeItem(this.getKey(key));
  }

  clear(): void {
    this.adapter.clear();
  }

  // Check if storage is available
  isAvailable(): boolean {
    try {
      const testKey = "__storage_test__";
      this.adapter.setItem(testKey, "test");
      this.adapter.removeItem(testKey);
      return true;
    } catch {
      return false;
    }
  }
}

// Pre-configured storage instances
export const appLocalStorageService = new StorageService(new LocalStorageAdapter());
export const appSessionStorageService = new StorageService(new SessionStorageAdapter());

// Zustand-compatible storage implementations
export class ZustandLocalStorage implements ZustandStorage {
  name = "localStorage";

  getItem(key: string): string | null {
    try {
      return window.localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  setItem(key: string, value: string): void {
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // Silently fail if localStorage is not available
    }
  }

  removeItem(key: string): void {
    try {
      window.localStorage.removeItem(key);
    } catch {
      // Silently fail if localStorage is not available
    }
  }

  isAvailable(): boolean {
    try {
      const testKey = "__storage_test__";
      window.localStorage.setItem(testKey, "test");
      window.localStorage.removeItem(testKey);
      return true;
    } catch {
      return false;
    }
  }
}

export class ZustandSessionStorage implements ZustandStorage {
  name = "sessionStorage";

  getItem(key: string): string | null {
    try {
      return window.sessionStorage.getItem(key);
    } catch {
      return null;
    }
  }

  setItem(key: string, value: string): void {
    try {
      window.sessionStorage.setItem(key, value);
    } catch {
      // Silently fail if sessionStorage is not available
    }
  }

  removeItem(key: string): void {
    try {
      window.sessionStorage.removeItem(key);
    } catch {
      // Silently fail if sessionStorage is not available
    }
  }

  isAvailable(): boolean {
    try {
      const testKey = "__storage_test__";
      window.sessionStorage.setItem(testKey, "test");
      window.sessionStorage.removeItem(testKey);
      return true;
    } catch {
      return false;
    }
  }
}

// Storage instances for Zustand
export const zustandLocalStorage = new ZustandLocalStorage();
export const zustandSessionStorage = new ZustandSessionStorage();

// Custom persistence options for different stores
export interface PersistenceConfig<T> {
  name: string;
  storage: ZustandStorage;
  partialize?: (state: T) => Partial<T>;
  onRehydrateStorage?: (state: T) => ((state?: T, error?: Error) => void) | undefined;
  skipHydration?: boolean;
}

// Helper to create storage with app prefix
export function createAppStorage(
  storage: ZustandStorage,
  prefix = "chiikawarden_"
): ZustandStorage {
  return {
    name: `${prefix}${storage.name}`,
    getItem: (key: string) => storage.getItem(`${prefix}${key}`),
    setItem: (key: string, value: string) => storage.setItem(`${prefix}${key}`, value),
    removeItem: (key: string) => storage.removeItem(`${prefix}${key}`),
    isAvailable: () => storage.isAvailable(),
  };
}

// Pre-configured app storages
export const appLocalStorage = createAppStorage(zustandLocalStorage);
export const appSessionStorage = createAppStorage(zustandSessionStorage);

// Dynamic storage selection based on remember me preference
export function createDynamicStorage(rememberMe: boolean): ZustandStorage {
  return rememberMe ? appLocalStorage : appSessionStorage;
}

// Session persistence types (non-sensitive data only)
export interface SessionData {
  userId: string | null;
  email: string | null;
  authStatus: "logged-out" | "locked" | "unlocked" | "pending-2fa";
  biometricEnabled: boolean;
  twoFactorEnabled: boolean;
  lastActivity: string; // ISO string
  rememberMe: boolean;
}

// Session management utilities
export const sessionManager = {
  // Save non-sensitive session data
  saveSession(data: SessionData): void {
    const storage = data.rememberMe ? appLocalStorageService : appSessionStorageService;
    storage.setObject("session", data);
  },

  // Load session data
  loadSession(): SessionData | null {
    // Try localStorage first (for remembered sessions)
    let session = appLocalStorageService.getObject<SessionData>("session");
    if (session) return session;

    // Fall back to sessionStorage
    session = appSessionStorageService.getObject<SessionData>("session");
    return session;
  },

  // Clear session data
  clearSession(): void {
    appLocalStorageService.remove("session");
    appSessionStorageService.remove("session");
  },

  // Check if session exists
  hasSession(): boolean {
    return this.loadSession() !== null;
  },

  // Update last activity
  updateActivity(): void {
    const session = this.loadSession();
    if (session) {
      session.lastActivity = new Date().toISOString();
      this.saveSession(session);
    }
  },
};

// Helper functions for Zustand store persistence
export const createAuthPersistConfig = <T extends Record<string, unknown>>(
  rememberMe: boolean
): PersistenceConfig<T> => ({
  name: "auth-state",
  storage: createDynamicStorage(rememberMe),
  partialize: (state) =>
    ({
      // Only persist non-sensitive data
      userId: state.userId,
      email: state.email,
      authStatus: state.authStatus,
      biometricEnabled: state.biometricEnabled,
      twoFactorEnabled: state.twoFactorEnabled,
      lastActivity: state.lastActivity,
    }) as unknown as Partial<T>,
  onRehydrateStorage: () => (state, error) => {
    if (error) {
      console.error("Failed to rehydrate auth state:", error);
    } else if (state) {
      // Validate and sanitize rehydrated state
      const authState = state as Record<string, unknown>;
      if (authState.authStatus === "unlocked") {
        // Never restore unlocked state, always require re-unlock
        authState.authStatus = "locked";
        authState.isAuthenticated = false;
      }
    }
  },
});

export const createVaultPersistConfig = <
  T extends Record<string, unknown>,
>(): PersistenceConfig<T> => ({
  name: "vault-state",
  storage: appSessionStorage, // Use session storage for vault data
  partialize: (state) =>
    ({
      // Only persist UI state, not sensitive cipher data
      searchQuery: state.searchQuery,
      selectedFolder: state.selectedFolder,
      showFavorites: state.showFavorites,
    }) as unknown as Partial<T>,
});
