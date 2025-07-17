import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/login-with-device")({
  component: LoginWithDeviceComponent,
});

function LoginWithDeviceComponent() {
  return <div className="p-2">Hello from '/login-with-device'!</div>;
}
