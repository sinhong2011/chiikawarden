import React from "react";
import ReactDOM from "react-dom/client";
import { scan } from "react-scan";
import { ErrorBoundary } from "@/components/error-boundary";
import { initializeApp } from "@/lib/app-initialization";
import App from "@/App";

if (__DEV__) {
  scan({
    enabled: true,
  });
}

// Register the router instance for type safety

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
          <App />
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
