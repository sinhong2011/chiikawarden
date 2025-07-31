// Debug script for vault synchronization with Vaultwarden
// This script helps diagnose issues with vault items not appearing in the application

import { commands } from "@/lib/tauri-commands";
import { authService } from "@/services/auth.service";
import { syncService } from "@/services/sync.service";
import { vaultService } from "@/services/vault.service";

interface DebugResult {
  step: string;
  success: boolean;
  data?: any;
  error?: string;
  timestamp: string;
}

class VaultSyncDebugger {
  private results: DebugResult[] = [];

  private log(step: string, success: boolean, data?: any, error?: string) {
    const result: DebugResult = {
      step,
      success,
      data,
      error,
      timestamp: new Date().toISOString(),
    };
    this.results.push(result);
    console.log(`[DEBUG] ${step}:`, success ? "✅ SUCCESS" : "❌ FAILED", data || error);
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

  async debugVaultSync(userId: string): Promise<DebugResult[]> {
    console.log("🔍 Starting Vault Synchronization Debug for user:", userId);

    try {
      // Step 1: Check authentication state
      await this.checkAuthenticationState(userId);

      // Step 2: Verify access token retrieval
      await this.checkAccessToken(userId);

      // Step 3: Test direct API connectivity
      await this.testApiConnectivity(userId);

      // Step 4: Test sync vault command
      await this.testSyncVault(userId);

      // Step 5: Test get_all_ciphers command
      await this.testGetAllCiphers(userId);

      // Step 6: Check local database state
      await this.checkLocalDatabase(userId);

      // Step 7: Test vault service
      await this.testVaultService(userId);

      // Step 8: Force sync and retest
      await this.forceSyncAndRetest(userId);
    } catch (error) {
      this.log("Debug Process", false, null, `Unexpected error: ${error}`);
    }

    this.printSummary();
    return this.results;
  }

  private async checkAuthenticationState(userId: string) {
    try {
      // Check if user is authenticated
      const allUsers = await commands.getAllUsers();

      if (allUsers.status === "error") {
        this.log("Authentication State", false, null, `Failed to get users: ${allUsers.error}`);
        return;
      }

      const user = allUsers.data.find((u) => u.id === userId);
      this.log("Authentication State", !!user, {
        userFound: !!user,
        totalUsers: allUsers.data.length,
        userEmail: user?.email,
      });
    } catch (error) {
      this.log("Authentication State", false, null, `Error: ${error}`);
    }
  }

  private async checkAccessToken(userId: string) {
    try {
      // Use the new comprehensive token diagnostic command
      const diagnostic = await commands.diagnoseTokenStatus(userId);

      if (diagnostic.status === "ok") {
        const result = diagnostic.data;
        this.log("Token Diagnostic", result.access_token_present && result.refresh_token_present, {
          accessTokenPresent: result.access_token_present,
          refreshTokenPresent: result.refresh_token_present,
          accessTokenExpired: result.access_token_expired,
          recommendations: result.recommendations,
          timestamp: result.timestamp,
        });

        // Log specific issues if any
        if (!result.refresh_token_present) {
          this.log(
            "Refresh Token Issue",
            false,
            null,
            "❌ CRITICAL: No refresh token found - this is the root cause of sync failures"
          );
        }

        if (result.access_token_expired === true) {
          this.log("Access Token Issue", false, null, "⚠️ Access token is expired");
        }
      } else {
        this.log(
          "Token Diagnostic",
          false,
          null,
          `Failed to run token diagnostic: ${diagnostic.error}`
        );
      }
    } catch (error) {
      // Fallback to old method if new diagnostic fails
      try {
        const syncStatus = await syncService.getSyncStatus(userId);
        this.log("Access Token Check", true, {
          note: "Access token appears to be available",
          syncStatusAvailable: true,
          syncStatus: syncStatus,
        });
      } catch (fallbackError) {
        const errorMessage = this.formatError(fallbackError);
        if (errorMessage.includes("No access token found")) {
          this.log(
            "Access Token Check",
            false,
            null,
            `No access token stored for user: ${errorMessage}`
          );
        } else {
          this.log("Access Token Check", false, null, `Token check failed: ${errorMessage}`);
        }
      }
    }
  }

  private async testApiConnectivity(userId: string) {
    try {
      // Test basic API connectivity by trying to get sync status
      const syncStatus = await syncService.getSyncStatus(userId);
      this.log("API Connectivity", true, syncStatus);
    } catch (error) {
      this.log("API Connectivity", false, null, `Error: ${this.formatError(error)}`);
    }
  }

  private async testSyncVault(userId: string) {
    try {
      console.log("🔄 Testing vault sync...");
      const syncResult = await syncService.syncVault(userId);
      this.log("Sync Vault Command", true, syncResult);
    } catch (error) {
      this.log("Sync Vault Command", false, null, `Error: ${this.formatError(error)}`);
    }
  }

  private async testGetAllCiphers(userId: string) {
    try {
      console.log("📋 Testing get all ciphers...");
      const ciphers = await vaultService.getAllCiphers(userId);
      this.log("Get All Ciphers", true, {
        count: ciphers.length,
        cipherIds: ciphers.map((c) => c.id),
        cipherNames: ciphers.map((c) => c.name),
      });
    } catch (error) {
      this.log("Get All Ciphers", false, null, `Error: ${error}`);
    }
  }

  private async checkLocalDatabase(userId: string) {
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
        "Local Database",
        dbHealth.status === "ok",
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
      this.log("Local Database", false, null, `Error: ${error}`);
    }
  }

