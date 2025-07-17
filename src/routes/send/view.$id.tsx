import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/send/view/$id")({
  component: SendViewComponent,
});

function SendViewComponent() {
  const params = Route.useParams();
  return <div className="p-2">Hello from '/send/view/{params.id}'!</div>;
}
