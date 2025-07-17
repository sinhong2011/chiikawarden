import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/vault/trash")({
  component: VaultTrashComponent,
});

function VaultTrashComponent() {
  return <div className="p-2">Hello from '/vault/trash'!</div>;
}
