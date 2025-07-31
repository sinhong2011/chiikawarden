export const queryKeys = {
  // Authentication
  auth: () => ["auth"] as const,
  prelogin: (email: string) => [...queryKeys.auth(), "prelogin", email] as const,
  user: (userId: string) => [...queryKeys.auth(), "user", userId] as const,

  // Vault data
  vault: (userId: string) => ["vault", userId] as const,
  ciphers: (userId: string) => [...queryKeys.vault(userId), "ciphers"] as const,
  cipher: (userId: string, cipherId: string) => [...queryKeys.ciphers(userId), cipherId] as const,
  folders: (userId: string) => [...queryKeys.vault(userId), "folders"] as const,
  collections: (userId: string) => [...queryKeys.vault(userId), "collections"] as const,

  // Search and filtering
  search: (userId: string, query: string) => [...queryKeys.vault(userId), "search", query] as const,
  folderCiphers: (userId: string, folderId: string) =>
    [...queryKeys.ciphers(userId), "folder", folderId] as const,

  // Specialized views
  favorites: (userId: string) => [...queryKeys.ciphers(userId), "favorites"] as const,
  recent: (userId: string) => [...queryKeys.ciphers(userId), "recent"] as const,
  trash: (userId: string) => [...queryKeys.ciphers(userId), "trash"] as const,

  // Server providers
  serverProviders: {
    all: () => ["serverProviders"] as const,
    current: () => [...queryKeys.serverProviders.all(), "current"] as const,
    info: () => [...queryKeys.serverProviders.all(), "info"] as const,
    connectivity: () => [...queryKeys.serverProviders.all(), "connectivity"] as const,
  },

  // Settings
  settings: {
    all: () => ["settings"] as const,
    current: () => [...queryKeys.settings.all(), "current"] as const,
  },

  // Users
  users: {
    all: () => ["users"] as const,
    byId: (userId: string) => [...queryKeys.users.all(), userId] as const,
    byEmail: (email: string) => [...queryKeys.users.all(), "email", email] as const,
  },
} as const;
