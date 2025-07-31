// Email persistence hook - now integrated with auth store
// Provides the same API as the old useEmailPersistence but uses the auth store's session management

import { useAuthStore } from "@/stores/auth.store";

/**
 * Hook for email persistence in authentication forms
 * Now integrated with the auth store's session management to avoid duplication
 */
export function useEmailPersistence() {
  const authStore = useAuthStore();

  return {
    storeEmail: authStore.storeEmail,
    getStoredEmail: authStore.getStoredEmail,
    clearStoredEmail: authStore.clearStoredEmail,
  };
}
