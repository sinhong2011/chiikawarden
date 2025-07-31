import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/vault/clone/$id")({
  component: VaultCloneComponent,
});

function VaultCloneComponent() {
  const params = Route.useParams();
  return <div className="p-2">Hello from '/vault/clone/{params.id}'!</div>;
}
