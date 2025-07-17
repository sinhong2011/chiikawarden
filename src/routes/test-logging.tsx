import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/test-logging")({
  component: TestLoggingComponent,
});

function TestLoggingComponent() {
  return (
    <div className="p-6">
      <h1 className="text-2xl font-bold mb-4">Logging Test</h1>
      <p className="text-base-content/70">This is a test page for logging functionality.</p>
    </div>
  );
}
