import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/sso")({
  component: SSOComponent,
});

function SSOComponent() {
  return <div className="p-2">Hello from '/sso'!</div>;
}
