// src/stores/navigation.store.ts
import { create } from "zustand";

// Navigation tab configuration (re-exported from internal-layout for consistency)
export const navigationTabs = [
  {
    key: "vault",
    label: "Vault",
    path: "/vault",
    description: "Manage your passwords and credentials",
  },
  {
    key: "send",
    label: "Send",
    path: "/send",
    description: "Securely share information",
  },
  {
    key: "generator",
    label: "Generator",
    path: "/generator",
    description: "Generate secure passwords and keys",
  },
  {
    key: "settings",
    label: "Settings",
    path: "/settings",
    description: "Configure application settings",
  },
] as const;

export type NavigationTabKey = (typeof navigationTabs)[number]["key"];

// Simplified navigation store interface
export interface NavigationStore {
  activeTab: string;
  setActiveTab: (tab: string) => void;
}

/**
 * Simplified Navigation Zustand Store
 *
 * Manages global navigation state for the internal layout tabs.
 * Simplified to only store the active tab key as a string.
 *
 * @example
 * ```tsx
 * const activeTab = useNavigationStore(state => state.activeTab);
 * const setActiveTab = useNavigationStore(state => state.setActiveTab);
 *
 * // Set active tab
 * setActiveTab("vault");
 * ```
 */
export const useNavigationStore = create<NavigationStore>((set) => ({
  // State
  activeTab: "vault", // Default to vault tab

  // Actions
  setActiveTab: (tab: string) => {
    set({ activeTab: tab });
  },
}));

// Export navigation tabs configuration for external use
export { navigationTabs as navigationTabsConfig };
