import { useRouter } from "@tanstack/react-router";
import type { AuthState } from "@/types/auth.types";

export const useTypedNavigation = () => {
  const router = useRouter();

  return {
    // Authentication flow navigation
    toLogin: () => router.navigate({ to: "/login" }),
    toSignup: () => router.navigate({ to: "/signup" }),
    toUnlock: () => router.navigate({ to: "/unlock" }),
    to2FA: () => router.navigate({ to: "/2fa" }),

    // Vault navigation
    toVault: () => router.navigate({ to: "/vault" }),
    toEditCipher: (id: string) => {
      router.navigate({ to: "/vault/edit/$id", params: { id } });
    },
    toViewCipher: (id: string) => {
      router.navigate({ to: "/vault/view/$id", params: { id } });
    },
    toCloneCipher: (id: string) => {
      router.navigate({ to: "/vault/clone/$id", params: { id } });
    },
    toAddCipher: (type?: string) => {
      if (type) {
        router.navigate({ to: "/vault/add/$type", params: { type } });
      } else {
        router.navigate({ to: "/vault/add" });
      }
    },
    toVaultSearch: (search?: { query?: string; type?: "login" | "card" }) => {
      router.navigate({ to: "/vault/search", search });
    },
    toVaultFavorites: () => router.navigate({ to: "/vault/favorites" }),
    toVaultTrash: () => router.navigate({ to: "/vault/trash" }),
    toPasswordGenerator: () => router.navigate({ to: "/vault/generator" }),

    // Send navigation
    toSend: () => router.navigate({ to: "/send" }),
    toAddSend: () => router.navigate({ to: "/send/add" }),
    toEditSend: (id: string) => {
      router.navigate({ to: "/send/edit/$id", params: { id } });
    },
    toViewSend: (id: string) => {
      router.navigate({ to: "/send/view/$id", params: { id } });
    },

    // Settings navigation
    toSettings: () => router.navigate({ to: "/settings" }),
    toSecuritySettings: () => router.navigate({ to: "/settings/security" }),
    toAccountSettings: () => router.navigate({ to: "/settings/account" }),
    toVaultSettings: () => router.navigate({ to: "/settings/vault" }),
    toOrganizationSettings: () => router.navigate({ to: "/settings/organizations" }),
    toAbout: () => router.navigate({ to: "/settings/about" }),
  };
};

/**
 * Smart navigation based on authentication state
 * This function determines where to redirect users based on their current auth status
 */
export const getSmartRedirectPath = (auth: AuthState): string => {
  // If user is authenticated and vault is unlocked, go to vault
  if (auth.isAuthenticated && auth.authStatus === "unlocked") {
    return "/vault";
  }

  // If user is authenticated but vault is locked, go to unlock
  if (auth.isAuthenticated && auth.authStatus === "locked") {
    return "/unlock";
  }

  // If user needs 2FA
  if (auth.isAuthenticated && auth.authStatus === "pending-2fa") {
    return "/2fa";
  }

  // If user is not authenticated, go to login
  return "/login";
};

/**
 * Hook for smart navigation that considers authentication state
 */
export const useSmartNavigation = () => {
  const router = useRouter();
  const navigation = useTypedNavigation();

  return {
    ...navigation,
    /**
     * Navigate to the most appropriate route based on current auth state
     */
    toSmartRoute: (auth: AuthState) => {
      const path = getSmartRedirectPath(auth);
      router.navigate({ to: path as "/login" | "/unlock" | "/2fa" | "/vault" });
    },
  };
};
