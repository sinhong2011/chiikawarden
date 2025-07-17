import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/set-password-jit")({
  component: SetPasswordJitComponent,
});

function SetPasswordJitComponent() {
  return <div className="p-2">Hello from '/set-password-jit'!</div>;
}
