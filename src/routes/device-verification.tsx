import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/device-verification")({
  component: DeviceVerificationComponent,
});

function DeviceVerificationComponent() {
  return <div className="p-2">Hello from '/device-verification'!</div>;
}
