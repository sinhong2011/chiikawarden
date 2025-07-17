import type {
  AddCustomProviderWithUrlsRequest,
  ServerProvider,
  UpdateProviderRequest,
} from "@/lib/tauri-commands";
import { commands } from "@/lib/tauri-commands";

// Also re-export for compatibility
export type {
  AddCustomProviderRequest,
  AddCustomProviderWithUrlsRequest,
  ConnectivityStatus,
  RemoveProviderRequest,
  ServerProvider,
  ServerProviderInfo,
  SetCurrentProviderRequest,
  UpdateProviderRequest,
} from "@/lib/tauri-commands";

export const serverProviderService = {
  /**
   * Get all available server providers
   */
  async getAllProviders() {
    const result = await commands.getAllServerProviders();

    if (result.status === "error") {
      throw new Error(`Failed to get server providers: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Get the current active server provider
   */
  async getCurrentProvider() {
    const result = await commands.getCurrentServerProvider();

    if (result.status === "error") {
      throw new Error(`Failed to get current server provider: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Get comprehensive server provider information
   */
  async getProviderInfo() {
    const result = await commands.getServerProviderInfo();

    if (result.status === "error") {
      throw new Error(`Failed to get server provider info: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Set the current active server provider
   */
  async setCurrentProvider(providerId: string) {
    const request = { provider_id: providerId };
    const result = await commands.setCurrentServerProvider(request);

    if (result.status === "error") {
      throw new Error(`Failed to set current server provider: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Add a new custom server provider
   */
  async addCustomProvider(label: string, baseUrl: string) {
    const request = { label, base_url: baseUrl };
    const result = await commands.addCustomServerProvider(request);

    if (result.status === "error") {
      throw new Error(`Failed to add custom server provider: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Add a new custom server provider with custom URLs
   */
  async addCustomProviderWithUrls(request: AddCustomProviderWithUrlsRequest) {
    const result = await commands.addCustomServerProviderWithUrls(request);

    if (result.status === "error") {
      throw new Error(`Failed to add custom server provider with URLs: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Update an existing server provider
   */
  async updateProvider(request: UpdateProviderRequest) {
    const result = await commands.updateServerProvider(request);

    if (result.status === "error") {
      throw new Error(`Failed to update server provider: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Remove a custom server provider
   */
  async removeProvider(providerId: string) {
    const request = { provider_id: providerId };
    const result = await commands.removeServerProvider(request);

    if (result.status === "error") {
      throw new Error(`Failed to remove server provider: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Test connectivity to the current server provider
   */
  async testConnectivity() {
    const result = await commands.testServerProviderConnectivity();

    if (result.status === "error") {
      throw new Error(`Failed to test server provider connectivity: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Get API URL for the current server provider
   */
  async getApiUrl() {
    const result = await commands.getServerProviderApiUrl();

    if (result.status === "error") {
      throw new Error(`Failed to get API URL: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Get identity URL for the current server provider
   */
  async getIdentityUrl() {
    const result = await commands.getServerProviderIdentityUrl();

    if (result.status === "error") {
      throw new Error(`Failed to get identity URL: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Get web vault URL for the current server provider
   */
  async getWebVaultUrl() {
    const result = await commands.getServerProviderWebVaultUrl();

    if (result.status === "error") {
      throw new Error(`Failed to get web vault URL: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Get icons URL for the current server provider
   */
  async getIconsUrl() {
    const result = await commands.getServerProviderIconsUrl();

    if (result.status === "error") {
      throw new Error(`Failed to get icons URL: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Get notifications URL for the current server provider
   */
  async getNotificationsUrl() {
    const result = await commands.getServerProviderNotificationsUrl();

    if (result.status === "error") {
      throw new Error(`Failed to get notifications URL: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Get events URL for the current server provider
   */
  async getEventsUrl() {
    const result = await commands.getServerProviderEventsUrl();

    if (result.status === "error") {
      throw new Error(`Failed to get events URL: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Validate a server URL format
   */
  validateUrl(url: string): boolean {
    try {
      new URL(url);
      return true;
    } catch {
      return false;
    }
  },

  /**
   * Format a base URL by removing trailing slashes
   */
  formatBaseUrl(url: string): string {
    return url.trim().replace(/\/+$/, "");
  },

  /**
   * Check if a provider is a preset provider
   */
  isPresetProvider(provider: ServerProvider): boolean {
    return provider.provider_type === "Preset";
  },

  /**
   * Check if a provider is a custom provider
   */
  isCustomProvider(provider: ServerProvider): boolean {
    return provider.provider_type === "Custom";
  },

  /**
   * Get display name for a provider (with type indicator)
   */
  getProviderDisplayName(provider: ServerProvider): string {
    const typeIndicator = this.isPresetProvider(provider) ? "" : " (Custom)";
    return `${provider.label}${typeIndicator}`;
  },

  /**
   * Get provider hostname from URLs
   */
  getProviderHostname(provider: ServerProvider): string {
    if (provider.urls.base) {
      try {
        return new URL(provider.urls.base).hostname;
      } catch {
        return "Unknown";
      }
    }
    if (provider.urls.api) {
      try {
        return new URL(provider.urls.api).hostname;
      } catch {
        return "Unknown";
      }
    }
    return "Unknown";
  },
};
