import { createFileRoute, Outlet } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/settings/__layout")({
  component: SettingsLayoutComponent,
});

function SettingsLayoutComponent() {
  return <Outlet />;
}
