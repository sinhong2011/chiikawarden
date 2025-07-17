import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/authentication-timeout")({
  component: AuthenticationTimeoutComponent,
});

function AuthenticationTimeoutComponent() {
  return <div className="p-2">Hello from '/authentication-timeout'!</div>;
}
