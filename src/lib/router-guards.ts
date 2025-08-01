import { redirect } from "@tanstack/react-router";
import type { RouterContext } from "@/lib/router";

// Define proper types for beforeLoad function parameters
interface BeforeLoadContext {
  context: RouterContext;
  location: {
    pathname: string;
  };
}

// Track last logged auth state to prevent spam
let lastLoggedState: string | null = null;

// Main auth guard - handles all authentication routing logic
export const createAuthGuard = () => ({
  beforeLoad: async ({ context, location }: BeforeLoadContext) => {
    const { authStore } = context;
    const { authStatus, isAuthenticated, userId } = authStore;

    // Development: Log state for debugging (but only when it changes)
    if (__DEV__) {
      const currentState = `${location.pathname}-${authStatus}-${isAuthenticated}-${userId}`;
      if (currentState !== lastLoggedState) {
        console.log(
          `[AuthGuard] ${location.pathname} - Status: ${authStatus}, Auth: ${isAuthenticated}, User: ${userId}`
        );
        lastLoggedState = currentState;
      }
    }

    // Route based on authentication state
    switch (authStatus) {
      case "unlocked":
        // User is fully authenticated and vault is unlocked
        if (location.pathname.startsWith("/auth") || location.pathname === "/") {
          console.log("[AuthGuard] User unlocked, redirecting to vault");
          throw redirect({ to: "/vault" });
        }
        break;

      case "locked":
        // User is authenticated but vault is locked
        if (
          !location.pathname.startsWith("/auth/unlock") &&
          !location.pathname.startsWith("/unlock")
        ) {
          console.log("[AuthGuard] User locked, redirecting to unlock");
          throw redirect({ to: "/unlock" });
        }
        break;

      case "identified":
        // User is known but needs authentication (development state)
        if (
          !location.pathname.startsWith("/auth/unlock") &&
          !location.pathname.startsWith("/unlock")
        ) {
          if (__DEV__) {
            console.log("[DEV] User identified, redirecting to unlock");
          }
          throw redirect({ to: "/unlock" });
        }
        break;

      case "pending-2fa":
        // User needs to complete 2FA
        if (location.pathname !== "/2fa" && location.pathname !== "/auth/2fa") {
          console.log("[AuthGuard] 2FA pending, redirecting to 2FA");
          throw redirect({ to: "/2fa" });
        }
        break;

      default:
        // User is not authenticated (logged-out or unknown state)
        if (
          location.pathname === "/" ||
          location.pathname.startsWith("/vault") ||
          location.pathname.startsWith("/_internal")
        ) {
          // Try automatic user detection first
          if (__DEV__) {
            console.log("[AuthGuard] Attempting automatic user detection");
          }

          const isDetectedUser = async () => {
            try {
              const detected = await authStore.detectAndSetupUser();

              return detected;
            } catch (error) {
              console.error("[AuthGuard] User detection failed:", error);
            }
          };

          if (await isDetectedUser()) {
            if (__DEV__) {
              console.log("[AuthGuard] User detected, redirecting to unlock");
            }
            throw redirect({ to: "/unlock" });
          }

          if (__DEV__) {
            console.log("[AuthGuard] No user detected, redirecting to login");
          }
          throw redirect({ to: "/login" });
        }
        break;
    }

    // Allow access to current route
    return;
  },
});

// Define simpler type for guards that only need context
interface GuardContext {
  context: RouterContext;
}

// Specific guard for routes that require authentication
export const requireAuth = () => ({
  beforeLoad: ({ context }: GuardContext) => {
    const { authStore } = context;

    if (!authStore.isAuthenticated) {
      throw redirect({ to: "/login" });
    }
  },
});

// Specific guard for routes that require unlocked vault
export const requireUnlocked = () => ({
  beforeLoad: ({ context }: GuardContext) => {
    const { authStore } = context;

    if (authStore.authStatus !== "unlocked") {
      if (authStore.authStatus === "locked" || authStore.authStatus === "identified") {
        throw redirect({ to: "/unlock" });
      } else {
        throw redirect({ to: "/login" });
      }
    }
  },
});

// Guard for auth pages (redirect if already authenticated)
export const requireGuest = () => ({
  beforeLoad: ({ context }: GuardContext) => {
    const { authStore } = context;

    if (authStore.isAuthenticated) {
      if (authStore.authStatus === "unlocked") {
        throw redirect({ to: "/vault" });
      } else if (authStore.authStatus === "locked") {
        throw redirect({ to: "/unlock" });
      }
    }
  },
});
