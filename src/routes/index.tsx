import { useLingui } from "@lingui/react/macro";
import { createFileRoute, redirect, useNavigate } from "@tanstack/react-router";
import { useEffect } from "react";

export const Route = createFileRoute("/")({
  component: LandingComponent,
  beforeLoad: async ({ context }) => {
    // Smart routing based on authentication state
    const { auth } = context;

    console.log(
      "Root route - Auth status:",
      auth.authStatus,
      "Authenticated:",
      auth.isAuthenticated
    );

    // If user is authenticated and vault is unlocked, go to vault
    if (auth.authStatus === "unlocked" && auth.isAuthenticated) {
      throw redirect({ to: "/vault" });
    }

    // If user is authenticated but vault is locked, go to unlock
    if (auth.authStatus === "locked" && auth.isAuthenticated) {
      throw redirect({ to: "/unlock" });
    }

    // If user has pending 2FA, go to 2FA page (future implementation)
    if (auth.authStatus === "pending-2fa") {
      throw redirect({ to: "/login" }); // For now, redirect to login
    }

    // If user is not authenticated or logged out, go to login
    if (auth.authStatus === "logged-out" || !auth.isAuthenticated) {
      throw redirect({ to: "/login" });
    }

    // Fallback to login if state is unclear
    throw redirect({ to: "/login" });
  },
});

function LandingComponent() {
  // This component should rarely be rendered due to the beforeLoad redirects
  // But it serves as a fallback for edge cases
  const navigate = useNavigate();
  const { t } = useLingui();

  useEffect(() => {
    // Fallback navigation in case beforeLoad doesn't catch everything
    navigate({ to: "/login" });
  }, [navigate]);

  return (
    <div className="flex items-center justify-center h-full">
      <div className="text-center">
        <h1 className="text-2xl font-bold mb-4">{t`app_name`}</h1>
        <div className="flex items-center gap-2 justify-center">
          <div className="animate-spin h-4 w-4 border-2 border-primary border-t-transparent rounded-full"></div>
          <p className="text-base-content/70">{t`common.initializing`}</p>
        </div>
      </div>
    </div>
  );
}
