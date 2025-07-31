// Settings diagnostics for comprehensive application health checking
// This script helps diagnose issues with settings, authentication, database, and system configuration

import { commands } from "@/lib/tauri-commands";
import { settingsService } from "@/services/settings.service";
import { syncService } from "@/services/sync.service";
import { vaultService } from "@/services/vault.service";

export interface DiagnosticResult {
  step: string;
  success: boolean;
  data?: Record<string, unknown>;
  error?: string;
  timestamp: string;
  category: DiagnosticCategory;
}

export enum DiagnosticCategory {
  SETTINGS = "settings",
  AUTHENTICATION = "authentication",
  DATABASE = "database",
  NETWORK = "network",
  SYSTEM = "system",
  VAULT = "vault",
}

export class SettingsDiagnostics {
  private results: DiagnosticResult[] = [];

  private log(
    step: string,
    success: boolean,
    category: DiagnosticCategory,
    data?: Record<string, unknown>,
    error?: string
  ) {
    const result: DiagnosticResult = {
      step,
      success,
      category,
      data,
      error,
      timestamp: new Date().toISOString(),
    };
    this.results.push(result);
    console.log(`[DIAGNOSTICS] ${step}:`, success ? "✅ SUCCESS" : "❌ FAILED", data || error);
  }

  private formatError(error: any): string {
    if (typeof error === "string") {
      return error;
    }
    if (error instanceof Error) {
      return `${error.name}: ${error.message}`;
    }
    if (error && typeof error === "object") {
      if (error.message) {
        return error.message;
      }
      return JSON.stringify(error, null, 2);
    }
    return String(error);
  }

  async runDiagnostics(userId: string): Promise<DiagnosticResult[]> {
    console.log("🔍 Starting Comprehensive Settings Diagnostics for user:", userId);

    try {
      // Step 1: Check settings storage and configuration
      await this.checkSettingsStorage();

      // Step 2: Check authentication state and tokens
      await this.checkAuthenticationState(userId);

      // Step 3: Check database health and connectivity
      await this.checkDatabaseHealth();

      // Step 4: Check system configuration
      await this.checkSystemConfiguration();

      // Step 5: Check network connectivity and API access
      await this.checkNetworkConnectivity(userId);

      // Step 6: Check vault synchronization status
      await this.checkVaultSyncStatus(userId);

      // Step 7: Validate application state consistency
      await this.validateApplicationState(userId);
    } catch (error) {
      this.log(
        "Diagnostics Process",
        false,
        DiagnosticCategory.SYSTEM,
        undefined,
        `Unexpected error: ${error}`
      );
    }

    this.printSummary();
    return this.results;
  }

  private async checkSettingsStorage() {
    try {
      // Test settings retrieval
      const settings = await settingsService.getSettings();

      this.log("Settings Storage", true, DiagnosticCategory.SETTINGS, {
        theme: settings.theme,
        language: settings.language,
        vaultTimeout: settings.vault_timeout,
        serverUrl: settings.server_url ? "configured" : "default",
        debugMode: settings.debug_token_operations,
        biometricUnlock: settings.biometric_unlock,
        autoStart: settings.auto_start,
      });

      // Test settings save functionality
      try {
        await settingsService.saveSettings(settings);
        this.log("Settings Save Test", true, DiagnosticCategory.SETTINGS, {
          message: "Settings save/load cycle successful",
        });
      } catch (saveError) {
        this.log(
          "Settings Save Test",
          false,
          DiagnosticCategory.SETTINGS,
          undefined,
          `Settings save failed: ${this.formatError(saveError)}`
        );
      }
    } catch (error) {
      this.log(
        "Settings Storage",
        false,
        DiagnosticCategory.SETTINGS,
        undefined,
        `Settings retrieval failed: ${this.formatError(error)}`
      );
    }
  }

