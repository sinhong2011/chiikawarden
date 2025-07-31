import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/settings/organizations")({
  component: SettingsOrganizationsComponent,
});

function SettingsOrganizationsComponent() {
  return <div className="p-2">Hello from '/settings/organizations'!</div>;
}
