import { Tab, Tabs } from "@heroui/tabs";
import { useNavigate } from "@tanstack/react-router";
import { Key, Send, Settings, Shield } from "lucide-react";
import { cn } from "@/lib/utils";
import { type NavigationTabKey, useNavigationStore } from "@/stores/navigation.store";

// Navigation tab configuration with icons (extends the store configuration)
const navigationTabs = [
  {
    key: "vault" as const,
    label: "Vault",
    icon: Shield,
    path: "/vault",
    description: "Manage your passwords and credentials",
  },
  {
    key: "send" as const,
    label: "Send",
    icon: Send,
    path: "/send",
    description: "Securely share information",
  },
  {
    key: "generator" as const,
    label: "Generator",
    icon: Key,
    path: "/generator",
    description: "Generate secure passwords and keys",
  },
  {
    key: "settings" as const,
    label: "Settings",
    icon: Settings,
    path: "/settings",
    description: "Configure application settings",
  },
] as const;

export interface NavigationTabProps {
  className?: string;
}

/**
 * Navigation Tab Component
 *
 * Provides vertical navigation tabs for internal application pages with:
 * - Route-based active tab highlighting
 * - Programmatic navigation when tabs are clicked
 * - URL synchronization with selected tab
 * - Icon-only display with tooltip labels for minimalist design
 * - Hover tooltips showing tab labels and descriptions
 *
 * @example
 * ```tsx
 * function NavigationTab() {
 *   return (
 *     <aside className="w-16 border-r">
 *       <NavigationTab />
 *     </aside>
 *   );
 * }
 * ```
 */
export function NavigationTab({ className }: NavigationTabProps) {
  const navigate = useNavigate();

  // Use simplified Zustand store for navigation state
  const activeTab = useNavigationStore((state) => state.activeTab);
  const setActiveTab = useNavigationStore((state) => state.setActiveTab);

  // Handle tab selection - update store and navigate
  const handleTabChange = (key: string | number) => {
    const tabKey = key as NavigationTabKey;
    const tab = navigationTabs.find((t) => t.key === tabKey);

    if (tab) {
      // Update store state first
      setActiveTab(tabKey);
      // Then navigate to the new route
      navigate({ to: tab.path });
    }
  };

  return (
    <div className={cn("flex-1 w-full", className)}>
      <Tabs
        aria-label="Internal tab navigation"
        isVertical
        selectedKey={activeTab}
        onSelectionChange={handleTabChange}
        className="w-full justify-center"
        classNames={{
          base: "w-full",
          tabList: "w-full bg-transparent p-0 gap-1",
          tab: "flex-1 justify-center h-12 py-3 px-3 data-[selected=true]:bg-primary/10 data-[selected=true]:text-primary",
          tabContent: "w-full justify-center text-center group-data-[selected=true]:text-primary",
          cursor: "bg-primary/20 shadow-none",
          panel: "hidden", // We don't use tab panels, just navigation
        }}
        radius="lg"
      >
        {navigationTabs.map((tab) => {
          const IconComponent = tab.icon;
          return (
            <Tab
              key={tab.key}
              title={
                <div className="flex w-full gap-3 items-center">
                  <IconComponent className="size-5 flex-shrink-0" />
                  <span>{tab.label}</span>
                  <span className="sr-only">
                    {tab.label} - {tab.description}
                  </span>
                </div>
              }
            />
          );
        })}
      </Tabs>
    </div>
  );
}

// Export types and configuration for external use
export type { NavigationTabKey };
export { navigationTabs };
