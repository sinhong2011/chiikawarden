import { useLingui } from "@lingui/react/macro";
import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { LanguageSwitcher } from "@/components/language-switcher";

export const Route = createFileRoute("/_auth")({
  component: RouteComponent,
  beforeLoad: ({ context }) => {
    // Redirect authenticated users away from auth pages
    const { auth } = context;

    if (auth.isAuthenticated) {
      if (auth.authStatus === "unlocked") {
        throw redirect({ to: "/vault" });
      } else if (auth.authStatus === "locked") {
        throw redirect({ to: "/unlock" });
      }
    }
  },
});

function RouteComponent() {
  const { t } = useLingui();

  return (
    <div className="flex flex-col h-full p-4 gap-5">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-base-content">{t`app_name` /* Chiikawarden */}</h1>
        <LanguageSwitcher />
      </div>
      <div className="flex-1">
        <Outlet />
      </div>
    </div>
  );
}