  private async testVaultService(userId: string) {
    try {
      // Test the vault service directly
      const ciphers = await vaultService.getAllCiphers(userId);
      const folders = await vaultService.getFolders(userId);

      this.log("Vault Service", true, {
        ciphersCount: ciphers.length,
        foldersCount: folders.length,
        hasCiphers: ciphers.length > 0,
        firstCipherName: ciphers.length > 0 ? ciphers[0].name : null,
        cipherTypes: ciphers.map((c) => c.cipher_type),
      });
    } catch (error) {
      this.log("Vault Service", false, null, `Error: ${error}`);
    }
  }

  private async forceSyncAndRetest(userId: string) {
    try {
      console.log("🔄 Force syncing and retesting...");

      // Force a fresh sync
      await syncService.syncVault(userId);

      // Wait a moment for sync to complete
      await new Promise((resolve) => setTimeout(resolve, 1000));

      // Test again
      const ciphers = await vaultService.getAllCiphers(userId);

      this.log("Force Sync & Retest", true, {
        ciphersAfterSync: ciphers.length,
        syncSuccessful: true,
        cipherNames: ciphers.map((c) => c.name),
      });
    } catch (error) {
      this.log("Force Sync & Retest", false, null, `Error: ${this.formatError(error)}`);
    }
  }

  private printSummary() {
    console.log("\n📊 VAULT SYNC DEBUG SUMMARY");
    console.log("=".repeat(50));

    const successCount = this.results.filter((r) => r.success).length;
    const totalCount = this.results.length;

    console.log(
      `Overall Success Rate: ${successCount}/${totalCount} (${Math.round((successCount / totalCount) * 100)}%)`
    );
    console.log("");

    this.results.forEach((result, index) => {
      const status = result.success ? "✅" : "❌";
      console.log(`${index + 1}. ${status} ${result.step}`);
      if (!result.success && result.error) {
        console.log(`   Error: ${result.error}`);
      }
      if (result.success && result.data) {
        console.log(`   Data:`, JSON.stringify(result.data, null, 2));
      }
    });

    console.log("\n🔍 RECOMMENDATIONS:");

    // Analyze results and provide recommendations
    const failedSteps = this.results.filter((r) => !r.success);

    if (failedSteps.length === 0) {
      console.log("✅ All steps passed! The issue might be in the UI layer or data binding.");
    } else {
      failedSteps.forEach((step) => {
        switch (step.step) {
          case "Authentication State":
            console.log(
              "❌ Authentication issue: Check if user is properly logged in and tokens are valid"
            );
            break;
          case "API Connectivity":
            console.log("❌ Network issue: Check Vaultwarden server URL and network connectivity");
            break;
          case "Sync Vault Command":
            console.log("❌ Sync issue: Check Vaultwarden API endpoints and authentication");
            break;
          case "Get All Ciphers":
            console.log(
              "❌ Cipher retrieval issue: Check if sync completed successfully and data is stored"
            );
            break;
          case "Local Database":
            console.log("❌ Database issue: Check database integrity and migrations");
            break;
          case "Vault Service":
            console.log(
              "❌ Service issue: Check vault service implementation and data transformation"
            );
            break;
        }
      });
    }
  }

  getResults(): DebugResult[] {
    return this.results;
  }
}

// Export for use in components
export { VaultSyncDebugger, type DebugResult };

// Usage example:
// const debugger = new VaultSyncDebugger();
// const results = await debugger.debugVaultSync(userId);
