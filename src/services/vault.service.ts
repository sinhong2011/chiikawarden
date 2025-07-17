// src/services/vault.service.ts
import { commands } from "@/lib/tauri-commands";

// Re-export types from tauri-commands for convenience
export type {
  CardView,
  CipherType,
  CipherView,
  Collection,
  DeleteCipherRequest,
  DeleteFolderRequest,
  Folder,
  GetCiphersRequest,
  GetCollectionsRequest,
  GetFoldersRequest,
  IdentityView,
  LoginUriView,
  LoginView,
  SaveCipherRequest,
  SaveFolderRequest,
  SearchCiphersRequest,
  SecureNoteView,
} from "@/lib/tauri-commands";

import type { CipherType, CipherView, Folder } from "@/lib/tauri-commands";

export const vaultService = {
  /**
   * Get all ciphers for a user
   */
  async getAllCiphers(userId: string) {
    const request = { user_id: userId };
    const result = await commands.getAllCiphers(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Save a cipher
   */
  async saveCipher(cipher: CipherView, userId: string) {
    const request = { cipher, user_id: userId };
    const result = await commands.saveCipher(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Delete a cipher
   */
  async deleteCipher(cipherId: string, userId: string) {
    const request = { cipher_id: cipherId, user_id: userId };
    const result = await commands.deleteCipher(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Search ciphers
   */
  async searchCiphers(query: string, userId: string) {
    const request = { query, user_id: userId };
    const result = await commands.searchCiphers(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Get folders for a user
   */
  async getFolders(userId: string) {
    const request = { user_id: userId };
    const result = await commands.getFolders(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Save a folder
   */
  async saveFolder(folder: Folder) {
    const request = { folder };
    const result = await commands.saveFolder(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Delete a folder
   */
  async deleteFolder(folderId: string, userId: string) {
    const request = { folder_id: folderId, user_id: userId };
    const result = await commands.deleteFolder(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  /**
   * Get collections for an organization
   */
  async getCollections(organizationId: string) {
    const request = { organization_id: organizationId };
    const result = await commands.getCollections(request);

    if (result.status === "error") {
      throw result.error;
    }

    return result.data;
  },

  // Convenience methods for common operations

  /**
   * Get ciphers by type
   */
  async getCiphersByType(userId: string, type: CipherType) {
    const allCiphers = await this.getAllCiphers(userId);
    return allCiphers.filter((cipher) => cipher.cipher_type === type);
  },

  /**
   * Get favorite ciphers
   */
  async getFavoriteCiphers(userId: string) {
    const allCiphers = await this.getAllCiphers(userId);
    return allCiphers.filter((cipher) => cipher.favorite);
  },

  /**
   * Get ciphers in a folder
   */
  async getCiphersInFolder(userId: string, folderId: string | null) {
    const allCiphers = await this.getAllCiphers(userId);
    return allCiphers.filter((cipher) => cipher.folder_id === folderId);
  },

  /**
   * Create a new login cipher
   */
  createLoginCipher(name: string, username?: string, password?: string, uri?: string): CipherView {
    return {
      id: crypto.randomUUID(),
      organization_id: null,
      folder_id: null,
      name,
      notes: null,
      cipher_type: "Login",
      login: {
        username: username || null,
        password: password || null,
        totp: null,
        uris: uri ? [{ uri: uri, match_type: null }] : [],
      },
      secure_note: null,
      card: null,
      identity: null,
      favorite: false,
      reprompt: false,
      revision_date: new Date().toISOString(),
      created_date: new Date().toISOString(),
    };
  },

  /**
   * Create a new secure note cipher
   */
  createSecureNoteCipher(name: string, notes?: string): CipherView {
    return {
      id: crypto.randomUUID(),
      organization_id: null,
      folder_id: null,
      name,
      notes: notes || null,
      cipher_type: "SecureNote",
      login: null,
      secure_note: {
        note_type: 0, // Generic note
      },
      card: null,
      identity: null,
      favorite: false,
      reprompt: false,
      revision_date: new Date().toISOString(),
      created_date: new Date().toISOString(),
    };
  },
};
