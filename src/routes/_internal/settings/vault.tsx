import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/settings/vault")({
  component: SettingsVaultComponent,
});

function SettingsVaultComponent() {
  return <div className="p-2">Hello from '/settings/vault'!</div>;
}
