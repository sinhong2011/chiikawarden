import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/settings/security")({
  component: SettingsSecurityComponent,
});

function SettingsSecurityComponent() {
  return <div className="p-2">Hello from '/settings/security'!</div>;
}
