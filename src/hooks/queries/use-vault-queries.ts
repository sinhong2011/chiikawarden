import { useMutation, useQuery } from "@tanstack/react-query";
import { queryClient } from "@/lib/query-client";
import { queryKeys } from "@/lib/query-key";
import { type CipherType, vaultService } from "@/services/vault.service";
import { useAuthStore } from "@/stores/auth.store";
import { useVaultStore } from "@/stores/vault.store";
import type { CipherView, Folder } from "@/types/vault.types";

export const useVaultQueries = () => {
  const authStore = useAuthStore();
  const vaultStore = useVaultStore();

  // Get all ciphers query with enhanced error handling
  const ciphersQuery = useQuery({
    queryKey: queryKeys.ciphers(authStore.userId || ""),
    queryFn: async () => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      try {
        const result = await vaultService.getAllCiphers(authStore.userId);
        // Ensure result is always an array
        return Array.isArray(result) ? result : [];
      } catch (error) {
        console.error("Failed to fetch ciphers:", error);
        // Return empty array instead of throwing to prevent UI breakage
        return [];
      }
    },
    enabled: !!authStore.userId && authStore.isAuthenticated,
    staleTime: 1000 * 60 * 5, // 5 minutes
    // Add retry configuration for better resilience
    retry: (failureCount, error) => {
      // Don't retry on authentication errors
      if (error?.message?.includes("authentication") || error?.message?.includes("401")) {
        return false;
      }
      // Retry up to 3 times for other errors
      return failureCount < 3;
    },
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
  });

  // Get folders query
  const foldersQuery = useQuery({
    queryKey: queryKeys.folders(authStore.userId || ""),
    queryFn: async () => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      return await vaultService.getFolders(authStore.userId);
    },
    enabled: !!authStore.userId && authStore.isAuthenticated,
    staleTime: 1000 * 60 * 10, // 10 minutes (folders change less frequently)
  });

  // Search ciphers query options factory
  const createSearchCiphersQuery = (query: string) => ({
    queryKey: queryKeys.search(authStore.userId || "", query),
    queryFn: async () => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      return await vaultService.searchCiphers(query, authStore.userId);
    },
    enabled: !!authStore.userId && authStore.isAuthenticated && query.trim().length > 0,
    staleTime: 1000 * 60 * 2, // 2 minutes for search results
  });

  // Get ciphers by type query options factory
  const createCiphersByTypeQuery = (type: CipherType) => ({
    queryKey: [...queryKeys.ciphers(authStore.userId || ""), "type", type],
    queryFn: async () => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      return await vaultService.getCiphersByType(authStore.userId, type);
    },
    enabled: !!authStore.userId && authStore.isAuthenticated,
    staleTime: 1000 * 60 * 5, // 5 minutes
  });

  // Get favorite ciphers query
  const favoriteCiphersQuery = useQuery({
    queryKey: queryKeys.favorites(authStore.userId || ""),
    queryFn: async () => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      return await vaultService.getFavoriteCiphers(authStore.userId);
    },
    enabled: !!authStore.userId && authStore.isAuthenticated,
    staleTime: 1000 * 60 * 5, // 5 minutes
  });

  // Get ciphers in folder query options factory
  const createCiphersInFolderQuery = (folderId: string | null) => ({
    queryKey: queryKeys.folderCiphers(authStore.userId || "", folderId || "no-folder"),
    queryFn: async () => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      return await vaultService.getCiphersInFolder(authStore.userId, folderId);
    },
    enabled: !!authStore.userId && authStore.isAuthenticated,
    staleTime: 1000 * 60 * 5, // 5 minutes
  });

  // Save cipher mutation
  const saveCipherMutation = useMutation({
    mutationFn: async (cipher: CipherView) => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      await vaultStore.saveCipher(cipher, authStore.userId);
      return cipher;
    },
    onSuccess: (cipher) => {
      // Invalidate relevant queries
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.ciphers(authStore.userId) });
        queryClient.invalidateQueries({ queryKey: queryKeys.favorites(authStore.userId) });

        if (cipher.folder_id) {
          queryClient.invalidateQueries({
            queryKey: queryKeys.folderCiphers(authStore.userId, cipher.folder_id),
          });
        }
      }
    },
    onError: (error) => {
      console.error("Failed to save cipher:", error);
    },
  });

  // Delete cipher mutation
  const deleteCipherMutation = useMutation({
    mutationFn: async (cipherId: string) => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      await vaultStore.deleteCipher(cipherId, authStore.userId);
      return cipherId;
    },
    onSuccess: () => {
      // Invalidate all cipher-related queries
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.vault(authStore.userId) });
      }
    },
    onError: (error) => {
      console.error("Failed to delete cipher:", error);
    },
  });

  // Save folder mutation
  const saveFolderMutation = useMutation({
    mutationFn: async (folder: Folder) => {
      await vaultStore.saveFolder(folder);
      return folder;
    },
    onSuccess: () => {
      // Invalidate folder queries
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.folders(authStore.userId) });
      }
    },
    onError: (error) => {
      console.error("Failed to save folder:", error);
    },
  });

  // Delete folder mutation
  const deleteFolderMutation = useMutation({
    mutationFn: async (folderId: string) => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      await vaultStore.deleteFolder(folderId, authStore.userId);
      return folderId;
    },
    onSuccess: () => {
      // Invalidate all vault queries since folder deletion affects ciphers too
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.vault(authStore.userId) });
      }
    },
    onError: (error) => {
      console.error("Failed to delete folder:", error);
    },
  });

  // Toggle cipher favorite mutation
  const toggleFavoriteMutation = useMutation({
    mutationFn: async (cipher: CipherView) => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      await vaultStore.toggleCipherFavorite(cipher, authStore.userId);
      return cipher;
    },
    onSuccess: () => {
      // Invalidate cipher and favorite queries
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.ciphers(authStore.userId) });
        queryClient.invalidateQueries({ queryKey: queryKeys.favorites(authStore.userId) });
      }
    },
    onError: (error) => {
      console.error("Failed to toggle favorite:", error);
    },
  });

  // Load vault data mutation (for initial load)
  const loadVaultDataMutation = useMutation({
    mutationFn: async () => {
      if (!authStore.userId) {
        throw new Error("No user ID available");
      }
      await vaultStore.loadVaultData(authStore.userId);
    },
    onSuccess: () => {
      // Invalidate all vault queries to refresh from store
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.vault(authStore.userId) });
      }
    },
    onError: (error) => {
      console.error("Failed to load vault data:", error);
    },
  });

  return {
    // Queries
    ciphers: ciphersQuery,
    folders: foldersQuery,
    createSearchCiphersQuery,
    createCiphersByTypeQuery,
    favoriteCiphers: favoriteCiphersQuery,
    createCiphersInFolderQuery,

    // Mutations
    saveCipher: saveCipherMutation,
    deleteCipher: deleteCipherMutation,
    saveFolder: saveFolderMutation,
    deleteFolder: deleteFolderMutation,
    toggleFavorite: toggleFavoriteMutation,
    loadVaultData: loadVaultDataMutation,

    // Helper functions
    invalidateVault: () => {
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.vault(authStore.userId) });
      }
    },
    invalidateCiphers: () => {
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.ciphers(authStore.userId) });
      }
    },
    invalidateFolders: () => {
      if (authStore.userId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.folders(authStore.userId) });
      }
    },
  };
};

