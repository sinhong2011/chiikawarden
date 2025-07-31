import { commands } from "@/lib/tauri-commands";
import { settingsService } from "./settings.service";

/**
 * User detection result for automatic authentication flow
 */
export interface UserDetectionResult {
  hasUsers: boolean;
  lastLoggedInUserId: string | null;
  shouldUseStreamlinedFlow: boolean;
  detectedUser?: {
    id: string;
    email: string;
  };
}

/**
 * Service to handle application initialization tasks
 */
export const appInitializationService = {
  /**
   * Initialize the application
   */
  async initialize(): Promise<void> {
    try {
      console.log("Starting application initialization...");

      // Verify settings service is working
      await this.verifySettingsService();

      console.log("Application initialization completed successfully");
    } catch (error) {
      console.error("Failed to initialize application:", error);
      throw error;
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
  }> {
    const settingsServiceWorking = await this.verifySettingsService();

    return {
      settingsServiceWorking,
    };
  },

  /**
   * Detect existing users and determine if streamlined authentication flow should be used
   */
  async detectUsers(): Promise<UserDetectionResult> {
    const fallbackResult: UserDetectionResult = {
      hasUsers: false,
      lastLoggedInUserId: null,
      shouldUseStreamlinedFlow: false,
    };

    try {
      console.log("Starting user detection for streamlined authentication...");

      // Get all users from database with timeout
      const usersResult = await Promise.race([
        commands.getAllUsers(),
        new Promise<{ status: "error"; error: string }>((_, reject) =>
          setTimeout(() => reject(new Error("Database query timeout")), 5000)
        ),
      ]);

      if (usersResult.status === "error") {
        console.error("Failed to get users from database:", usersResult.error);
        return fallbackResult;
      }

      const users = usersResult.data;
      const hasUsers = users.length > 0;

      if (!hasUsers) {
        console.log("No users found in database - new user flow");
        return {
          hasUsers: false,
          lastLoggedInUserId: null,
          shouldUseStreamlinedFlow: false,
        };
      }

      // Get last logged-in user from session data with timeout and validation
      let lastLoggedInUserId: string | null = null;
      try {
        const sessionResult = await Promise.race([
          commands.getValue({
            store_name: "auth-store",
            key: "session",
          }),
          new Promise<{ status: "error"; error: string }>((_, reject) =>
            setTimeout(() => reject(new Error("Session query timeout")), 3000)
          ),
        ]);

        if (sessionResult.status === "ok" && sessionResult.data.value) {
          try {
            const session = JSON.parse(sessionResult.data.value);
            // Validate session data structure
            if (session && typeof session === "object") {
              lastLoggedInUserId = session.lastLoggedInUserId || null;
              // Validate that the user ID is a non-empty string
              if (lastLoggedInUserId && typeof lastLoggedInUserId !== "string") {
                console.warn("Invalid lastLoggedInUserId type, ignoring");
                lastLoggedInUserId = null;
              }
            }
          } catch (parseError) {
            console.warn("Failed to parse session data:", parseError);
          }
        }
      } catch (error) {
        console.warn("Failed to get last logged-in user from session:", error);
        // Continue with null lastLoggedInUserId
      }

      // Find the detected user if we have a last logged-in user ID
      let detectedUser: { id: string; email: string } | undefined;
      if (lastLoggedInUserId) {
        try {
          const user = users.find((u) => u.id === lastLoggedInUserId);
          if (user?.id && user?.email) {
            detectedUser = {
              id: user.id,
              email: user.email,
            };
            console.log("Found last logged-in user:", user.email);
          } else {
            console.warn("Last logged-in user not found in database or invalid data");
          }
        } catch (error) {
          console.warn("Error finding last logged-in user:", error);
        }
      }

      // If no last logged-in user, but we have users, use the most recently created one
      if (!detectedUser && users.length > 0) {
        try {
          // Users are ordered by created_date ASC, so take the last one (most recent)
          const mostRecentUser = users[users.length - 1];
          if (mostRecentUser?.id && mostRecentUser?.email) {
            detectedUser = {
              id: mostRecentUser.id,
              email: mostRecentUser.email,
            };
            lastLoggedInUserId = mostRecentUser.id;
            console.log("Using most recent user:", mostRecentUser.email);
          } else {
            console.warn("Most recent user has invalid data");
          }
        } catch (error) {
          console.warn("Error selecting most recent user:", error);
        }
      }

      const shouldUseStreamlinedFlow = hasUsers && !!detectedUser;

      console.log("User detection completed:", {
        hasUsers,
        lastLoggedInUserId,
        shouldUseStreamlinedFlow,
        detectedUserEmail: detectedUser?.email,
      });

      return {
        hasUsers,
        lastLoggedInUserId,
        shouldUseStreamlinedFlow,
        detectedUser,
      };
    } catch (error) {
      console.error("User detection failed:", error);
      return {
        hasUsers: false,
        lastLoggedInUserId: null,
        shouldUseStreamlinedFlow: false,
      };
    }
  },
};
