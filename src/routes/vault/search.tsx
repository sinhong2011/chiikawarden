import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/vault/search")({
  component: VaultSearchComponent,
});

function VaultSearchComponent() {
  return <div className="p-2">Hello from '/vault/search'!</div>;
}
