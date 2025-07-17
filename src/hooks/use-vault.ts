import { useVaultStore } from "@/stores/vault.store";
import type { CipherView, Folder, VaultStats } from "@/types/vault.types";

export const useVault = () => {
  const vaultStore = useVaultStore();

  return {
    // State
    ciphers: vaultStore.ciphers,
    folders: vaultStore.folders,
    collections: vaultStore.collections,
    isLoading: vaultStore.isLoading,
    searchQuery: vaultStore.searchQuery,
    selectedFolder: vaultStore.selectedFolder,
    selectedCipher: vaultStore.selectedCipher,
    showFavorites: vaultStore.showFavorites,
    lastSync: vaultStore.lastSync,

    // Computed properties
    get filteredCiphers(): CipherView[] {
      let filtered = vaultStore.ciphers;

      // Filter by search query
      if (vaultStore.searchQuery.trim()) {
        const query = vaultStore.searchQuery.toLowerCase();
        filtered = filtered.filter(
          (cipher) =>
            cipher.name.toLowerCase().includes(query) ||
            cipher.notes?.toLowerCase().includes(query) ||
            cipher.login?.username?.toLowerCase().includes(query)
        );
      }

      // Filter by selected folder
      if (vaultStore.selectedFolder !== undefined) {
        filtered = filtered.filter((cipher) => cipher.folder_id === vaultStore.selectedFolder);
      }

      // Filter by favorites
      if (vaultStore.showFavorites) {
        filtered = filtered.filter((cipher) => cipher.favorite);
      }

      return filtered;
    },

    get vaultStats(): VaultStats {
      const ciphers = vaultStore.ciphers;

      return {
        totalCiphers: ciphers.length,
        loginCount: ciphers.filter((c) => c.cipher_type === "Login").length,
        noteCount: ciphers.filter((c) => c.cipher_type === "SecureNote").length,
        cardCount: ciphers.filter((c) => c.cipher_type === "Card").length,
        identityCount: ciphers.filter((c) => c.cipher_type === "Identity").length,
        favoriteCount: ciphers.filter((c) => c.favorite).length,
        folderCount: vaultStore.folders.length,
      };
    },

    get loginCiphers(): CipherView[] {
      return vaultStore.ciphers.filter((c) => c.cipher_type === "Login");
    },

    get noteCiphers(): CipherView[] {
      return vaultStore.ciphers.filter((c) => c.cipher_type === "SecureNote");
    },

    get cardCiphers(): CipherView[] {
      return vaultStore.ciphers.filter((c) => c.cipher_type === "Card");
    },

    get identityCiphers(): CipherView[] {
      return vaultStore.ciphers.filter((c) => c.cipher_type === "Identity");
    },

    get favoriteCiphers(): CipherView[] {
      return vaultStore.ciphers.filter((c) => c.favorite);
    },

    // Actions
    loadVaultData: (userId: string) => vaultStore.loadVaultData(userId),
    searchCiphers: (userId: string, query: string) => vaultStore.searchCiphers(userId, query),
    saveCipher: (cipher: CipherView, userId: string) => vaultStore.saveCipher(cipher, userId),
    deleteCipher: (cipherId: string, userId: string) => vaultStore.deleteCipher(cipherId, userId),
    saveFolder: (folder: Folder) => vaultStore.saveFolder(folder),
    deleteFolder: (folderId: string, userId: string) => vaultStore.deleteFolder(folderId, userId),
    selectCipher: (cipher: CipherView | undefined) => vaultStore.selectCipher(cipher),
    selectFolder: (folderId: string | null | undefined) => vaultStore.selectFolder(folderId),
    toggleFavorites: () => vaultStore.toggleFavorites(),
    toggleCipherFavorite: (cipher: CipherView, userId: string) =>
      vaultStore.toggleCipherFavorite(cipher, userId),
    clearSearch: () => vaultStore.clearSearch(),
    clearVaultData: () => vaultStore.clearVaultData(),
  };
};
