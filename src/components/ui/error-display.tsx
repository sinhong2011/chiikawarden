import { Button } from "@heroui/button";
import React from "react";
import { type AppError, getUserMessage, isRetryable, parseError } from "@/lib/error-handling";
import { i18n } from "@/lib/i18n";
import { cn } from "@/lib/utils";

export interface ErrorDisplayProps {
  error: AppError | string | null;
  onRetry?: () => void;
  onDismiss?: () => void;
  variant?: "default" | "compact" | "inline";
  showRetry?: boolean;
  showDismiss?: boolean;
  className?: string;
}

export function ErrorDisplay(props: ErrorDisplayProps) {
  const {
    error: errorProp,
    onRetry,
    onDismiss,
    variant = "default",
    showRetry = true,
    showDismiss = true,
    className,
    ...others
  } = props;

  // Parse error if it's a string
  const parsedError = React.useMemo(() => {
    if (!errorProp) return null;
    if (typeof errorProp === "string") {
      return parseError(errorProp);
    }
    return errorProp;
  }, [errorProp]);

  if (!parsedError) return null;

  const isRetryableError = isRetryable(parsedError);
  const userMessage = getUserMessage(parsedError);

  const getVariantClasses = () => {
    const baseClasses = "rounded-lg border";

    switch (variant) {
      case "compact":
        return cn(baseClasses, "p-3 bg-danger/10 border-danger/20");
      case "inline":
        return cn(baseClasses, "p-2 bg-danger/5 border-danger/10");
      default:
        return cn(baseClasses, "p-4 bg-danger/10 border-danger/20");
    }
  };

  const getTextClasses = () => {
    switch (variant) {
      case "compact":
        return "text-sm";
      case "inline":
        return "text-xs";
      default:
        return "text-sm";
    }
  };

  return (
    <div {...others} className={cn(getVariantClasses(), className)}>
      <div className="flex items-start gap-3">
        {/* Error icon */}
        <div className="flex-shrink-0 mt-0.5">
          <svg
            className="h-5 w-5 text-danger"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fillRule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
              clipRule="evenodd"
            />
          </svg>
        </div>

        {/* Error content */}
        <div className="flex-1 min-w-0">
          <div className={cn("text-danger font-medium", getTextClasses())}>{userMessage}</div>

          {/* Error details in development */}
          {import.meta.env.DEV && parsedError.details && parsedError.details !== userMessage && (
            <details className="mt-2">
              <summary className="cursor-pointer text-xs text-danger/70 hover:text-danger">
                Technical Details
              </summary>
              <div className="mt-1 text-xs text-danger/60 font-mono bg-danger/5 p-2 rounded border">
                <div>
                  <strong>Code:</strong> {parsedError.code}
                </div>
                <div>
                  <strong>Details:</strong> {parsedError.details}
                </div>
              </div>
            </details>
          )}
        </div>

        {/* Action buttons */}
        <div className="flex-shrink-0 flex items-center gap-2">
          {showRetry !== false && isRetryableError && onRetry && (
            <Button
              variant="bordered"
              size="sm"
              onPress={onRetry}
              className="text-danger border-danger/30 hover:bg-danger/10"
            >
              Retry
            </Button>
          )}

          {showDismiss !== false && onDismiss && (
            <Button
              onPress={onDismiss}
              className="text-danger/70 hover:text-danger transition-colors"
              aria-label="Dismiss error"
            >
              <svg className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
              </svg>
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}

// Compact error display for inline use
export function InlineError(props: Omit<ErrorDisplayProps, "variant">) {
  return <ErrorDisplay {...props} variant="inline" showDismiss={false} />;
}

// Toast-style error notification
export interface ErrorToastProps extends Omit<ErrorDisplayProps, "variant"> {
  duration?: number;
  onAutoClose?: () => void;
}

export function ErrorToast(props: ErrorToastProps) {
  const { duration, onAutoClose, ...others } = props;

  // Auto-close after duration
  React.useEffect(() => {
    if (duration && onAutoClose) {
      const timer = setTimeout(() => {
        onAutoClose();
      }, duration);

      return () => clearTimeout(timer);
    }
  }, [duration, onAutoClose]);

  return (
    <div className="fixed top-4 right-4 z-50">
      <ErrorDisplay
        {...others}
        variant="default"
        className="shadow-lg border-danger/30 bg-danger/15 backdrop-blur-sm"
      />
    </div>
  );
}

// Loading state component for async operations
export interface LoadingStateProps {
  isLoading: boolean;
  error?: AppError | string | null;
  onRetry?: () => void;
  loadingText?: string;
  children?: React.ReactNode;
  className?: string;
}

export function LoadingState(props: LoadingStateProps) {
  if (props.isLoading) {
    return (
      <div className={cn("flex items-center justify-center p-4", props.className)}>
        <div className="flex items-center gap-2">
          <div className="animate-spin h-4 w-4 border-2 border-primary border-t-transparent rounded-full"></div>
          <span className="text-base-content/70 text-sm">
            {props.loadingText || i18n._("common.loading")}
          </span>
        </div>
      </div>
    );
  }

  if (props.error) {
    return <ErrorDisplay error={props.error} onRetry={props.onRetry} className={props.className} />;
  }

  return <>{props.children}</>;
}

// Hook for managing error state
export function useErrorState() {
  const [error, setError] = React.useState<AppError | null>(null);
  const [isLoading, setIsLoading] = React.useState(false);

  const handleError = React.useCallback((err: unknown) => {
    const parsedError = parseError(err);
    setError(parsedError);
    setIsLoading(false);
  }, []);

  const clearError = React.useCallback(() => {
    setError(null);
  }, []);

  const withErrorHandling = React.useCallback(
    async <T,>(operation: () => Promise<T>): Promise<T | null> => {
      try {
        setIsLoading(true);
        clearError();
        const result = await operation();
        setIsLoading(false);
        return result;
      } catch (err) {
        handleError(err);
        return null;
      }
    },
    [clearError, handleError]
  );

  return {
    error,
    isLoading,
    handleError,
    clearError,
    withErrorHandling,
    setIsLoading,
  };
}

// Re-export for convenience
export {
  type AppError,
  getUserMessage,
  isRetryable,
  parseError,
  reportError,
  withRetry,
} from "@/lib/error-handling";
