import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/2fa")({
  component: TwoFAComponent,
});

function TwoFAComponent() {
  return <div className="p-2">Hello from '/2fa'!</div>;
}
