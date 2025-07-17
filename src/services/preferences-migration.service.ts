import type { Settings } from "@/lib/tauri-commands";
import { settingsService } from "./settings.service";

/**
 * Legacy preferences interface from storage.ts
 * Used only for migration purposes
 */
interface LegacyAppPreferences {
  theme: "light" | "dark" | "system";
  language: string;
  autoLock: boolean;
  autoLockTimeout: number; // minutes
  minimizeToTray: boolean;
  startMinimized: boolean;
  clearClipboard: boolean;
  clearClipboardTimeout: number; // seconds
}

/**
 * Migration service to transfer legacy browser-stored preferences to Tauri settings
 */
export const preferencesMigrationService = {
  /**
   * Check if legacy preferences exist in browser storage
   */
  hasLegacyPreferences(): boolean {
    try {
      const stored = localStorage.getItem("chiikawarden_preferences");
      return stored !== null;
    } catch {
      return false;
    }
  },

  /**
   * Load legacy preferences from browser storage
   */
  loadLegacyPreferences(): LegacyAppPreferences | null {
    try {
      const stored = localStorage.getItem("chiikawarden_preferences");
      if (!stored) return null;

      const parsed = JSON.parse(stored) as LegacyAppPreferences;
      return parsed;
    } catch (error) {
      console.warn("Failed to load legacy preferences:", error);
      return null;
    }
  },

  /**
   * Convert legacy preferences to Tauri Settings format
   */
  convertLegacyToSettings(legacy: LegacyAppPreferences): Partial<Settings> {
    return {
      theme: legacy.theme,
      language: legacy.language,
      vault_timeout: legacy.autoLockTimeout,
      vault_timeout_action: legacy.autoLock ? "lock" : "logout",
      clear_clipboard: legacy.clearClipboard ? legacy.clearClipboardTimeout : 0,
      minimize_to_tray: legacy.minimizeToTray,
      start_to_tray: legacy.startMinimized,
      // Set reasonable defaults for new fields
      biometric_unlock: false,
      auto_start: false,
      server_url: undefined,
    };
  },

  /**
   * Migrate legacy preferences to Tauri settings
   */
  async migrateLegacyPreferences(): Promise<boolean> {
    try {
      // Check if legacy preferences exist
      if (!this.hasLegacyPreferences()) {
        console.log("No legacy preferences found to migrate");
        return false;
      }

      // Load legacy preferences
      const legacyPrefs = this.loadLegacyPreferences();
      if (!legacyPrefs) {
        console.warn("Failed to load legacy preferences for migration");
        return false;
      }

      console.log("Migrating legacy preferences:", legacyPrefs);

      // Get current Tauri settings (this will create defaults if none exist)
      const currentSettings = await settingsService.getSettings();

      // Convert legacy preferences to Tauri format
      const convertedSettings = this.convertLegacyToSettings(legacyPrefs);

      // Merge with current settings (legacy takes precedence for existing fields)
      const mergedSettings: Settings = {
        ...currentSettings,
        ...convertedSettings,
      };

      // Save the merged settings
      await settingsService.saveSettings(mergedSettings);

      console.log("Successfully migrated legacy preferences to Tauri settings");
      return true;
    } catch (error) {
      console.error("Failed to migrate legacy preferences:", error);
      return false;
    }
  },

  /**
   * Clean up legacy preferences from browser storage after successful migration
   */
  cleanupLegacyPreferences(): void {
    try {
      // Remove the main preferences
      localStorage.removeItem("chiikawarden_preferences");

      // Also remove any Zustand persisted preferences
      localStorage.removeItem("chiikawarden_app-preferences");

      console.log("Cleaned up legacy preferences from browser storage");
    } catch (error) {
      console.warn("Failed to cleanup legacy preferences:", error);
    }
  },

  /**
   * Full migration process: migrate and cleanup
   */
  async performFullMigration(): Promise<boolean> {
    const migrationSuccess = await this.migrateLegacyPreferences();

    if (migrationSuccess) {
      this.cleanupLegacyPreferences();
    }

    return migrationSuccess;
  },

  /**
   * Check if migration has been completed (no legacy preferences exist)
   */
  isMigrationComplete(): boolean {
    return !this.hasLegacyPreferences();
  },
};
