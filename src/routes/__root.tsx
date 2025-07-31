import "@/assets/styles/global.css";
import { QueryClientProvider } from "@tanstack/react-query";
import { createRootRouteWithContext, Outlet } from "@tanstack/react-router";
import { TanStackRouterDevtools } from "@tanstack/react-router-devtools";
import { ErrorBoundary } from "@/components/error-boundary";
import { queryClient } from "@/lib/query-client";
import type { RouterContext } from "@/lib/router";
import { HeroUIProviderWrapper } from "@/providers/heroui-provider";
import { I18nProvider } from "@/providers/i18n-provider";

export const Route = createRootRouteWithContext<RouterContext>()({
  component: RootComponent,
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
              {__DEV__ && <TanStackRouterDevtools position="top-right" />}
            </main>
          </ErrorBoundary>
        </HeroUIProviderWrapper>
      </I18nProvider>
    </QueryClientProvider>
  );
}
