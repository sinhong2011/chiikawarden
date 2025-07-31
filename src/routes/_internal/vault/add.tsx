import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/vault/add")({
  component: VaultAddComponent,
});

function VaultAddComponent() {
  return <div className="p-2">Hello from '/vault/add'!</div>;
}