  private async checkAuthenticationState(userId: string) {
    try {
      // Check if user exists
      const allUsers = await commands.getAllUsers();

      if (allUsers.status === "error") {
        this.log(
          "User Authentication",
          false,
          DiagnosticCategory.AUTHENTICATION,
          undefined,
          `Failed to get users: ${allUsers.error}`
        );
        return;
      }

      const user = allUsers.data.find((u) => u.id === userId);
      this.log("User Authentication", !!user, DiagnosticCategory.AUTHENTICATION, {
        userFound: !!user,
        totalUsers: allUsers.data.length,
        userEmail: user?.email,
      });

      // Check token status using comprehensive diagnostic
      try {
        const diagnostic = await commands.diagnoseTokenStatus(userId);

        if (diagnostic.status === "ok") {
          const result = diagnostic.data;
          this.log(
            "Token Diagnostic",
            result.access_token_present && result.refresh_token_present,
            DiagnosticCategory.AUTHENTICATION,
            {
              accessTokenPresent: result.access_token_present,
              refreshTokenPresent: result.refresh_token_present,
              accessTokenExpired: result.access_token_expired,
              recommendations: result.recommendations,
            }
          );
        } else {
          this.log(
            "Token Diagnostic",
            false,
            DiagnosticCategory.AUTHENTICATION,
            undefined,
            `Token diagnostic failed: ${diagnostic.error}`
          );
        }
      } catch (tokenError) {
        this.log(
          "Token Diagnostic",
          false,
          DiagnosticCategory.AUTHENTICATION,
          undefined,
          `Token check failed: ${this.formatError(tokenError)}`
        );
      }
    } catch (error) {
      this.log(
        "User Authentication",
        false,
        DiagnosticCategory.AUTHENTICATION,
        undefined,
        `Authentication check failed: ${this.formatError(error)}`
      );
    }
  }

  private async checkDatabaseHealth() {
    try {
      // Check database health
      const dbHealth = await commands.getDatabaseHealth();

      let dbStats = null;
      // Only try to get stats in development mode
      if (import.meta.env.DEV) {
        try {
          dbStats = await commands.getDatabaseStats();
        } catch (error) {
          console.warn("Database stats not available (development only):", error);
        }
      }

      this.log(
        "Database Health",
        dbHealth.status === "ok",
        DiagnosticCategory.DATABASE,
        {
          health: dbHealth.status === "ok" ? dbHealth.data : null,
          stats: dbStats?.status === "ok" ? dbStats.data : null,
          statsAvailable: !!dbStats,
        },
        dbHealth.status === "error"
          ? typeof dbHealth.error === "string"
            ? dbHealth.error
            : JSON.stringify(dbHealth.error)
          : undefined
      );
    } catch (error) {
      this.log(
        "Database Health",
        false,
        DiagnosticCategory.DATABASE,
        undefined,
        `Database health check failed: ${this.formatError(error)}`
      );
    }
  }

  private async checkSystemConfiguration() {
    try {
      // Check keyring status if available
      try {
        const keyringStatus = await commands.checkKeyringBackend();
        if (keyringStatus.status === "ok") {
          this.log(
            "Keyring Status",
            keyringStatus.data.backend_available && keyringStatus.data.backend_type !== "mock",
            DiagnosticCategory.SYSTEM,
            {
              backendType: keyringStatus.data.backend_type,
              backendAvailable: keyringStatus.data.backend_available,
              canStoreRetrieve: keyringStatus.data.can_store_retrieve,
              secure: keyringStatus.data.backend_type !== "mock",
              errorMessage: keyringStatus.data.error_message,
            }
          );
        } else {
          this.log(
            "Keyring Status",
            false,
            DiagnosticCategory.SYSTEM,
            undefined,
            `Keyring check failed: ${keyringStatus.error}`
          );
        }
      } catch (keyringError) {
        this.log(
          "Keyring Status",
          false,
          DiagnosticCategory.SYSTEM,
          undefined,
          `Keyring not available: ${this.formatError(keyringError)}`
        );
      }

      // Check application environment
      this.log("Application Environment", true, DiagnosticCategory.SYSTEM, {
        isDevelopment: import.meta.env.DEV,
        mode: import.meta.env.MODE,
        userAgent: `${navigator.userAgent.substring(0, 100)}...`,
      });
    } catch (error) {
      this.log(
        "System Configuration",
        false,
        DiagnosticCategory.SYSTEM,
        undefined,
        `System check failed: ${this.formatError(error)}`
      );
    }
  }

  private async checkNetworkConnectivity(userId: string) {
    try {
      // Test basic API connectivity by trying to get sync status
      const syncStatus = await syncService.getSyncStatus(userId);
      this.log("Network Connectivity", true, DiagnosticCategory.NETWORK, {
        syncStatusAvailable: true,
        lastSync: syncStatus.last_sync,
        isSyncing: syncStatus.is_syncing,
        revisionDate: syncStatus.revision_date,
      });
    } catch (error) {
      this.log(
        "Network Connectivity",
        false,
        DiagnosticCategory.NETWORK,
        undefined,
        `Network connectivity failed: ${this.formatError(error)}`
      );
    }
  }

