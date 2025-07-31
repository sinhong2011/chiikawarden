import { createFileRoute, Outlet } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/send/__layout")({
  component: SendLayoutComponent,
});

function SendLayoutComponent() {
  return <Outlet />;
}
