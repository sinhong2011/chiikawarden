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
  server_provider_id?: string;
  premium?: boolean;
  emailVerified?: boolean;
  twoFactorEnabled?: boolean;
  kdfConfig?: KdfConfig;
};

// Enhanced user type with server provider information
export type UserWithProvider = User & {
  server_provider_id: string;
  provider_label: string;
  provider_domain?: string;
};

export type AuthStatus =
  | "logged-out" // No user context
  | "identified" // User known, needs authentication
  | "locked" // Authenticated, vault locked
  | "unlocked" // Authenticated, vault unlocked
  | "pending-2fa"; // Awaiting 2FA

export interface DevAuthConfig {
  allowStateRestoration: boolean;
  maxRestorationAge: number;
  preserveUserContext: boolean;
}

export interface SessionData {
  email: string | null;
  biometricEnabled: boolean;
  twoFactorEnabled?: boolean;
  lastActivity: string;
  rememberMe: boolean;
  lastLoggedInUserId?: string;
}

export interface PersistOptions {
  rememberMe?: boolean;
  lastLoggedInUserId?: string;
}

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
  allUsers: User[];
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
