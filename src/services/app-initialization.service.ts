import { preferencesMigrationService } from "./preferences-migration.service";
import { settingsService } from "./settings.service";

/**
 * Service to handle application initialization tasks including preferences migration
 */
export const appInitializationService = {
  /**
   * Initialize the application and handle any necessary migrations
   */
  async initialize(): Promise<void> {
    try {
      console.log("Starting application initialization...");

      // Check if legacy preferences migration is needed
      await this.handlePreferencesMigration();

      console.log("Application initialization completed successfully");
    } catch (error) {
      console.error("Failed to initialize application:", error);
      throw error;
    }
  },

  /**
   * Handle migration of legacy preferences to Tauri settings
   */
  async handlePreferencesMigration(): Promise<void> {
    try {
      // Check if migration is needed
      if (preferencesMigrationService.isMigrationComplete()) {
        console.log("Preferences migration already completed");
        return;
      }

      console.log("Legacy preferences detected, starting migration...");

      // Perform the migration
      const migrationSuccess = await preferencesMigrationService.performFullMigration();

      if (migrationSuccess) {
        console.log("Preferences migration completed successfully");
      } else {
        console.warn("Preferences migration failed or no legacy preferences found");
      }
    } catch (error) {
      console.error("Error during preferences migration:", error);
      // Don't throw here - migration failure shouldn't prevent app startup
    }
  },

  /**
   * Verify that settings service is working correctly
   */
  async verifySettingsService(): Promise<boolean> {
    try {
      const settings = await settingsService.getSettings();
      console.log("Settings service verification successful:", settings);
      return true;
    } catch (error) {
      console.error("Settings service verification failed:", error);
      return false;
    }
  },

  /**
   * Get initialization status
   */
  async getInitializationStatus(): Promise<{
    settingsServiceWorking: boolean;
    migrationComplete: boolean;
  }> {
    const settingsServiceWorking = await this.verifySettingsService();
    const migrationComplete = preferencesMigrationService.isMigrationComplete();

    return {
      settingsServiceWorking,
      migrationComplete,
    };
  },
};
