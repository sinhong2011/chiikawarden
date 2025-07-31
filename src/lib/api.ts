// API integration layer for Chiikawarden
// This file provides a unified interface for all API operations

import type { User } from "@/types/auth.types";

// Re-export query hooks for component usage
export { useAuthQueries } from "@/hooks/queries/use-auth-queries";
export { useCryptoQueries } from "@/hooks/queries/use-crypto-queries";
export { useUserQueries } from "@/hooks/queries/use-user-queries";
export { useVaultQueries } from "@/hooks/queries/use-vault-queries";
// Re-export hooks for component usage
export { useAuth } from "@/hooks/use-auth";
export { useVault } from "@/hooks/use-vault";
export { queryClient } from "@/lib/query-client";
// Re-export query utilities
export { queryKeys } from "@/lib/query-key";
// Re-export services for direct access when needed
export { authService } from "@/services/auth.service";
export type {
  // Crypto types
  EncryptedData,
  EncryptionType,
  HashPurpose,
} from "@/services/crypto.service";
export { cryptoService } from "@/services/crypto.service";
export { vaultService } from "@/services/vault.service";
// Re-export stores for direct state access
export { useAuthStore } from "@/stores/auth.store";
export { useVaultStore } from "@/stores/vault.store";
// Re-export types
export type {
  // Auth types
  AuthState,
  KdfConfig,
  LoginCredentials,
  LoginResponse,
  UnlockCredentials,
  UnlockResponse,
  User,
} from "@/types/auth.types";
export type {
  CardView,
  CipherType,
  CipherView,
  Collection,
  Folder,
  IdentityView,
  LoginView,
  SecureNoteView,
  VaultFilter,
  // Vault types
  VaultState,
  VaultStats,
} from "../types/vault.types";

export async function fetchUsers(): Promise<User[]> {
  // Simulate API delay
  await new Promise((resolve) => setTimeout(resolve, 1000));

  return [
    { id: "1", name: "John Doe", email: "john@example.com" },
    { id: "2", name: "Jane Smith", email: "jane@example.com" },
    { id: "3", name: "Bob Johnson", email: "bob@example.com" },
    { id: "4", name: "Alice Brown", email: "alice@example.com" },
  ];
}

export async function fetchUser(id: string): Promise<User> {
  await new Promise((resolve) => setTimeout(resolve, 800));

  const users = await fetchUsers();
  const user = users.find((u) => u.id === id);

  if (!user) {
    throw new Error(`User with ID ${id} not found`);
  }

  return user;
}
