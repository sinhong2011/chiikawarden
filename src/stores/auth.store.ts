import { create } from "zustand";
import { logDebug, logError, logInfo } from "@/lib/logging";
import { sessionManager } from "@/lib/storage/session-manager";
import { commands } from "@/lib/tauri-commands";
import { isTauriEnvironment, logEnvironmentWarning } from "@/lib/tauri-environment";
import { authService } from "@/services/auth.service";
import { networkAwareSyncService } from "@/services/network-aware-sync.service";
import type {
  AuthState,
  LoginCredentials,
  PersistOptions,
  SessionData,
  UnlockCredentials,
  User,
} from "@/types/auth.types";

// Initial auth state
const initialAuthState: AuthState = {
  isAuthenticated: false,
  authStatus: "logged-out",
  user: null,
  userId: null,
  email: null,
  biometricEnabled: false,
  twoFactorEnabled: false,
  lastActivity: new Date(),
  allUsers: [],
};

// Load persisted session data on initialization with migration
// SECURITY: In production, always start with logged-out state
// DEVELOPMENT: Allow restoring to identified/locked state for better DX
const loadPersistedState = async (): Promise<AuthState> => {
  const baseState = { ...initialAuthState };

  try {
    const session = await sessionManager.loadSession();
    if (!session) {
      return baseState;
    }

    // Fallback when preservation is disabled
    return {
      ...baseState,
      email: session.rememberMe ? session.email : null,
      biometricEnabled: session.biometricEnabled,
      twoFactorEnabled: session.twoFactorEnabled || false,
    };
  } catch (error) {
    console.warn("Failed to load persisted auth state:", error);
    return baseState;
  }
};

export interface AuthStore extends AuthState {
  // Actions
  login: (credentials: LoginCredentials) => Promise<boolean>;
  unlock: (credentials: UnlockCredentials) => Promise<boolean>;
  setupAccount: (email: string, password: string) => Promise<boolean>;
  lock: () => Promise<void>;
  logout: () => Promise<void>;
  setupBiometric: () => Promise<boolean>;
  updateActivity: () => void;
  clearSensitiveData: () => void;

  // Automatic user detection
  detectAndSetupUser: () => Promise<boolean>;

  // Manual user context setup for unlock scenarios
  setupUserContextForUnlock: (userId: string, email: string) => void;

  // Setup user from last logged-in ID
  setupUserFromLastLoggedIn: (userId: string) => Promise<boolean>;

  // Email persistence (integrated with session management)
  storeEmail: (email: string, rememberMe: boolean) => Promise<void>;
  getStoredEmail: () => Promise<string | null>;
  clearStoredEmail: () => Promise<void>;

  // Saved account selection
  selectedAccountEmail: string | null;
  setSelectedAccountEmail: (email: string | null) => void;

  // Last logged-in user management
  getLastLoggedInUserId: () => Promise<string | null>;
  setLastLoggedInUserId: (userId: string) => Promise<void>;
  clearLastLoggedInUserId: () => Promise<void>;

  // All users management
  loadAllUsers: () => Promise<void>;
  addCurrentUserToAllUsers: () => Promise<void>;
}

// Enhanced session persistence with development context
const persistSessionToTauri = async (state: AuthState, options: PersistOptions = {}) => {
  try {
    await sessionManager.persistSession(state, {
      rememberMe: options.rememberMe,
      lastLoggedInUserId: state.userId || options.lastLoggedInUserId,
    });
  } catch (error) {
    console.error("Failed to persist session:", error);
  }
};

