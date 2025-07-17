// src/types/vault.types.ts

// Re-export types from vault service for consistency
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
} from "@/services/vault.service";

// Additional types for vault state management
export interface VaultState {
  ciphers: CipherView[];
  folders: Folder[];
  collections: Collection[];
  isLoading: boolean;
  lastSync?: Date;
  searchQuery: string;
  selectedFolder?: string | null;
  selectedCipher?: CipherView;
  showFavorites: boolean;
}

export interface VaultFilter {
  type?: CipherType;
  folderId?: string | null;
  favorites?: boolean;
  search?: string;
}

export interface VaultStats {
  totalCiphers: number;
  loginCount: number;
  noteCount: number;
  cardCount: number;
  identityCount: number;
  favoriteCount: number;
  folderCount: number;
}

// Import types for re-export
import type { CipherType, CipherView, Collection, Folder } from "@/services/vault.service";

// Legacy type for backward compatibility
export type Cipher = {
  id: string;
  name: string;
  data: unknown;
};
