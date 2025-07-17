import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/404")({
  component: NotFoundComponent,
});

function NotFoundComponent() {
  return <div className="p-2">404 Not Found</div>;
}
