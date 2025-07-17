import { QueryClient } from "@tanstack/react-query";

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes
      gcTime: 1000 * 60 * 30, // 30 minutes cache
      refetchOnWindowFocus: true,
      refetchOnReconnect: true,
      refetchOnMount: true,
      retry: (failureCount, error) => {
        // Don't retry auth errors
        if (error.message.includes("401") || error.message.includes("403")) {
          return false;
        }
        return failureCount < 3;
      },
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
      networkMode: "offlineFirst",
    },
    mutations: {
      retry: (failureCount, error) => {
        return failureCount < 2 && isNetworkError(error);
      },
      networkMode: "offlineFirst",
    },
  },
});

function isNetworkError(error: unknown): boolean {
  return (
    error instanceof Error &&
    (error.message.includes("network") ||
      error.message.includes("fetch") ||
      error.message.includes("timeout"))
  );
}
