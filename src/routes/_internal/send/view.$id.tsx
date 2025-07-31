import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/send/view/$id")({
  component: SendViewComponent,
});

function SendViewComponent() {
  const params = Route.useParams();
  return <div className="p-2">Hello from '/send/view/{params.id}'!</div>;
}
