import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/send/add")({
  component: SendAddComponent,
});

function SendAddComponent() {
  return <div className="p-2">Hello from '/send/add'!</div>;
}
