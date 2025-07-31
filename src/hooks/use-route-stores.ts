import { useRouter } from "@tanstack/react-router";
import type { RouterContext } from "@/lib/router";
import type { AuthStore } from "@/stores/auth.store";
import type { VaultState } from "@/types/vault.types";

/**
 * Hook to access router context
 *
 * Provides access to the full router context including all stores.
 */
function useRouterContext(): RouterContext {
  const router = useRouter();
  return router.options.context as RouterContext;
}

/**
 * Hook to access auth store from router context
 *
 * Provides access to the full auth store instance for advanced operations
 * like calling store actions from within route components.
 *
 * @example
 * ```tsx
 * function MyRouteComponent() {
 *   const authStore = useRouteAuthStore();
 *
 *   const handleLogout = () => {
 *     authStore.logout();
 *   };
 *
 *   return <button onClick={handleLogout}>Logout</button>;
 * }
 * ```
 */
export function useRouteAuthStore() {
  const context = useRouterContext();
  return context.authStore;
}

/**
 * Hook to access vault store from router context
 *
 * Provides access to the full vault store instance for vault operations.
 *
 * @example
 * ```tsx
 * function VaultComponent() {
 *   const vaultStore = useRouteVaultStore();
 *
 *   const handleLoadVault = () => {
 *     vaultStore.loadVaultData(userId);
 *   };
 *
 *   return <button onClick={handleLoadVault}>Load Vault</button>;
 * }
 * ```
 */
export function useRouteVaultStore() {
  const context = useRouterContext();
  return context.vaultStore;
}

/**
 * Hook to access navigation store from router context
 *
 * Provides access to the navigation store for managing active tabs.
 *
 * @example
 * ```tsx
 * function NavigationComponent() {
 *   const navigationStore = useRouteNavigationStore();
 *
 *   const handleTabChange = (tab: string) => {
 *     navigationStore.setActiveTab(tab);
 *   };
 *
 *   return <button onClick={() => handleTabChange('vault')}>Vault</button>;
 * }
 * ```
 */
export function useRouteNavigationStore() {
  const context = useRouterContext();
  return context.navigationStore;
}

// useRouteAuth removed - use useRouteAuthStore() directly to access auth state

/**
 * Hook to access vault state from router context
 *
 * Provides reactive access to vault state. Use this when you need to
 * read vault state but don't need to call vault actions.
 *
 * @example
 * ```tsx
 * function VaultStatsComponent() {
 *   const vaultState = useRouteVaultState();
 *
 *   return (
 *     <div>
 *       <p>Ciphers: {vaultState.ciphers.length}</p>
 *       <p>Loading: {vaultState.isLoading ? 'Yes' : 'No'}</p>
 *     </div>
 *   );
 * }
 * ```
 */
export function useRouteVaultState() {
  const vaultStore = useRouteVaultStore();
  return vaultStore
    ? ({
        ciphers: vaultStore.ciphers,
        folders: vaultStore.folders,
        collections: vaultStore.collections,
        isLoading: vaultStore.isLoading,
        searchQuery: vaultStore.searchQuery,
        selectedFolder: vaultStore.selectedFolder,
        selectedCipher: vaultStore.selectedCipher,
        showFavorites: vaultStore.showFavorites,
        lastSync: vaultStore.lastSync,
      } as VaultState)
    : null;
}

/**
 * Hook to access navigation state from router context
 *
 * Provides reactive access to navigation state.
 *
 * @example
 * ```tsx
 * function TabIndicator() {
 *   const activeTab = useRouteNavigationState();
 *
 *   return <div>Current tab: {activeTab}</div>;
 * }
 * ```
 */
export function useRouteNavigationState() {
  const navigationStore = useRouteNavigationStore();
  return navigationStore?.activeTab || "vault";
}

/**
 * Optimized selector hook for auth state
 *
 * Use this when you only need specific parts of the auth state
 * to avoid unnecessary re-renders.
 *
 * @example
 * ```tsx
 * function UserName() {
 *   const userName = useRouteAuthSelector(authStore => authStore.user?.name);
 *   return <span>{userName}</span>;
 * }
 * ```
 */
export function useRouteAuthSelector<T>(selector: (authStore: AuthStore) => T) {
  const context = useRouterContext();
  return selector(context.authStore);
}

/**
 * Optimized selector hook for vault state
 *
 * Use this when you only need specific parts of the vault state
 * to avoid unnecessary re-renders.
 *
 * @example
 * ```tsx
 * function CipherCount() {
 *   const count = useRouteVaultSelector(vault => vault.ciphers.length);
 *   return <span>Ciphers: {count}</span>;
 * }
 * ```
 */
export function useRouteVaultSelector<T>(selector: (vault: VaultState) => T) {
  const context = useRouterContext();
  const vaultStore = context.vaultStore;

  if (!vaultStore) return null;

  const vaultState: VaultState = {
    ciphers: vaultStore.ciphers,
    folders: vaultStore.folders,
    collections: vaultStore.collections,
    isLoading: vaultStore.isLoading,
    searchQuery: vaultStore.searchQuery,
    selectedFolder: vaultStore.selectedFolder,
    selectedCipher: vaultStore.selectedCipher,
    showFavorites: vaultStore.showFavorites,
    lastSync: vaultStore.lastSync,
  };

  return selector(vaultState);
}
