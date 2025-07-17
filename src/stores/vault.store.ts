// src/stores/vault.store.ts
import { create } from "zustand";
import { vaultService } from "@/services/vault.service";
import type { CipherView, Folder, VaultState } from "@/types/vault.types";

// Initial vault state
const initialVaultState: VaultState = {
  ciphers: [],
  folders: [],
  collections: [],
  isLoading: false,
  searchQuery: "",
  selectedFolder: undefined,
  selectedCipher: undefined,
  showFavorites: false,
};

interface VaultStore extends VaultState {
  // Actions
  loadVaultData: (userId: string) => Promise<void>;
  searchCiphers: (userId: string, query: string) => Promise<void>;
  saveCipher: (cipher: CipherView, userId: string) => Promise<void>;
  deleteCipher: (cipherId: string, userId: string) => Promise<void>;
  saveFolder: (folder: Folder) => Promise<void>;
  deleteFolder: (folderId: string, userId: string) => Promise<void>;
  selectCipher: (cipher: CipherView | undefined) => void;
  selectFolder: (folderId: string | null | undefined) => void;
  toggleFavorites: () => void;
  toggleCipherFavorite: (cipher: CipherView, userId: string) => Promise<void>;
  clearSearch: () => void;
  clearVaultData: () => void;
}

export const useVaultStore = create<VaultStore>((set, get) => ({
  ...initialVaultState,
  /**
   * Load all vault data for a user
   */
  async loadVaultData(userId: string): Promise<void> {
    set((state) => ({ ...state, isLoading: true }));

    try {
      const [ciphers, folders] = await Promise.all([
        vaultService.getAllCiphers(userId),
        vaultService.getFolders(userId),
      ]);

      set((state) => ({
        ...state,
        ciphers,
        folders,
        isLoading: false,
        lastSync: new Date(),
      }));
    } catch (error) {
      console.error("Failed to load vault data:", error);
      set((state) => ({ ...state, isLoading: false }));
      throw error;
    }
  },

  /**
   * Search ciphers
   */
  async searchCiphers(userId: string, query: string): Promise<void> {
    set((state) => ({ ...state, isLoading: true, searchQuery: query }));

    try {
      const ciphers = query.trim()
        ? await vaultService.searchCiphers(query, userId)
        : await vaultService.getAllCiphers(userId);

      set((state) => ({
        ...state,
        ciphers,
        isLoading: false,
      }));
    } catch (error) {
      console.error("Failed to search ciphers:", error);
      set((state) => ({ ...state, isLoading: false }));
      throw error;
    }
  },

  /**
   * Save a cipher
   */
  async saveCipher(cipher: CipherView, userId: string): Promise<void> {
    try {
      await vaultService.saveCipher(cipher, userId);

      // Update local state
      set((state) => {
        const existingIndex = state.ciphers.findIndex((c) => c.id === cipher.id);
        if (existingIndex >= 0) {
          const newCiphers = [...state.ciphers];
          newCiphers[existingIndex] = cipher;
          return { ...state, ciphers: newCiphers };
        } else {
          return { ...state, ciphers: [...state.ciphers, cipher] };
        }
      });
    } catch (error) {
      console.error("Failed to save cipher:", error);
      throw error;
    }
  },

  /**
   * Delete a cipher
   */
  async deleteCipher(cipherId: string, userId: string): Promise<void> {
    try {
      await vaultService.deleteCipher(cipherId, userId);

      // Update local state
      set((state) => {
        const newCiphers = state.ciphers.filter((c) => c.id !== cipherId);
        const selectedCipher =
          state.selectedCipher?.id === cipherId ? undefined : state.selectedCipher;
        return { ...state, ciphers: newCiphers, selectedCipher };
      });
    } catch (error) {
      console.error("Failed to delete cipher:", error);
      throw error;
    }
  },

  /**
   * Save a folder
   */
  async saveFolder(folder: Folder): Promise<void> {
    try {
      await vaultService.saveFolder(folder);

      // Update local state
      set((state) => {
        const existingIndex = state.folders.findIndex((f) => f.id === folder.id);
        if (existingIndex >= 0) {
          const newFolders = [...state.folders];
          newFolders[existingIndex] = folder;
          return { ...state, folders: newFolders };
        } else {
          return { ...state, folders: [...state.folders, folder] };
        }
      });
    } catch (error) {
      console.error("Failed to save folder:", error);
      throw error;
    }
  },

  /**
   * Delete a folder
   */
  async deleteFolder(folderId: string, userId: string): Promise<void> {
    try {
      await vaultService.deleteFolder(folderId, userId);

      // Update local state
      set((state) => {
        const newFolders = state.folders.filter((f) => f.id !== folderId);
        const selectedFolder = state.selectedFolder === folderId ? undefined : state.selectedFolder;

        // Update ciphers that were in this folder
        const newCiphers = state.ciphers.map((cipher) =>
          cipher.folder_id === folderId ? { ...cipher, folder_id: null } : cipher
        );

        return { ...state, folders: newFolders, selectedFolder, ciphers: newCiphers };
      });
    } catch (error) {
      console.error("Failed to delete folder:", error);
      throw error;
    }
  },

  /**
   * Set selected cipher
   */
  selectCipher(cipher: CipherView | undefined): void {
    set((state) => ({ ...state, selectedCipher: cipher }));
  },

  /**
   * Set selected folder
   */
  selectFolder(folderId: string | null | undefined): void {
    set((state) => ({ ...state, selectedFolder: folderId }));
  },

  /**
   * Toggle favorites view
   */
  toggleFavorites(): void {
    set((state) => ({ ...state, showFavorites: !state.showFavorites }));
  },

  /**
   * Toggle cipher favorite status
   */
  async toggleCipherFavorite(cipher: CipherView, userId: string): Promise<void> {
    const updatedCipher = { ...cipher, favorite: !cipher.favorite };
    await get().saveCipher(updatedCipher, userId);
  },

  /**
   * Clear search
   */
  clearSearch(): void {
    set((state) => ({ ...state, searchQuery: "" }));
  },

  /**
   * Clear all vault data
   */
  clearVaultData(): void {
    set(initialVaultState);
  },
}));
