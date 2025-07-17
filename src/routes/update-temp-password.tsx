import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/update-temp-password")({
  component: UpdateTempPasswordComponent,
});

function UpdateTempPasswordComponent() {
  return <div className="p-2">Hello from '/update-temp-password'!</div>;
}
