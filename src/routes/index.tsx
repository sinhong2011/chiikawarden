import { createFileRoute } from "@tanstack/react-router";
import { createAuthGuard } from "@/lib/router-guards";

export const Route = createFileRoute("/")({
  component: LandingComponent,
  ...createAuthGuard(),
});

function LandingComponent() {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="text-center">
        <h1 className="text-2xl font-bold mb-4">ChiikaWarden</h1>
        <p className="text-gray-600">Initializing secure vault...</p>
      </div>
    </div>
  );
}
