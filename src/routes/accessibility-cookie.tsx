import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/accessibility-cookie")({
  component: AccessibilityCookieComponent,
});

function AccessibilityCookieComponent() {
  return <div className="p-2">Hello from '/accessibility-cookie'!</div>;
}
