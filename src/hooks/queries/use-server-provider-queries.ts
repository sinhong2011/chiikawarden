import { useMutation, useQuery } from "@tanstack/react-query";
import { queryClient } from "@/lib/query-client";
import { queryKeys } from "@/lib/query-key";
import type {
  AddCustomProviderWithUrlsRequest as TauriAddCustomProviderWithUrlsRequest,
  UpdateProviderRequest as TauriUpdateProviderRequest,
} from "@/lib/tauri-commands";
import { serverProviderService } from "@/services/server-provider.service";
import type {
  AddCustomProviderWithUrlsRequest,
  UpdateProviderRequest,
} from "@/types/server-provider.types";

export const useServerProviderQueries = () => {
  // Query for all server providers
  const allProvidersQuery = useQuery({
    queryKey: queryKeys.serverProviders.all(),
    queryFn: () => serverProviderService.getAllProviders(),
    staleTime: 10 * 60 * 1000, // 10 minutes - provider list doesn't change frequently
    gcTime: 30 * 60 * 1000, // 30 minutes cache
    refetchOnMount: false, // Don't refetch on mount since providers are stable
    refetchOnWindowFocus: false, // Don't refetch on window focus
  });

  // Query for current server provider
  const currentProviderQuery = useQuery({
    queryKey: queryKeys.serverProviders.current(),
    queryFn: () => serverProviderService.getCurrentProvider(),
    staleTime: 10 * 60 * 1000, // 10 minutes - current provider doesn't change frequently
    gcTime: 30 * 60 * 1000, // 30 minutes cache
    refetchOnMount: false, // Don't refetch on mount since current provider is stable
    refetchOnWindowFocus: false, // Don't refetch on window focus
  });

  // Query for comprehensive provider info
  const providerInfoQuery = useQuery({
    queryKey: queryKeys.serverProviders.info(),
    queryFn: () => serverProviderService.getProviderInfo(),
    staleTime: 10 * 60 * 1000, // 10 minutes - provider info doesn't change frequently
    gcTime: 30 * 60 * 1000, // 30 minutes cache
    refetchOnMount: false, // Don't refetch on mount since provider info is stable
    refetchOnWindowFocus: false, // Don't refetch on window focus
  });

  // Mutation to set current provider
  const setCurrentProviderMutation = useMutation({
    mutationFn: async (providerId: string) => {
      await serverProviderService.setCurrentProvider(providerId);
    },
    onSuccess: () => {
      // Invalidate related queries
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.current() });
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.info() });
      queryClient.invalidateQueries({ queryKey: queryKeys.auth() });
    },
    onError: (error) => {
      console.error("Failed to set current server provider:", error);
    },
  });

  // Mutation to add custom provider
  const addCustomProviderMutation = useMutation({
    mutationFn: async (request: { label: string; baseUrl: string }) => {
      return await serverProviderService.addCustomProvider(request.label, request.baseUrl);
    },
    onSuccess: () => {
      // Invalidate provider queries
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.all() });
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.info() });
    },
    onError: (error) => {
      console.error("Failed to add custom server provider:", error);
    },
  });

  // Mutation to add custom provider with URLs
  const addCustomProviderWithUrlsMutation = useMutation({
    mutationFn: async (request: AddCustomProviderWithUrlsRequest) => {
      // Convert undefined to null to match Tauri command expectations
      const tauriRequest = {
        ...request,
        urls: {
          base: request.urls.base ?? null,
          api: request.urls.api ?? null,
          identity: request.urls.identity ?? null,
          icons: request.urls.icons ?? null,
          web_vault: request.urls.web_vault ?? null,
          notifications: request.urls.notifications ?? null,
          events: request.urls.events ?? null,
          key_connector: request.urls.key_connector ?? null,
          scim: request.urls.scim ?? null,
        },
      };
      return await serverProviderService.addCustomProviderWithUrls(
        tauriRequest as TauriAddCustomProviderWithUrlsRequest
      );
    },
    onSuccess: () => {
      // Invalidate provider queries
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.all() });
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.info() });
    },
    onError: (error) => {
      console.error("Failed to add custom server provider with URLs:", error);
    },
  });

  // Mutation to update provider
  const updateProviderMutation = useMutation({
    mutationFn: async (request: UpdateProviderRequest) => {
      // Convert undefined to null to match Tauri command expectations
      const tauriRequest = {
        ...request,
        label: request.label ?? null,
        urls: request.urls
          ? {
              base: request.urls.base ?? null,
              api: request.urls.api ?? null,
              identity: request.urls.identity ?? null,
              icons: request.urls.icons ?? null,
              web_vault: request.urls.web_vault ?? null,
              notifications: request.urls.notifications ?? null,
              events: request.urls.events ?? null,
              key_connector: request.urls.key_connector ?? null,
              scim: request.urls.scim ?? null,
            }
          : null,
      };
      await serverProviderService.updateProvider(tauriRequest as TauriUpdateProviderRequest);
    },
    onSuccess: () => {
      // Invalidate provider queries
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.all() });
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.info() });
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.current() });
    },
    onError: (error) => {
      console.error("Failed to update server provider:", error);
    },
  });

  // Mutation to remove provider
  const removeProviderMutation = useMutation({
    mutationFn: async (providerId: string) => {
      await serverProviderService.removeProvider(providerId);
    },
    onSuccess: () => {
      // Invalidate provider queries
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.all() });
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.info() });
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.current() });
    },
    onError: (error) => {
      console.error("Failed to remove server provider:", error);
    },
  });

  // Mutation to test connectivity
  const testConnectivityMutation = useMutation({
    mutationFn: async () => {
      return await serverProviderService.testConnectivity();
    },
    onError: (error) => {
      console.error("Failed to test server provider connectivity:", error);
    },
  });

  return {
    // Queries
    allProviders: allProvidersQuery,
    currentProvider: currentProviderQuery,
    providerInfo: providerInfoQuery,

    // Mutations
    setCurrentProvider: setCurrentProviderMutation,
    addCustomProvider: addCustomProviderMutation,
    addCustomProviderWithUrls: addCustomProviderWithUrlsMutation,
    updateProvider: updateProviderMutation,
    removeProvider: removeProviderMutation,
    testConnectivity: testConnectivityMutation,

    // Helper functions
    invalidateAll: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.all() });
    },
    invalidateCurrent: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.current() });
    },
    invalidateInfo: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.serverProviders.info() });
    },
  };
};
