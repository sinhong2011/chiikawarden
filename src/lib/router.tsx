import type { QueryClient } from "@tanstack/react-query";
import { Router } from "@tanstack/react-router";
import { routeTree } from "@/routeTree.gen";
import type { AuthState } from "@/types/auth.types";

// This is a placeholder and will not work until the route tree is generated.
// @ts-ignore
export const router = new Router({
  routeTree,
  defaultPreload: "intent",
  context: {
    queryClient: undefined as unknown as QueryClient,
    auth: undefined as unknown as AuthState,
  },
});

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
