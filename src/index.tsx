import type { QueryClient } from "@tanstack/react-query";
import { createRouter, RouterProvider } from "@tanstack/react-router";
import React from "react";
import ReactDOM from "react-dom/client";
import { scan } from "react-scan";
import { ErrorBoundary } from "@/components/error-boundary";
import { initializeApp } from "@/lib/app-initialization";
import type { AuthState } from "@/types/auth.types";
// Import the generated route tree
import { routeTree } from "./routeTree.gen";

if (__DEV__) {
  scan({
    enabled: true,
  });
}

// Create the router with proper context
const router = createRouter({
  routeTree,
  context: {
    queryClient: undefined as unknown as QueryClient,
    auth: undefined as unknown as AuthState,
  },
});

// Register the router instance for type safety
declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}

// Initialize app systems before rendering
initializeApp()
  .then(() => {
    const root = ReactDOM.createRoot(document.getElementById("root") as HTMLElement);

    root.render(
      <React.StrictMode>
        <ErrorBoundary
          onError={(error, errorInfo) => {
            console.error("Global error boundary caught:", error, errorInfo);
          }}
        >
          <RouterProvider router={router} />
        </ErrorBoundary>
      </React.StrictMode>
    );
  })
  .catch((error) => {
    console.error("Failed to initialize app:", error);
    // Render a basic error message if initialization fails
    const root = ReactDOM.createRoot(document.getElementById("root") as HTMLElement);
    root.render(
      <div style={{ padding: "20px", textAlign: "center" }}>
        <h1>Application Initialization Failed</h1>
        <p>Please refresh the page to try again.</p>
        <details>
          <summary>Error Details</summary>
          <pre>{error.toString()}</pre>
        </details>
      </div>
    );
  });
