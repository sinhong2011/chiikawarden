import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/settings/about")({
  component: SettingsAboutComponent,
});

function SettingsAboutComponent() {
  return <div className="p-2">Hello from '/settings/about'!</div>;
}
