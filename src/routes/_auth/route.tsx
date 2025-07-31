import { useLingui } from "@lingui/react/macro";
import { createFileRoute, Outlet } from "@tanstack/react-router";
import { AccountSelectorCompact } from "@/components/auth/account-selector";
import { LanguageSwitcher } from "@/components/language-switcher";
import { createAuthGuard } from "@/lib/router-guards";

export const Route = createFileRoute("/_auth")({
  component: RouteComponent,
  ...createAuthGuard(), // Apply auth guard to all auth routes
});

function RouteComponent() {
  const { t } = useLingui();

  return (
    <div className="flex flex-col h-full p-4 gap-5">
      {/* Header with app name and saved accounts selector */}
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-base-content">{t`app_name` /* Chiikawarden */}</h1>
        <AccountSelectorCompact showLabel={true} />
      </div>

      {/* Main content area */}
      <div className="flex-1">
        <Outlet />
      </div>

      {/* Footer with language switcher */}
      <div className="flex justify-center items-center pt-4 border-t border-divider">
        <LanguageSwitcher />
      </div>
    </div>
  );
}
