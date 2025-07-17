// src/types/auth.types.ts

// Re-export types from auth service for consistency
export type {
  BiometricUnlockRequest,
  BiometricUnlockResponse,
  KdfConfig,
  LoginRequest,
  LoginResponse,
  SetupAccountRequest,
  SetupAccountResponse,
  UnlockRequest,
  UnlockResponse,
} from "@/services/auth.service";

export type User = {
  id: string;
  name?: string;
  email: string;
  premium?: boolean;
  emailVerified?: boolean;
  twoFactorEnabled?: boolean;
  kdfConfig?: KdfConfig;
};

export type AuthStatus = "logged-out" | "locked" | "unlocked" | "pending-2fa";

export type AuthState = {
  isAuthenticated: boolean;
  authStatus: AuthStatus;
  user: User | null;
  userId: string | null;
  email: string | null;
  biometricEnabled: boolean;
  twoFactorEnabled: boolean;
  masterKey?: number[];
  userKey?: number[];
  accessToken?: string;
  refreshToken?: string;
  lastActivity?: Date;
};

export type LoginCredentials = {
  email: string;
  password: string;
  rememberMe?: boolean;
  twoFactorToken?: string;
  twoFactorMethod?: string;
};

export type UnlockCredentials = {
  password?: string;
  biometric?: boolean;
  pin?: string;
};

// Import KdfConfig for the User type
import type { KdfConfig } from "@/services/auth.service";
