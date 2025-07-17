import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/fido2")({
  component: Fido2Component,
});

function Fido2Component() {
  return <div className="p-2">Hello from '/fido2'!</div>;
}
