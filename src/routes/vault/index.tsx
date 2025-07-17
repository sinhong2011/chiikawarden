import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/vault/")({
  component: VaultIndexComponent,
});

function VaultIndexComponent() {
  return <div className="p-2">Hello from '/vault/'!</div>;
}
