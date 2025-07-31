import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/vault/view/$id")({
  component: VaultViewComponent,
});

function VaultViewComponent() {
  const params = Route.useParams();
  return <div className="p-2">Hello from '/vault/view/{params.id}'!</div>;
}
