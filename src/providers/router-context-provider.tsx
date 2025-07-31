import { RouterProvider } from "@tanstack/react-router";
import { queryClient } from "@/lib/query-client";
import type { RouterContext } from "@/lib/router";
import { router } from "@/lib/router";
import { useAuthStore } from "@/stores/auth.store";
import { useNavigationStore } from "@/stores/navigation.store";
import { useVaultStore } from "@/stores/vault.store";

interface RouterContextProviderProps {
  children?: never; // RouterProvider doesn't accept children
}

/**
 * Router Context Provider
 *
 * This component provides context to TanStack Router that includes:
 * - All store instances for state management
 * - QueryClient for data fetching
 *
 * Routes access stores directly through the context, providing a single,
 * consistent way to access application state.
 */
export function RouterContextProvider(_props: RouterContextProviderProps) {
  // Get store instances
  const authStore = useAuthStore();
  const vaultStore = useVaultStore();
  const navigationStore = useNavigationStore();

  // Build router context
  const routerContext: RouterContext = {
    queryClient,
    authStore,
    vaultStore,
    navigationStore,
  };

  return <RouterProvider router={router} context={routerContext} />;
}
