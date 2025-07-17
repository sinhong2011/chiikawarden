import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/vault/folder/add")({
  component: VaultFolderAddComponent,
});

function VaultFolderAddComponent() {
  return <div className="p-2">Hello from '/vault/folder/add'!</div>;
}
