import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/settings/account")({
  component: SettingsAccountComponent,
});

function SettingsAccountComponent() {
  return <div className="p-2">Hello from '/settings/account'!</div>;
}
