import { RouterContextProvider } from "@/providers/router-context-provider";

/**
 * Main App Component
 *
 * Uses the RouterContextProvider to provide reactive context to TanStack Router.
 * The provider handles all store subscriptions and context management automatically.
 */
function App() {
  return <RouterContextProvider />;
}

export default App;
