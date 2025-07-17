import { Button } from "@heroui/button";
import React from "react";
import { ErrorBoundary as ReactErrorBoundary, useErrorBoundary } from "react-error-boundary";
import { ErrorDisplay } from "@/components/ui/error-display";
import { type AppError, parseError, reportError } from "@/lib/error-handling";
import { cn } from "@/lib/utils";

// Remove the old state interface as we'll use react-error-boundary

interface ErrorBoundaryProps {
  children: React.ReactNode;
  fallback?: React.ComponentType<ErrorBoundaryFallbackProps>;
  onError?: (error: Error, errorInfo: React.ErrorInfo) => void;
  resetKeys?: Array<string | number>;
  isolate?: boolean;
  className?: string;
}

interface ErrorBoundaryFallbackProps {
  error: AppError;
  resetError: () => void;
  hasError: boolean;
}

// Functional ErrorBoundary component that wraps react-error-boundary
function ErrorBoundary({
  children,
  fallback: FallbackComponent,
  onError,
  resetKeys,
  isolate,
  className,
}: ErrorBoundaryProps) {
  // Simplified reset logic - just use the provided resetKeys
  // The resetOnPropsChange functionality has been simplified to reduce complexity
  const combinedResetKeys = React.useMemo(() => {
    return resetKeys || [];
  }, [resetKeys]);

  // Enhanced error handler that parses errors and reports them
  const handleError = React.useCallback(
    (error: Error, errorInfo: React.ErrorInfo) => {
      // Log error to console in development
      if (import.meta.env.DEV) {
        console.error("Error Boundary caught an error:", error, errorInfo);
      }

      // Report error to external service or parent component
      onError?.(error, errorInfo);

      // Report to error tracking service
      reportError(error, {
        context: "ErrorBoundary",
        componentStack: errorInfo.componentStack || "",
        errorBoundary: true,
      });
    },
    [onError]
  );

  // Custom fallback render function that handles our AppError types and isolate prop
  const fallbackRender = React.useCallback(
    ({ error, resetErrorBoundary }: { error: Error; resetErrorBoundary: () => void }) => {
      const parsedError = parseError(error);

      if (FallbackComponent) {
        return (
          <FallbackComponent error={parsedError} resetError={resetErrorBoundary} hasError={true} />
        );
      }

      return (
        <ErrorBoundaryFallback
          error={parsedError}
          resetError={resetErrorBoundary}
          hasError={true}
          isolate={isolate}
          className={className}
        />
      );
    },
    [FallbackComponent, isolate, className]
  );

  return (
    <ReactErrorBoundary
      fallbackRender={fallbackRender}
      onError={handleError}
      resetKeys={combinedResetKeys}
    >
      {children}
    </ReactErrorBoundary>
  );
}

interface ErrorBoundaryFallbackComponentProps {
  error: AppError;
  resetError: () => void;
  hasError: boolean;
  isolate?: boolean;
  className?: string;
}

function ErrorBoundaryFallback({
  error,
  resetError,
  isolate,
  className,
}: ErrorBoundaryFallbackComponentProps) {
  const handleReload = () => {
    window.location.reload();
  };

  if (isolate) {
    return (
      <div className={cn("p-4 border-l-4 border-danger bg-danger/5", className)}>
        <ErrorDisplay error={error} onRetry={resetError} variant="compact" showDismiss={false} />
      </div>
    );
  }

  return (
    <div className={cn("min-h-screen flex items-center justify-center p-4", className)}>
      <div className="max-w-md w-full">
        <div className="text-center mb-6">
          <div className=" h-12 w-12 text-danger mb-4">
            <svg
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
              aria-label="Error icon"
            >
              <title>Error icon</title>
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"
              />
            </svg>
          </div>
          <h2 className="text-2xl font-bold text-base-content mb-2">Something went wrong</h2>
          <p className="text-base-content/70">An unexpected error occurred. Please try again.</p>
        </div>

        <ErrorDisplay
          error={error}
          onRetry={resetError}
          variant="default"
          showDismiss={false}
          className="mb-6"
        />

        <div className="flex gap-3 justify-center">
          <Button variant="bordered" onPress={resetError} className="flex-1">
            Try Again
          </Button>
          <Button variant="solid" onPress={handleReload} className="flex-1">
            Reload Page
          </Button>
        </div>

        {import.meta.env.DEV && (
          <details className="mt-6">
            <summary className="cursor-pointer text-sm text-base-content/70 hover:text-base-content">
              Developer Information
            </summary>
            <div className="mt-2 p-3 bg-base-200 rounded border text-xs font-mono">
              <div className="mb-2">
                <strong>Error Code:</strong> {error.code}
              </div>
              <div className="mb-2">
                <strong>Details:</strong> {error.details}
              </div>
              <div>
                <strong>Retry:</strong> {error.retryable ? "Yes" : "No"}
              </div>
            </div>
          </details>
        )}
      </div>
    </div>
  );
}

// Higher-order component for easier usage - updated to use new ErrorBoundary
export function withErrorBoundary<P extends object>(
  Component: React.ComponentType<P>,
  errorBoundaryProps?: Omit<ErrorBoundaryProps, "children">
) {
  const WrappedComponent = (props: P) => (
    <ErrorBoundary {...errorBoundaryProps}>
      <Component {...props} />
    </ErrorBoundary>
  );

  WrappedComponent.displayName = `withErrorBoundary(${Component.displayName || Component.name})`;

  return WrappedComponent;
}

// Async error boundary for handling async errors - now uses react-error-boundary's hook
export function useAsyncErrorBoundary() {
  const { showBoundary } = useErrorBoundary();
  return React.useCallback(
    (error: Error) => {
      showBoundary(error);
    },
    [showBoundary]
  );
}

// Hook for error boundary reset - enhanced to work with react-error-boundary
export function useErrorBoundaryReset() {
  const [resetKey, setResetKey] = React.useState(0);
  const { resetBoundary } = useErrorBoundary();

  const reset = React.useCallback(() => {
    setResetKey((prev) => prev + 1);
    resetBoundary();
  }, [resetBoundary]);

  return { resetKey, reset };
}

export { ErrorBoundary };
export type { ErrorBoundaryProps, ErrorBoundaryFallbackProps };
