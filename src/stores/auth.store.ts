import { create } from "zustand";
import { sessionManager } from "@/lib/storage";
import { authService } from "@/services/auth.service";
import type { AuthState, LoginCredentials, UnlockCredentials, User } from "@/types/auth.types";

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
};

// Load persisted session data on initialization
const loadPersistedState = (): AuthState => {
  try {
    const session = sessionManager.loadSession();
    if (!session) return { ...initialAuthState };

    // Create a new object to avoid readonly property issues
    const restoredState: AuthState = {
      isAuthenticated: session.authStatus === "unlocked" || session.authStatus === "locked",
      authStatus: session.authStatus,
      user: null,
      userId: session.userId,
      email: session.email,
      biometricEnabled: session.biometricEnabled,
      twoFactorEnabled: session.twoFactorEnabled,
      lastActivity: session.lastActivity ? new Date(session.lastActivity) : new Date(),
    };

    return restoredState;
  } catch (error) {
    console.warn("Failed to load persisted auth state:", error);
    return { ...initialAuthState };
  }
};

interface AuthStore extends AuthState {
  // Actions
  login: (credentials: LoginCredentials) => Promise<boolean>;
  unlock: (credentials: UnlockCredentials) => Promise<boolean>;
  setupAccount: (email: string, password: string) => Promise<boolean>;
  lock: () => Promise<void>;
  logout: () => Promise<void>;
  setupBiometric: () => Promise<boolean>;
  updateActivity: () => void;
  clearSensitiveData: () => void;
}

// Helper function to persist session data
const persistSession = (state: AuthState, rememberMe = false) => {
  const sessionData = {
    userId: state.userId,
    email: state.email,
    authStatus: state.authStatus,
    biometricEnabled: state.biometricEnabled,
    twoFactorEnabled: state.twoFactorEnabled,
    lastActivity: state.lastActivity?.toISOString() || new Date().toISOString(),
    rememberMe,
  };
  sessionManager.saveSession(sessionData);
};

export const useAuthStore = create<AuthStore>((set, get) => {
  // Initialize with persisted state safely
  const initialState = loadPersistedState();

  return {
    ...initialState,
    /**
     * Login with email and password
     */
    async login(credentials: LoginCredentials): Promise<boolean> {
      try {
        const response = await authService.loginWithPassword(
          credentials.email,
          credentials.password
        );

        if (response.success) {
          const user: User = {
            id: response.user_id,
            email: credentials.email,
          };

          const newState: Partial<AuthState> = {
            isAuthenticated: true,
            authStatus: "unlocked" as const,
            user,
            userId: response.user_id,
            email: credentials.email,
            masterKey: response.master_key,
            lastActivity: new Date(),
          };

          set((state) => {
            // Create a new state object to avoid readonly property issues
            return Object.assign({}, state, newState);
          });

          // Persist session data
          persistSession(get(), credentials.rememberMe);

          return true;
        }
        return false;
      } catch (error) {
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

          // Persist session data (unlock doesn't change rememberMe preference)
          persistSession(get());

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

        // Update session data to reflect locked state
        persistSession(get());
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

        // Update session data even if backend call fails
        persistSession(get());
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

        // Clear all session data
        sessionManager.clearSession();
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

      // Update session activity timestamp
      sessionManager.updateActivity();
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
  };
});