/**
 * Custom hook for fetching vault items with TanStack Query
 * Provides loading, error, and success states for the vault items list
 * Enhanced with robust error handling to prevent UI breakage
 */
export const useVaultItems = () => {
  const authStore = useAuthStore();

  return useQuery({
    queryKey: queryKeys.ciphers(authStore.userId || ""),
    queryFn: async () => {
      if (!authStore.userId) {
        console.warn("useVaultItems: No user ID available");
        return [];
      }

      try {
        const result = await vaultService.getAllCiphers(authStore.userId);
        // Defensive programming: ensure result is always an array
        if (!result) {
          console.warn("useVaultItems: Received null/undefined result, returning empty array");
          return [];
        }

        if (!Array.isArray(result)) {
          console.warn("useVaultItems: Received non-array result, converting to array");
          return [];
        }

        return result;
      } catch (error) {
        console.error("useVaultItems: Failed to fetch vault items:", error);
        // Return empty array instead of throwing to prevent UI breakage
        return [];
      }
    },
    enabled: !!authStore.userId && authStore.isAuthenticated,
    staleTime: 1000 * 60 * 5, // 5 minutes
    retry: (failureCount, error) => {
      // Don't retry on authentication errors
      const errorMessage = error?.message?.toLowerCase() || "";
      if (
        errorMessage.includes("authentication") ||
        errorMessage.includes("401") ||
        errorMessage.includes("unauthorized")
      ) {
        console.warn("useVaultItems: Authentication error, not retrying");
        return false;
      }
      // Retry up to 3 times for other errors
      return failureCount < 3;
    },
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
    // Ensure we always have a fallback value
    placeholderData: [],
  });
};
