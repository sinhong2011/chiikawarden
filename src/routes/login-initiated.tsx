import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/login-initiated")({
  component: LoginInitiatedComponent,
});

function LoginInitiatedComponent() {
  return <div className="p-2">Hello from '/login-initiated'!</div>;
}
