import { useAuthStore } from "@/stores/auth.store";
import type { LoginCredentials, UnlockCredentials } from "@/types/auth.types";

export const useAuth = () => {
  const authStore = useAuthStore();

  return {
    // State
    isAuthenticated: authStore.isAuthenticated,
    authStatus: authStore.authStatus,
    user: authStore.user,
    userId: authStore.userId,
    email: authStore.email,
    biometricEnabled: authStore.biometricEnabled,
    twoFactorEnabled: authStore.twoFactorEnabled,
    lastActivity: authStore.lastActivity,

    // Computed properties
    get isLoggedIn() {
      return authStore.authStatus !== "logged-out";
    },

    get isUnlocked() {
      return authStore.authStatus === "unlocked" && authStore.isAuthenticated;
    },

    get isLocked() {
      return authStore.authStatus === "locked";
    },

    get needsSetup() {
      return authStore.authStatus === "logged-out" && !authStore.userId;
    },

    // Actions
    login: (credentials: LoginCredentials) => authStore.login(credentials),
    unlock: (credentials: UnlockCredentials) => authStore.unlock(credentials),
    setupAccount: (email: string, password: string) => authStore.setupAccount(email, password),
    lock: () => authStore.lock(),
    logout: () => authStore.logout(),
    setupBiometric: () => authStore.setupBiometric(),
    updateActivity: () => authStore.updateActivity(),
    clearSensitiveData: () => authStore.clearSensitiveData(),
  };
};
