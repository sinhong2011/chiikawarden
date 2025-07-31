import { createFileRoute, Outlet } from "@tanstack/react-router";
import { createAuthGuard } from "@/lib/router-guards";
import { InternalLayout } from "@/routes/_internal/-components/layout";

export const Route = createFileRoute("/_internal")({
  component: InternalRouteComponent,
  ...createAuthGuard(), // Apply auth guard to all internal routes
});

function InternalRouteComponent() {
  return (
    <InternalLayout>
      <Outlet />
    </InternalLayout>
  );
}
