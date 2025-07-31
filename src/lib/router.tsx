import type { QueryClient } from "@tanstack/react-query";
import { createRouter } from "@tanstack/react-router";
import { routeTree } from "@/routeTree.gen";
import type { AuthStore } from "@/stores/auth.store";
import type { NavigationStore } from "@/stores/navigation.store";
import type { VaultStore } from "@/stores/vault.store";

/**
 * Router Context Interface
 *
 * Provides access to all application stores and services through TanStack Router context.
 * This enables type-safe access to stores in route loaders, beforeLoad functions, and components.
 */
export interface RouterContext {
  // TanStack Query client for data fetching
  queryClient: QueryClient;

  // Store instances for all application state
  authStore: AuthStore;
  vaultStore: VaultStore;
  navigationStore: NavigationStore;
}

// Create router with proper context typing and performance optimizations
export const router = createRouter({
  routeTree,
  defaultPreload: "intent",
  // Disable router's internal preload caching to work better with external state management
  defaultPreloadStaleTime: 0,
  // Enable structural sharing for better performance
  defaultStructuralSharing: true,
  context: {
    queryClient: undefined as unknown as QueryClient,
    authStore: undefined as unknown as AuthStore,
    vaultStore: undefined as unknown as VaultStore,
    navigationStore: undefined as unknown as NavigationStore,
  },
});

// Register router type for TypeScript
declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
