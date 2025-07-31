import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_internal/generator/")({
  component: VaultGeneratorComponent,
});

function VaultGeneratorComponent() {
  return <div className="p-2">Hello from '/vault/generator'!</div>;
}
