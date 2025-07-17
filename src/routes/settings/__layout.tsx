import { createFileRoute, Outlet } from "@tanstack/react-router";

export const Route = createFileRoute("/settings/__layout")({
  component: SettingsLayoutComponent,
});

function SettingsLayoutComponent() {
  return (
    <div>
      <h1>Settings Layout</h1>
      <Outlet />
    </div>
  );
}
