import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/finish-signup")({
  component: FinishSignupComponent,
});

function FinishSignupComponent() {
  return <div className="p-2">Hello from '/finish-signup'!</div>;
}
