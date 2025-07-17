import { commands } from "@/lib/tauri-commands";

// Re-export types from tauri-commands for convenience
export type {
  MigrateLegacySettingsRequest,
  SaveSettingsRequest,
  Settings,
} from "@/lib/tauri-commands";

import type { Settings } from "@/lib/tauri-commands";

/**
 * Settings service for managing application settings
 * Uses the new tauri-plugin-store based backend
 */
export const settingsService = {
  /**
   * Get current application settings
   */
  async getSettings() {
    const result = await commands.getSettings();

    if (result.status === "error") {
      throw new Error(`Failed to get settings: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Save application settings
   */
  async saveSettings(settings: Settings) {
    const request = { settings };
    const result = await commands.saveSettings(request);

    if (result.status === "error") {
      throw new Error(`Failed to save settings: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Reset settings to defaults
   */
  async resetSettings() {
    const result = await commands.resetSettings();

    if (result.status === "error") {
      throw new Error(`Failed to reset settings: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Update theme setting
   */
  async updateTheme(theme: string) {
    const currentSettings = await this.getSettings();
    await this.saveSettings({
      ...currentSettings,
      theme,
    });
  },

  /**
   * Update language setting
   */
  async updateLanguage(language: string) {
    const currentSettings = await this.getSettings();
    await this.saveSettings({
      ...currentSettings,
      language,
    });
  },

  /**
   * Update vault timeout setting
   */
  async updateVaultTimeout(vault_timeout: number) {
    const currentSettings = await this.getSettings();
    await this.saveSettings({
      ...currentSettings,
      vault_timeout,
    });
  },

  /**
   * Update biometric unlock setting
   */
  async updateBiometricUnlock(biometric_unlock: boolean) {
    const currentSettings = await this.getSettings();
    await this.saveSettings({
      ...currentSettings,
      biometric_unlock,
    });
  },

  /**
   * Update server URL setting
   */
  async updateServerUrl(server_url?: string) {
    const currentSettings = await this.getSettings();
    await this.saveSettings({
      ...currentSettings,
      server_url: server_url || null,
    });
  },

  /**
   * Migrate legacy settings from browser storage to Tauri store
   */
  async migrateLegacySettings(legacySettingsJson: string) {
    const request = { legacy_settings: legacySettingsJson };
    const result = await commands.migrateLegacySettings(request);

    if (result.status === "error") {
      throw new Error(`Failed to migrate legacy settings: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Update multiple settings at once
   */
  async updateSettings(updates: Partial<Settings>) {
    const currentSettings = await this.getSettings();
    await this.saveSettings({
      ...currentSettings,
      ...updates,
    });
  },
};
