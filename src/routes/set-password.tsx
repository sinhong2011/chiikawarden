import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/set-password")({
  component: SetPasswordComponent,
});

function SetPasswordComponent() {
  return <div className="p-2">Hello from '/set-password'!</div>;
}
