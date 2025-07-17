import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/vault/folder/edit/$id")({
  component: VaultFolderEditComponent,
});

function VaultFolderEditComponent() {
  const params = Route.useParams();
  return <div className="p-2">Hello from '/vault/folder/edit/{params.id}'!</div>;
}
