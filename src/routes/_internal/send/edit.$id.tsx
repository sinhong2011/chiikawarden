import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/send/edit/$id")({
  component: SendEditComponent,
});

function SendEditComponent() {
  const params = Route.useParams();
  return <div className="p-2">Hello from '/send/edit/{params.id}'!</div>;
}
