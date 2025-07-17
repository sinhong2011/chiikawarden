// src/services/auth.service.ts

import type { KdfConfig } from "@/lib/tauri-commands";
import { commands } from "@/lib/tauri-commands";

// Re-export types from tauri-commands for convenience
export type {
  AppError,
  BiometricUnlockRequest,
  BiometricUnlockResponse,
  KdfConfig,
  LoginRequest,
  LoginResponse,
  PreloginRequest,
  PreloginResponse,
  SetupAccountRequest,
  SetupAccountResponse,
  UnlockRequest,
  UnlockResponse,
} from "@/lib/tauri-commands";

// Default KDF configuration for Bitwarden compatibility
export const DEFAULT_KDF_CONFIG: KdfConfig = {
  kdf_type: 0, // PBKDF2
  iterations: 600_000,
  memory: null,
  parallelism: null,
};

export const authService = {
  /**
   * Get KDF settings for user before login (prelogin)
   */
  async prelogin(email: string) {
    const request = { email };
    const result = await commands.prelogin(request);

    if (result.status === "error") {
      throw new Error(`Prelogin failed: ${result.error}`);
    }

    return result.data;
  },
  /**
   * Login with email and password
   */
  async loginWithPassword(
    email: string,
    password: string,
    kdfConfig: KdfConfig = DEFAULT_KDF_CONFIG
  ) {
    const request = {
      email,
      password,
      kdf_config: kdfConfig,
    };

    const result = await commands.loginWithPassword(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Unlock vault with password
   */
  async unlockWithPassword(userId: string, password: string) {
    const request = {
      user_id: userId,
      password,
    };

    const result = await commands.unlockWithPassword(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Setup new account
   */
  async setupAccount(email: string, password: string, kdfConfig: KdfConfig = DEFAULT_KDF_CONFIG) {
    const request = {
      email,
      password,
      kdf_config: kdfConfig,
    };

    const result = await commands.setupAccount(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Unlock with biometric authentication
   */
  async unlockWithBiometric(userId: string) {
    const request = {
      user_id: userId,
    };

    const result = await commands.unlockWithBiometric(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Setup biometric unlock
   */
  async setupBiometricUnlock(userId: string, userKey: number[]) {
    const result = await commands.setupBiometricUnlock(userId, userKey);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Lock the vault
   */
  async lockVault(userId: string) {
    const result = await commands.lockVault(userId);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Refresh access token
   */
  async refreshToken(refreshToken: string) {
    const result = await commands.refreshToken(refreshToken);

    if (result.status === "error") {
      throw new Error(`Token refresh failed: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Logout user
   */
  async logout(userId: string) {
    const result = await commands.logout(userId);

    if (result.status === "error") {
      throw new Error(`Logout failed: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Change master password
   */
  async changeMasterPassword(
    userId: string,
    currentPassword: string,
    newPassword: string,
    email: string,
    kdfConfig: KdfConfig = DEFAULT_KDF_CONFIG
  ) {
    const result = await commands.changeMasterPassword(
      userId,
      currentPassword,
      newPassword,
      email,
      kdfConfig
    );

    if (result.status === "error") {
      throw new Error(`Password change failed: ${result.error}`);
    }

    return result.data;
  },
};
