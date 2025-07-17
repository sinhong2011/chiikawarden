import "@/assets/styles/global.css";
import { QueryClientProvider } from "@tanstack/react-query";
import { createRootRoute, Outlet } from "@tanstack/react-router";
import { TanStackRouterDevtools } from "@tanstack/react-router-devtools";
import { ErrorBoundary } from "@/components/error-boundary";
import { queryClient } from "@/lib/query-client";
import { HeroUIProviderWrapper } from "@/providers/heroui-provider";
import { I18nProvider } from "@/providers/i18n-provider";
import { useAuthStore } from "@/stores/auth.store";

export const Route = createRootRoute({
  component: RootComponent,
  context: () => ({
    queryClient,
    auth: useAuthStore.getState(),
  }),
});

function RootComponent() {
  return (
    <QueryClientProvider client={queryClient}>
      <I18nProvider>
        <HeroUIProviderWrapper>
          <ErrorBoundary
            onError={(error, errorInfo) => {
              console.error("Route-level error boundary caught:", error, errorInfo);
            }}
          >
            <main className="h-full">
              <Outlet />
              {__DEV__ && <TanStackRouterDevtools />}
            </main>
          </ErrorBoundary>
        </HeroUIProviderWrapper>
      </I18nProvider>
    </QueryClientProvider>
  );
}
