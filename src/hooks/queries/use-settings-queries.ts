import { useMutation, useQuery } from "@tanstack/react-query";
import { queryClient } from "@/lib/query-client";
import { queryKeys } from "@/lib/query-key";
import { type Settings, settingsService } from "@/services/settings.service";

/**
 * TanStack Query hooks for settings management
 * Following the user's preferred patterns for data fetching
 */
export const useSettingsQueries = () => {
  // Query for current settings
  const settingsQuery = useQuery({
    queryKey: queryKeys.settings.current(),
    queryFn: () => settingsService.getSettings(),
    staleTime: 1000 * 60 * 15, // 15 minutes - settings don't change often
    gcTime: 1000 * 60 * 60, // 1 hour cache - settings are rarely updated
    refetchOnMount: false, // Don't refetch on mount since settings are stable
    refetchOnWindowFocus: false, // Don't refetch on window focus
    retry: (failureCount, error) => {
      // Don't retry if app is not initialized
      if (error.message.includes("Application not initialized")) {
        return false;
      }
      return failureCount < 2;
    },
  });

  // Mutation for saving settings
  const saveSettingsMutation = useMutation({
    mutationFn: (settings: Settings) => settingsService.saveSettings(settings),
    onSuccess: () => {
      // Invalidate settings queries to refresh the UI
      queryClient.invalidateQueries({ queryKey: queryKeys.settings.all() });
      console.log("Settings saved successfully");
    },
    onError: (error) => {
      console.error("Failed to save settings:", error);
    },
  });

  // Mutation for resetting settings
  const resetSettingsMutation = useMutation({
    mutationFn: () => settingsService.resetSettings(),
    onSuccess: (resetSettings) => {
      // Update the cache with the reset settings
      queryClient.setQueryData(queryKeys.settings.current(), resetSettings);
      console.log("Settings reset to defaults");
    },
    onError: (error) => {
      console.error("Failed to reset settings:", error);
    },
  });

  // Mutation for updating theme
  const updateThemeMutation = useMutation({
    mutationFn: (theme: string) => settingsService.updateTheme(theme),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.settings.all() });
    },
    onError: (error) => {
      console.error("Failed to update theme:", error);
    },
  });

  // Mutation for updating language
  const updateLanguageMutation = useMutation({
    mutationFn: (language: string) => settingsService.updateLanguage(language),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.settings.all() });
    },
    onError: (error) => {
      console.error("Failed to update language:", error);
    },
  });

  // Mutation for updating vault timeout
  const updateVaultTimeoutMutation = useMutation({
    mutationFn: (timeout: number) => settingsService.updateVaultTimeout(timeout),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.settings.all() });
    },
    onError: (error) => {
      console.error("Failed to update vault timeout:", error);
    },
  });

  // Mutation for updating biometric unlock
  const updateBiometricUnlockMutation = useMutation({
    mutationFn: (enabled: boolean) => settingsService.updateBiometricUnlock(enabled),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.settings.all() });
    },
    onError: (error) => {
      console.error("Failed to update biometric unlock:", error);
    },
  });

  // Mutation for updating server URL
  const updateServerUrlMutation = useMutation({
    mutationFn: (serverUrl?: string) => settingsService.updateServerUrl(serverUrl),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.settings.all() });
    },
    onError: (error) => {
      console.error("Failed to update server URL:", error);
    },
  });

  // Mutation for updating multiple settings at once
  const updateSettingsMutation = useMutation({
    mutationFn: (updates: Partial<Settings>) => settingsService.updateSettings(updates),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.settings.all() });
    },
    onError: (error) => {
      console.error("Failed to update settings:", error);
    },
  });

  return {
    // Queries
    settings: settingsQuery,

    // Mutations
    saveSettings: saveSettingsMutation,
    resetSettings: resetSettingsMutation,
    updateTheme: updateThemeMutation,
    updateLanguage: updateLanguageMutation,
    updateVaultTimeout: updateVaultTimeoutMutation,
    updateBiometricUnlock: updateBiometricUnlockMutation,
    updateServerUrl: updateServerUrlMutation,
    updateSettings: updateSettingsMutation,

    // Helper functions
    invalidateSettings: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.settings.all() });
    },

    // Get current settings data from cache
    getCurrentSettings: () => {
      return queryClient.getQueryData<Settings>(queryKeys.settings.current());
    },
  };
};
