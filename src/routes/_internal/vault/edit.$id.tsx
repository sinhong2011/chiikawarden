import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/vault/edit/$id")({
  component: VaultEditComponent,
});

function VaultEditComponent() {
  const params = Route.useParams();
  return <div className="p-2">Hello from '/vault/edit/{params.id}'!</div>;
}