  private async checkVaultSyncStatus(userId: string) {
    try {
      // Check current vault state
      const ciphers = await vaultService.getAllCiphers(userId);
      const folders = await vaultService.getFolders(userId);

      this.log("Vault Status", true, DiagnosticCategory.VAULT, {
        ciphersCount: ciphers.length,
        foldersCount: folders.length,
        hasCiphers: ciphers.length > 0,
        cipherTypes: ciphers.map((c) => c.cipher_type),
      });
    } catch (error) {
      this.log(
        "Vault Status",
        false,
        DiagnosticCategory.VAULT,
        undefined,
        `Vault status check failed: ${this.formatError(error)}`
      );
    }
  }

  private async validateApplicationState(_userId: string) {
    try {
      // Validate that all critical components are working together
      const validationChecks = [];

      // Check if settings and authentication are consistent
      try {
        const settings = await settingsService.getSettings();
        const users = await commands.getAllUsers();

        validationChecks.push({
          check: "Settings-Auth Consistency",
          passed: users.status === "ok" && !!settings,
          details: "Settings and authentication systems are accessible",
        });
      } catch (error) {
        validationChecks.push({
          check: "Settings-Auth Consistency",
          passed: false,
          error: this.formatError(error),
        });
      }

      const allPassed = validationChecks.every((check) => check.passed);

      this.log("Application State Validation", allPassed, DiagnosticCategory.SYSTEM, {
        checks: validationChecks,
        overallHealth: allPassed ? "healthy" : "issues_detected",
      });
    } catch (error) {
      this.log(
        "Application State Validation",
        false,
        DiagnosticCategory.SYSTEM,
        undefined,
        `Validation failed: ${this.formatError(error)}`
      );
    }
  }

  private printSummary() {
    console.log("\n📊 SETTINGS DIAGNOSTICS SUMMARY");
    console.log("=".repeat(50));

    const successCount = this.results.filter((r) => r.success).length;
    const totalCount = this.results.length;

    console.log(
      `Overall Success Rate: ${successCount}/${totalCount} (${Math.round((successCount / totalCount) * 100)}%)`
    );

    // Group results by category
    const categories = Object.values(DiagnosticCategory);
    categories.forEach((category) => {
      const categoryResults = this.results.filter((r) => r.category === category);
      const categorySuccess = categoryResults.filter((r) => r.success).length;

      if (categoryResults.length > 0) {
        console.log(`\n${category.toUpperCase()}: ${categorySuccess}/${categoryResults.length}`);
        categoryResults.forEach((result) => {
          const status = result.success ? "✅" : "❌";
          console.log(`  ${status} ${result.step}`);
          if (!result.success && result.error) {
            console.log(`     Error: ${result.error}`);
          }
        });
      }
    });

    console.log("\n🔍 RECOMMENDATIONS:");
    this.generateRecommendations();
  }

  private generateRecommendations() {
    const failedSteps = this.results.filter((r) => !r.success);

    if (failedSteps.length === 0) {
      console.log("✅ All diagnostics passed! Your application is healthy.");
      return;
    }

    // Group failures by category and provide specific recommendations
    const failuresByCategory = failedSteps.reduce(
      (acc, step) => {
        if (!acc[step.category]) acc[step.category] = [];
        acc[step.category].push(step);
        return acc;
      },
      {} as Record<DiagnosticCategory, DiagnosticResult[]>
    );

    Object.entries(failuresByCategory).forEach(([category, failures]) => {
      console.log(`\n❌ ${category.toUpperCase()} Issues:`);
      failures.forEach((failure) => {
        switch (failure.step) {
          case "Settings Storage":
            console.log("  • Check settings file permissions and storage location");
            break;
          case "User Authentication":
            console.log("  • Verify user login status and re-authenticate if needed");
            break;
          case "Token Diagnostic":
            console.log("  • Clear tokens and log in again to refresh authentication");
            break;
          case "Database Health":
            console.log("  • Check database file integrity and permissions");
            break;
          case "Keyring Status":
            console.log("  • Ensure system keyring service is available and configured");
            break;
          case "Network Connectivity":
            console.log("  • Check internet connection and server URL configuration");
            break;
          case "Vault Status":
            console.log("  • Try manual sync to refresh vault data");
            break;
          default:
            console.log(`  • Review ${failure.step} configuration and logs`);
        }
      });
    });
  }

  getResults(): DiagnosticResult[] {
    return this.results;
  }
}
