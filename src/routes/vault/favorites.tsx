import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/vault/favorites")({
  component: VaultFavoritesComponent,
});

function VaultFavoritesComponent() {
  return <div className="p-2">Hello from '/vault/favorites'!</div>;
}