export const useAuthStore = create<AuthStore>((set, get) => {
  // Initialize with persisted state safely
  const initialState = { ...initialAuthState };

  // Load persisted state asynchronously
  loadPersistedState().then((persistedState) => {
    set(persistedState);
    // Load all users after state is restored
    get().loadAllUsers();
  });

  return {
    ...initialState,
    // Saved account selection state
    selectedAccountEmail: null,
    /**
     * Login with email and password
     */
    async login(credentials: LoginCredentials): Promise<boolean> {
      await logInfo(
        "Starting login attempt",
        {
          email: credentials.email,
          rememberMe: credentials.rememberMe,
          hasPassword: !!credentials.password,
        },
        "AuthStore"
      );

      const startTime = Date.now();

      try {
        await logDebug("Calling auth service for login", { email: credentials.email }, "AuthStore");

        const response = await authService.loginWithPassword(
          credentials.email,
          credentials.password
        );

        if (response.success) {
          const elapsed = Date.now() - startTime;

          await logInfo(
            "Login authentication successful, updating auth state",
            {
              email: credentials.email,
              userId: response.user_id,
              elapsed_ms: elapsed,
            },
            "AuthStore"
          );

          const user: User = {
            id: response.user_id,
            email: credentials.email,
          };

          const newState: Partial<AuthState> = {
            isAuthenticated: true,
            authStatus: "unlocked" as const,
            user,
            userId: response.user_id,
            email: credentials.rememberMe ? credentials.email : null, // Only save email if remember me
            masterKey: response.master_key,
            lastActivity: new Date(),
          };

          set((state) => {
            // Create a new state object to avoid readonly property issues
            return Object.assign({}, state, newState);
          });

          // Persist session data to Tauri store
          await persistSessionToTauri(get(), {
            rememberMe: credentials.rememberMe,
            lastLoggedInUserId: response.user_id,
          });

          // Add current user to allUsers list for user selection
          await get().addCurrentUserToAllUsers();

          // Trigger immediate sync after successful login
          try {
            await logInfo(
              "Starting post-login vault sync",
              { userId: response.user_id },
              "AuthStore"
            );
            const syncResult = await networkAwareSyncService.syncVault(response.user_id);

            if (syncResult.success) {
              await logInfo(
                "Post-login sync completed successfully",
                {
                  userId: response.user_id,
                  itemsSynced: syncResult.items_synced,
                  syncMode: syncResult.sync_mode,
                },
                "AuthStore"
              );
            } else {
              await logError(
                "Post-login sync failed, but allowing login to proceed",
                new Error("Sync failed after login"),
                { userId: response.user_id },
                "AuthStore"
              );
            }
          } catch (syncError) {
            // Don't fail login if sync fails - allow offline access
            await logError(
              "Post-login sync failed with exception, allowing login to proceed",
              syncError instanceof Error ? syncError : new Error(String(syncError)),
              { userId: response.user_id },
              "AuthStore"
            );
          }

          await logInfo(
            "Login completed successfully - user authenticated and session persisted",
            {
              email: credentials.email,
              userId: response.user_id,
              rememberMe: credentials.rememberMe,
              elapsed_ms: elapsed,
            },
            "AuthStore"
          );

          return true;
        } else {
          const elapsed = Date.now() - startTime;

          await logError(
            "Login authentication failed - invalid credentials",
            undefined,
            {
              email: credentials.email,
              elapsed_ms: elapsed,
              reason: "authentication_failed",
            },
            "AuthStore"
          );

          return false;
        }
      } catch (error) {
        const elapsed = Date.now() - startTime;

        // Determine error category for better logging
        let errorCategory = "unknown";
        let errorMessage = "Unknown error occurred";

        if (error && typeof error === "object" && "message" in error) {
          errorMessage = String(error.message);

          // Categorize common error types
          if (errorMessage.includes("storage") || errorMessage.includes("store")) {
            errorCategory = "storage_failure";
          } else if (errorMessage.includes("network") || errorMessage.includes("connection")) {
            errorCategory = "network_failure";
          } else if (
            errorMessage.includes("authentication") ||
            errorMessage.includes("credentials")
          ) {
            errorCategory = "authentication_failure";
          } else if (errorMessage.includes("cryptography") || errorMessage.includes("encryption")) {
            errorCategory = "cryptography_failure";
          }
        }

        await logError(
          "Login failed with exception",
          error instanceof Error ? error : new Error(String(error)),
          {
            email: credentials.email,
            elapsed_ms: elapsed,
            reason: "exception",
            error_category: errorCategory,
            error_message: errorMessage,
          },
          "AuthStore"
        );

        console.error("Login failed:", error);
        return false;
      }
    },

    /**
     * Unlock vault with credentials
     */
    async unlock(credentials: UnlockCredentials): Promise<boolean> {
      try {
        const state = get();
        if (!state.userId) {
          throw new Error("No user ID available for unlock");
        }

        let masterKey: number[] | null = null;
        let userKey: number[] | null = null;
        let success = false;

        if (credentials.password) {
          const response = await authService.unlockWithPassword(state.userId, credentials.password);
          success = response.success;
          masterKey = response.master_key;
          userKey = response.user_key;
        } else if (credentials.biometric) {
          const response = await authService.unlockWithBiometric(state.userId);
          success = response.success;
          userKey = response.user_key;
        } else {
          throw new Error("No valid unlock method provided");
        }

        if (success) {
          const newState: Partial<AuthState> = {
            isAuthenticated: true,
            authStatus: "unlocked" as const,
            masterKey: masterKey || undefined,
            userKey: userKey || undefined,
            lastActivity: new Date(),
          };

          set((state) => {
            // Create a new state object to avoid readonly property issues
            return Object.assign({}, state, newState);
          });

          // SECURITY: Don't persist unlocked state - user must re-authenticate on app restart
          // persistSession(get()); // Removed for security

          return true;
        }
        return false;
      } catch (error) {
        console.error("Unlock failed:", error);
        return false;
      }
    },

    /**
     * Setup new account
     */
    async setupAccount(email: string, password: string): Promise<boolean> {
      try {
        const response = await authService.setupAccount(email, password);

        const user: User = {
          id: response.user_id,
          email,
        };

        const newState: Partial<AuthState> = {
          isAuthenticated: true,
          authStatus: "unlocked" as const,
          user,
          userId: response.user_id,
          email,
          masterKey: response.master_key,
          userKey: response.user_key,
          lastActivity: new Date(),
        };

        set((state) => {
          // Create a new state object to avoid readonly property issues
          return Object.assign({}, state, newState);
        });

        return true;
      } catch (error) {
        console.error("Account setup failed:", error);
        return false;
      }
    },

    /**
     * Lock the vault
     */
    async lock(): Promise<void> {
      try {
        const state = get();
        if (state.userId) {
          await authService.lockVault(state.userId);
        }

        const newState: Partial<AuthState> = {
          authStatus: "locked" as const,
          isAuthenticated: false,
          masterKey: undefined,
          userKey: undefined,
          lastActivity: new Date(),
        };

        set((state) => {
          // Create a new state object to avoid readonly property issues
          return Object.assign({}, state, newState);
        });

        // SECURITY: Don't persist locked state - user must re-authenticate on app restart
        // persistSession(get()); // Removed for security
      } catch (error) {
        console.error("Lock failed:", error);
        // Still update state even if backend call fails
        const newState: Partial<AuthState> = {
          authStatus: "locked" as const,
          isAuthenticated: false,
          masterKey: undefined,
          userKey: undefined,
          lastActivity: new Date(),
        };

        set((state) => {
          // Create a new state object to avoid readonly property issues
          return Object.assign({}, state, newState);
        });

        // SECURITY: Don't persist locked state - user must re-authenticate on app restart
        // persistSession(get()); // Removed for security
      }
    },

    /**
     * Logout user
     */
    async logout(): Promise<void> {
      try {
        const state = get();
        if (state.userId) {
          await authService.logout(state.userId);
        }
      } catch (error) {
        console.error("Logout failed:", error);
      } finally {
        // Always reset state regardless of backend call result
        set(() => ({ ...initialAuthState }));

        // Clear all session data from both browser storage and Tauri store
        sessionManager.clearSession();
        try {
          await commands.deleteValue({
            store_name: "auth-store",
            key: "session",
          });
        } catch (error) {
          console.error("Failed to clear Tauri store session:", error);
        }
      }
    },

    /**
     * Setup biometric unlock
     */
    async setupBiometric(): Promise<boolean> {
      try {
        const state = get();
        if (!state.userId || !state.userKey) {
          throw new Error("User not authenticated or user key not available");
        }

        const success = await authService.setupBiometricUnlock(state.userId, state.userKey);

        if (success) {
          set((state) => {
            // Create a new state object to avoid readonly property issues
            return Object.assign({}, state, { biometricEnabled: true });
          });
        }

        return success;
      } catch (error) {
        console.error("Biometric setup failed:", error);
        return false;
      }
    },

    /**
     * Update last activity timestamp
     */
    updateActivity(): void {
      set((state) => {
        // Create a new state object to avoid readonly property issues
        return Object.assign({}, state, { lastActivity: new Date() });
      });

      // Note: Session activity is updated when session is persisted
    },

    /**
     * Clear sensitive data from memory
     */
    clearSensitiveData(): void {
      set((state) => {
        // Create a new state object to avoid readonly property issues
        return Object.assign({}, state, {
          masterKey: undefined,
          userKey: undefined,
          accessToken: undefined,
          refreshToken: undefined,
        });
      });
    },

    /**
     * Setup user context for unlock when we have account information
     * This is used when accessing unlock page directly with account context
     */
    setupUserContextForUnlock(userId: string, email: string): void {
      const user: User = {
        id: userId,
        email,
      };

      const newState: Partial<AuthState> = {
        authStatus: "locked" as const,
        isAuthenticated: false, // Still need to unlock
        user,
        userId,
        email,
        lastActivity: new Date(),
        // Don't set keys - user must unlock to get them
        masterKey: undefined,
        userKey: undefined,
      };

      set((state) => {
        return Object.assign({}, state, newState);
      });
    },

    /**
     * Setup user context from last logged-in user ID
     * This fetches user data from the database and sets up the auth state
     */
    async setupUserFromLastLoggedIn(userId: string): Promise<boolean> {
      try {
        await logInfo("Setting up user context from last logged-in ID", { userId }, "AuthStore");

        // Check if we're in a Tauri environment
        if (!isTauriEnvironment()) {
          logEnvironmentWarning("setupUserFromLastLoggedIn");
          await logInfo(
            "User setup skipped - running in browser environment",
            { userId },
            "AuthStore"
          );
          return false;
        }

        // Get user data from database by getting all users and filtering
        const usersResult = await commands.getAllUsers();
        if (usersResult.status === "error") {
          await logError(
            "Failed to get users from database",
            new Error(JSON.stringify(usersResult.error)),
            { userId },
            "AuthStore"
          );
          return false;
        }

        const userData = usersResult.data.find((user) => user.id === userId);
        if (!userData || !userData.id || !userData.email) {
          await logError(
            "User not found in database or invalid user data",
            new Error("User not found or missing required user fields"),
            {
              userId,
              availableUsers: usersResult.data.length,
              availableUserIds: usersResult.data.map((u) => u.id),
            },
            "AuthStore"
          );
          return false;
        }

        await logInfo(
          "Found user data in database",
          { userId: userData.id, email: userData.email },
          "AuthStore"
        );

        // Set up user context in locked state
        const user: User = {
          id: userData.id,
          email: userData.email,
        };

        const newState: Partial<AuthState> = {
          authStatus: "locked" as const,
          isAuthenticated: false, // Still need to unlock
          user,
          userId: userData.id,
          email: userData.email,
          lastActivity: new Date(),
          // Don't set keys - user must unlock to get them
          masterKey: undefined,
          userKey: undefined,
        };

        set((state) => {
          return Object.assign({}, state, newState);
        });

        await logInfo(
          "User context setup completed from last logged-in ID",
          {
            userId: userData.id,
            email: userData.email,
            authStatus: "locked",
          },
          "AuthStore"
        );

        return true;
      } catch (error) {
        await logError(
          "Failed to setup user from last logged-in ID",
          error instanceof Error ? error : new Error(String(error)),
          { userId },
          "AuthStore"
        );
        return false;
      }
    },

    /**
     * Detect existing user and setup for streamlined authentication
     */
    async detectAndSetupUser(): Promise<boolean> {
      try {
        await logInfo("Starting automatic user detection", {}, "AuthStore");

        // Check if we're in a Tauri environment
        if (!isTauriEnvironment()) {
          logEnvironmentWarning("detectAndSetupUser");
          await logInfo("User detection skipped - running in browser environment", {}, "AuthStore");
          return false;
        }

        // First, try to get the last logged-in user ID from our own session data
        let lastLoggedInUserId: string | null = null;
        try {
          lastLoggedInUserId = await this.getLastLoggedInUserId();
          if (lastLoggedInUserId) {
            await logInfo(
              "Found last logged-in user ID from session data",
              { userId: lastLoggedInUserId },
              "AuthStore"
            );
          } else {
            await logInfo("No last logged-in user ID found in session data", {}, "AuthStore");
          }
        } catch (error) {
          await logError(
            "Failed to get last logged-in user ID from session",
            error instanceof Error ? error : new Error(String(error)),
            {},
            "AuthStore"
          );
        }

        // If we have a last logged-in user ID, try to set up user context directly
        if (lastLoggedInUserId) {
          const userSetupSuccess = await this.setupUserFromLastLoggedIn(lastLoggedInUserId);
          if (userSetupSuccess) {
            return true;
          }
          // If direct setup failed, continue with full detection flow as fallback
          await logInfo(
            "Direct user setup from last logged-in ID failed, falling back to full detection",
            { userId: lastLoggedInUserId },
            "AuthStore"
          );
        }

        // Fallback to full user detection flow
        await logInfo("Performing full user detection", {}, "AuthStore");

        // Import here to avoid circular dependency with timeout
        const { appInitializationService } = await Promise.race([
          import("@/services/app-initialization.service"),
          new Promise<never>((_, reject) =>
            setTimeout(() => reject(new Error("Service import timeout")), 2000)
          ),
        ]);

        const detection = await Promise.race([
          appInitializationService.detectUsers(),
          new Promise<never>((_, reject) =>
            setTimeout(() => reject(new Error("User detection timeout")), 10000)
          ),
        ]);

        if (!detection.shouldUseStreamlinedFlow || !detection.detectedUser) {
          await logInfo(
            "No streamlined flow needed",
            {
              hasUsers: detection.hasUsers,
              shouldUseStreamlinedFlow: detection.shouldUseStreamlinedFlow,
            },
            "AuthStore"
          );
          return false;
        }

        // Validate detected user data
        if (!detection.detectedUser.id || !detection.detectedUser.email) {
          await logError(
            "Invalid detected user data",
            new Error("Missing user ID or email"),
            { detectedUser: detection.detectedUser },
            "AuthStore"
          );
          return false;
        }

        await logInfo(
          "Setting up streamlined authentication flow",
          {
            userId: detection.detectedUser.id,
            email: detection.detectedUser.email,
          },
          "AuthStore"
        );

        // Set up the auth state for the detected user in locked state
        try {
          const user: User = {
            id: detection.detectedUser.id,
            email: detection.detectedUser.email,
          };

          const newState: Partial<AuthState> = {
            authStatus: "locked" as const,
            isAuthenticated: false, // Still need to unlock
            user,
            userId: detection.detectedUser.id,
            email: detection.detectedUser.email,
            lastActivity: new Date(),
            // Don't set keys - user must unlock to get them
            masterKey: undefined,
            userKey: undefined,
          };

          set((state) => {
            return Object.assign({}, state, newState);
          });

          // Update session with detected user as last logged-in
          if (detection.lastLoggedInUserId) {
            try {
              await this.setLastLoggedInUserId(detection.lastLoggedInUserId);
            } catch (sessionError) {
              // Log but don't fail the whole operation
              await logError(
                "Failed to update last logged-in user in session",
                sessionError instanceof Error ? sessionError : new Error(String(sessionError)),
                { userId: detection.lastLoggedInUserId },
                "AuthStore"
              );
            }
          }
        } catch (stateError) {
          await logError(
            "Failed to update auth state for detected user",
            stateError instanceof Error ? stateError : new Error(String(stateError)),
            { userId: detection.detectedUser.id },
            "AuthStore"
          );
          return false;
        }

        await logInfo(
          "Streamlined authentication setup completed",
          {
            userId: detection.detectedUser.id,
            authStatus: "locked",
          },
          "AuthStore"
        );

        return true;
      } catch (error) {
        await logError(
          "Automatic user detection failed",
          error instanceof Error ? error : new Error(String(error)),
          {},
          "AuthStore"
        );
        return false;
      }
    },

    /**
     * Store email with remember me preference (integrated with session management)
     */
    async storeEmail(email: string, rememberMe: boolean): Promise<void> {
      try {
        // Get current session data
        const currentSession = await commands.getValue({
          store_name: "auth-store",
          key: "session",
        });

        let sessionData: Partial<SessionData> = {};
        if (currentSession.status === "ok" && currentSession.data.value) {
          sessionData = JSON.parse(currentSession.data.value);
        }

        // Update session with email and rememberMe preference
        const updatedSession: SessionData = {
          email: rememberMe ? email : null,
          rememberMe,
          lastActivity: new Date().toISOString(),
          biometricEnabled: sessionData.biometricEnabled || false,
          twoFactorEnabled: sessionData.twoFactorEnabled || false,
          lastLoggedInUserId: sessionData.lastLoggedInUserId || undefined,
        };

        await commands.storeValue({
          store_name: "auth-store",
          key: "session",
          value: JSON.stringify(updatedSession),
        });
      } catch (error) {
        console.error("Failed to store email:", error);
      }
    },

    /**
     * Get stored email from session data
     */
    async getStoredEmail(): Promise<string | null> {
      try {
        const result = await commands.getValue({
          store_name: "auth-store",
          key: "session",
        });

        if (result.status === "ok" && result.data.value) {
          const session = JSON.parse(result.data.value);
          return session.rememberMe ? session.email : null;
        }
      } catch (error) {
        console.error("Failed to get stored email:", error);
      }
      return null;
    },

    /**
     * Clear stored email from session data
     */
    async clearStoredEmail(): Promise<void> {
      try {
        const currentSession = await commands.getValue({
          store_name: "auth-store",
          key: "session",
        });

        if (currentSession.status === "ok" && currentSession.data.value) {
          const sessionData = JSON.parse(currentSession.data.value);
          const updatedSession = {
            ...sessionData,
            email: null,
            rememberMe: false,
          };

          await commands.storeValue({
            store_name: "auth-store",
            key: "session",
            value: JSON.stringify(updatedSession),
          });
        }
      } catch (error) {
        console.error("Failed to clear stored email:", error);
      }
    },

    /**
     * Get last logged-in user ID from session data
     */
    async getLastLoggedInUserId(): Promise<string | null> {
      try {
        // Check if we're in a Tauri environment
        if (!isTauriEnvironment()) {
          logEnvironmentWarning("getLastLoggedInUserId");
          // Use localStorage as fallback in browser environment
          const stored = localStorage.getItem("session");
          if (stored) {
            const session = JSON.parse(stored);
            return session.lastLoggedInUserId || null;
          }
          return null;
        }

        const result = await commands.getValue({
          store_name: "auth-store",
          key: "session",
        });

        if (result.status === "ok" && result.data.value) {
          const session = JSON.parse(result.data.value);
          return session.lastLoggedInUserId || null;
        }
      } catch (error) {
        console.error("Failed to get last logged-in user ID:", error);
      }
      return null;
    },

    /**
     * Set last logged-in user ID in session data
     */
    async setLastLoggedInUserId(userId: string): Promise<void> {
      try {
        const currentSession = await commands.getValue({
          store_name: "auth-store",
          key: "session",
        });

        let sessionData: Partial<SessionData> = {};
        if (currentSession.status === "ok" && currentSession.data.value) {
          sessionData = JSON.parse(currentSession.data.value);
        }

        const updatedSession: SessionData = {
          email: sessionData.email || null,
          rememberMe: sessionData.rememberMe || false,
          lastActivity: new Date().toISOString(),
          biometricEnabled: sessionData.biometricEnabled || false,
          twoFactorEnabled: sessionData.twoFactorEnabled || false,
          lastLoggedInUserId: userId,
        };

        await commands.storeValue({
          store_name: "auth-store",
          key: "session",
          value: JSON.stringify(updatedSession),
        });
      } catch (error) {
        console.error("Failed to set last logged-in user ID:", error);
      }
    },

    /**
     * Clear last logged-in user ID from session data
     */
    async clearLastLoggedInUserId(): Promise<void> {
      try {
        const currentSession = await commands.getValue({
          store_name: "auth-store",
          key: "session",
        });

        if (currentSession.status === "ok" && currentSession.data.value) {
          const sessionData = JSON.parse(currentSession.data.value);
          const updatedSession = {
            ...sessionData,
            lastLoggedInUserId: null,
          };

          await commands.storeValue({
            store_name: "auth-store",
            key: "session",
            value: JSON.stringify(updatedSession),
          });
        }
      } catch (error) {
        console.error("Failed to clear last logged-in user ID:", error);
      }
    },

    /**
     * Set selected account email for prefilling forms
     */
    setSelectedAccountEmail: (email: string | null) => {
      set({ selectedAccountEmail: email });
    },

    /**
     * Load all users from database
     */
    async loadAllUsers(): Promise<void> {
      try {
        // Check if we're in a Tauri environment
        if (!isTauriEnvironment()) {
          logEnvironmentWarning("loadAllUsers");
          // Set empty array for browser environment
          set({ allUsers: [] });
          return;
        }

        const result = await commands.getAllUsers();
        if (result.status === "ok") {
          // Convert database User to auth User format
          const authUsers: User[] = result.data.map((dbUser) => ({
            id: dbUser.id,
            email: dbUser.email,
            server_provider_id: dbUser.server_provider_id || "us-cloud",
            // Map other fields as needed
          }));
          set({ allUsers: authUsers });
        }
      } catch (error) {
        console.error("Failed to load all users:", error);
      }
    },

    /**
     * Add current user to allUsers if not already present
     */
    async addCurrentUserToAllUsers(): Promise<void> {
      const currentState = get();
      if (!currentState.user) return;

      const currentUser = currentState.user;
      const existingUser = currentState.allUsers.find((u) => u.id === currentUser.id);
      if (!existingUser) {
        const updatedUsers = [...currentState.allUsers, currentUser];
        set({ allUsers: updatedUsers });
      }
    },
  };
});

export type UseAuthStore = typeof useAuthStore;
