import { t } from "@lingui/core/macro";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { AccountDropdown } from "./account-dropdown";
import { NavigationTab } from "./navigation-tab";

export interface InternalLayoutProps {
  children: ReactNode;
  className?: string;
}

/**
 * Internal Layout Component
 *
 * Provides a consistent layout for internal application pages with:
 * - Left sidebar navigation using HeroUI Tabs in vertical mode
 * - Route-based active tab highlighting
 * - Programmatic navigation when tabs are clicked
 * - URL synchronization with selected tab
 *
 * @example
 * ```tsx
 * function VaultLayoutComponent() {
 *   return (
 *     <InternalLayout>
 *       <Outlet />
 *     </InternalLayout>
 *   );
 * }
 * ```
 */

export function InternalLayout({ children, className }: InternalLayoutProps) {
  return (
    <div className={cn("flex h-full bg-background", className)}>
      {/* Left Sidebar Navigation */}
      <aside className="w-60 border-r border-border bg-card flex flex-col p-3 gap-3">
        <div className="px-1">
          <h1 className="text-2xl font-bold text-foreground">{t`app_name`}</h1>
        </div>
        <NavigationTab />
        {/* Account Dropdown at bottom of sidebar */}
        <AccountDropdown />
      </aside>

      {/* Main Content Area */}
      <main className="flex-1 overflow-hidden">
        <div className="h-full overflow-auto">{children}</div>
      </main>
    </div>
  );
}
