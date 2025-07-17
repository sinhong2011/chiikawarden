import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/send/")({
  component: SendIndexComponent,
});

function SendIndexComponent() {
  return <div className="p-2">Hello from '/send/'!</div>;
}
