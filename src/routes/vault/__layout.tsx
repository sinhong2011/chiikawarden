import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/vault/__layout")({
  component: VaultLayoutComponent,
  beforeLoad: ({ context }) => {
    // Ensure user is authenticated and vault is unlocked
    const { auth } = context;

    if (!auth.isAuthenticated || auth.authStatus !== "unlocked") {
      if (auth.authStatus === "locked") {
        throw redirect({ to: "/unlock" });
      } else {
        throw redirect({ to: "/login" });
      }
    }
  },
});

function VaultLayoutComponent() {
  return (
    <div>
      <h1>Vault Layout</h1>
      <Outlet />
    </div>
  );
}
