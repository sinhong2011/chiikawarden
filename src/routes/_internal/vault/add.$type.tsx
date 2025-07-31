import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/vault/add/$type")({
  component: VaultAddTypeComponent,
});

function VaultAddTypeComponent() {
  const params = Route.useParams();
  return <div className="p-2">Hello from '/vault/add/{params.type}'!</div>;
}
