// src/hooks/useAuthQueries.ts

import { useLingui } from "@lingui/react/macro";
import { useMutation, useQuery } from "@tanstack/react-query";
import { usePostLoginSync } from "@/hooks/queries/use-sync-queries";
import { isValidEmail } from "@/lib/constants";
import { queryClient } from "@/lib/query-client";
import { queryKeys } from "@/lib/query-key";
import { authService } from "@/services/auth.service";
import { useAuthStore } from "@/stores/auth.store";
import type { LoginCredentials, UnlockCredentials } from "@/types/auth.types";

export const useAuthQueries = () => {
  const authStore = useAuthStore();
  const { t } = useLingui();
  const postLoginSync = usePostLoginSync();

  // Prelogin mutation - gets KDF settings for user
  const preloginMutation = useMutation({
    mutationFn: async (email: string) => {
      if (!email || !isValidEmail(email)) {
        throw new Error(t`validation.email_required` /* 邮箱不能为空 */);
      }
      return await authService.prelogin(email);
    },
    retry: (failureCount, error) => {
      // Don't retry on client-side validation errors
      if (error.message.includes(t`validation.email_required` /* 邮箱不能为空 */)) {
        return false;
      }
      // Retry network errors up to 2 times
      return failureCount < 2;
    },
    onError: (error) => {
      console.error("Prelogin failed:", error);
    },
  });

  // Login mutation
  const loginMutation = useMutation({
    mutationFn: async (credentials: LoginCredentials) => {
      const success = await authStore.login(credentials);
      if (!success) {
        throw new Error(
          t`Login failed. Please check your credentials and try again.` /* 登录失败。请检查您的凭据并重试。 */
        );
      }
      return success;
    },
    onSuccess: async () => {
      // Invalidate auth-related queries
      queryClient.invalidateQueries({ queryKey: queryKeys.auth() });

      // Trigger vault synchronization after successful login
      if (authStore.userId) {
        try {
          await postLoginSync.mutateAsync(authStore.userId);
          console.log("Post-login vault sync completed successfully");
        } catch (error) {
          // Log sync error but don't fail the login
          console.error("Post-login vault sync failed:", error);
          // The user is still logged in, sync can be retried later
        }
      }
    },
    onError: (error) => {
      console.error("Login failed:", error);
    },
  });

  // Unlock mutation
  const unlockMutation = useMutation({
    mutationFn: async (credentials: UnlockCredentials) => {
      const success = await authStore.unlock(credentials);
      if (!success) {
        throw new Error(
          t`Unlock failed. Please check your password and try again.` /* 解锁失败。请检查您的密码并重试。 */
        );
      }
      return success;
    },
    onSuccess: async () => {
      // Invalidate auth and vault queries
      queryClient.invalidateQueries({ queryKey: queryKeys.auth() });
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.vault(authStore.userId) });

        // Trigger vault synchronization after successful unlock
        try {
          await postLoginSync.mutateAsync(authStore.userId);
          console.log("Post-unlock vault sync completed successfully");
        } catch (error) {
          // Log sync error but don't fail the unlock
          console.error("Post-unlock vault sync failed:", error);
          // The user is still unlocked, sync can be retried later
        }
      }
    },
    onError: (error) => {
      console.error("Unlock failed:", error);
    },
  });

  // Setup account mutation
  const setupAccountMutation = useMutation({
    mutationFn: async ({ email, password }: { email: string; password: string }) => {
      const success = await authStore.setupAccount(email, password);
      if (!success) {
        throw new Error(t`Account setup failed. Please try again.` /* 账户设置失败。请重试。 */);
      }
      return success;
    },
    onSuccess: () => {
      // Invalidate auth-related queries
      queryClient.invalidateQueries({ queryKey: queryKeys.auth() });
    },
    onError: (error) => {
      console.error("Account setup failed:", error);
    },
  });

  // Lock mutation
  const lockMutation = useMutation({
    mutationFn: async () => {
      await authStore.lock();
    },
    onSuccess: () => {
      // Clear all cached data when locking
      queryClient.clear();
    },
    onError: (error) => {
      console.error("Lock failed:", error);
    },
  });

  // Logout mutation
  const logoutMutation = useMutation({
    mutationFn: async () => {
      await authStore.logout();
    },
    onSuccess: () => {
      // Clear all cached data when logging out
      queryClient.clear();
    },
    onError: (error) => {
      console.error("Logout failed:", error);
    },
  });

  // Setup biometric mutation
  const setupBiometricMutation = useMutation({
    mutationFn: async () => {
      const success = await authStore.setupBiometric();
      if (!success) {
        throw new Error("Biometric setup failed");
      }
      return success;
    },
    onSuccess: () => {
      // Invalidate auth queries to refresh biometric status
      queryClient.invalidateQueries({ queryKey: queryKeys.auth() });
    },
    onError: (error) => {
      console.error("Biometric setup failed:", error);
    },
  });

  // Change master password mutation
  const changeMasterPasswordMutation = useMutation({
    mutationFn: async ({
      currentPassword,
      newPassword,
      email,
    }: {
      currentPassword: string;
      newPassword: string;
      email: string;
    }) => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }

      const success = await authService.changeMasterPassword(
        authStore.userId,
        currentPassword,
        newPassword,
        email
      );

      if (!success) {
        throw new Error("Password change failed");
      }

      return success;
    },
    onSuccess: () => {
      // Invalidate auth queries
      queryClient.invalidateQueries({ queryKey: queryKeys.auth() });
    },
    onError: (error) => {
      console.error("Password change failed:", error);
    },
  });

  // Refresh token mutation
  const refreshTokenMutation = useMutation({
    mutationFn: async (refreshToken: string) => {
      const newToken = await authService.refreshToken(refreshToken);
      return newToken;
    },
    onError: (error) => {
      console.error("Token refresh failed:", error);
      // If token refresh fails, logout the user
      authStore.logout();
    },
  });

  // Auth status query
  const authStatusQuery = useQuery({
    queryKey: queryKeys.auth(),
    queryFn: () => {
      return {
        isAuthenticated: authStore.isAuthenticated,
        authStatus: authStore.authStatus,
        user: authStore.user,
        userId: authStore.userId,
        email: authStore.email,
        biometricEnabled: authStore.biometricEnabled,
        twoFactorEnabled: authStore.twoFactorEnabled,
        lastActivity: authStore.lastActivity,
      };
    },
    staleTime: 0, // Always fresh since it's local state
    gcTime: 0, // Don't cache since it's local state
  });

  return {
    // Queries
    authStatus: authStatusQuery,

    // Mutations
    preloginMutation,
    login: loginMutation,
    unlock: unlockMutation,
    setupAccount: setupAccountMutation,
    lock: lockMutation,
    logout: logoutMutation,
    setupBiometric: setupBiometricMutation,
    changeMasterPassword: changeMasterPasswordMutation,
    refreshToken: refreshTokenMutation,

    // Helper functions
    invalidateAuth: () => queryClient.invalidateQueries({ queryKey: queryKeys.auth() }),
    clearAllQueries: () => queryClient.clear(),
  };
};
