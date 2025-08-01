import { QueryClient } from "@tanstack/react-query";

const isNetworkError = (error: unknown): boolean => {
  if (error && typeof error === "object" && "message" in error) {
    const message = (error as { message: string }).message;
    return message.includes("network") || message.includes("fetch") || message.includes("timeout");
  }
  if (error && typeof error === "object" && "code" in error) {
    return (error as { code: string }).code === "NETWORK_ERROR";
  }
  return false;
};

const isRetryableError = (error: unknown): boolean => {
  const getErrorMessage = (err: unknown): string => {
    if (err && typeof err === "object" && "message" in err) {
      return (err as { message: string }).message;
    }
    return "";
  };

  const message = getErrorMessage(error);

  // Don't retry auth errors that couldn't be refreshed
  if (message.includes("401") || message.includes("403")) {
    return false;
  }

  // Retry network errors and server errors (5xx)
  return (
    isNetworkError(error) ||
    message.includes("500") ||
    message.includes("502") ||
    message.includes("503") ||
    message.includes("504")
  );
};

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes
      gcTime: 1000 * 60 * 30, // 30 minutes cache
      refetchOnWindowFocus: false, // Disable to reduce duplicate calls in development
      refetchOnReconnect: true,
      refetchOnMount: false, // Don't refetch on every mount to reduce duplicate calls
      retry: (failureCount, error) => {
        // For auth errors, we'll handle token refresh in the error boundary
        // For now, just retry once for auth errors to allow the refresh to work
        const message = getErrorMessage(error);
        if (message.includes("401") || message.includes("Authentication")) {
          return failureCount < 1; // Allow one retry for auth errors
        }

        // For other retryable errors, use standard retry logic
        if (isRetryableError(error) && failureCount < 3) {
          return true;
        }

        return false;
      },
      retryDelay: (attemptIndex) => {
        // Exponential backoff with jitter
        const baseDelay = 1000 * 2 ** attemptIndex;
        const jitter = Math.random() * 0.1 * baseDelay;
        return Math.min(baseDelay + jitter, 30000);
      },
      networkMode: "offlineFirst",
    },
    mutations: {
      retry: (failureCount, error) => {
        // Similar logic for mutations but with fewer retries
        const message = getErrorMessage(error);
        if (message.includes("401") || message.includes("Authentication")) {
          return failureCount < 1;
        }

        // Retry network errors with limited attempts
        return failureCount < 2 && isRetryableError(error);
      },
      retryDelay: (attemptIndex) => {
        // Shorter delays for mutations
        const baseDelay = 500 * 2 ** attemptIndex;
        const jitter = Math.random() * 0.1 * baseDelay;
        return Math.min(baseDelay + jitter, 10000);
      },
      networkMode: "offlineFirst",
    },
  },
});

// Helper function to get error message (used in retry logic)
const getErrorMessage = (err: unknown): string => {
  if (err && typeof err === "object" && "message" in err) {
    return (err as { message: string }).message;
  }
  return "";
};
