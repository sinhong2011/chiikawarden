// src/services/user-provider.service.ts

import { commands } from "@/lib/tauri-commands";
import { serverProviderService } from "@/services/server-provider.service";
import type { UserWithProvider } from "@/types/auth.types";

/**
 * Service for managing users with their associated server provider information
 */
export const userProviderService = {
  /**
   * Get all users with their associated server provider information
   */
  async getAllUsersWithProviders(): Promise<UserWithProvider[]> {
    try {
      // Get all users from database
      const usersResult = await commands.getAllUsers();
      if (usersResult.status === "error") {
        throw new Error(`Failed to fetch users: ${usersResult.error}`);
      }

      // Get all server providers
      const providersResult = await serverProviderService.getProviderInfo();
      const providers = providersResult.all_providers;

      // Create a map of provider ID to provider info for quick lookup
      const providerMap = new Map(
        providers.map((provider) => [provider.id, provider])
      );

      // Combine user data with provider information
      const usersWithProviders: UserWithProvider[] = usersResult.data.map((dbUser) => {
        const providerId = dbUser.server_provider_id || "us-cloud";
        const provider = providerMap.get(providerId);
        
        return {
          id: dbUser.id,
          email: dbUser.email,
          server_provider_id: providerId,
          provider_label: provider?.label || "Unknown Provider",
          provider_domain: provider?.urls.base || undefined,
        };
      });

      return usersWithProviders;
    } catch (error) {
      console.error("Failed to load users with provider info:", error);
      throw error;
    }
  },

  /**
   * Get a specific user with provider information
   */
  async getUserWithProvider(userId: string): Promise<UserWithProvider | null> {
    try {
      const users = await this.getAllUsersWithProviders();
      return users.find((user) => user.id === userId) || null;
    } catch (error) {
      console.error("Failed to get user with provider info:", error);
      return null;
    }
  },
};
