# Chiikawarden: Project Structure and Routing Guide

This document provides a comprehensive overview of the Chiikawarden project structure and the TanStack Router file-based routing architecture.

## 📁 Project Structure

> **TanStack Router Best Practices**: File-based routing with type-safe navigation and nested layouts

```
chiikawarden/
├── src/                           # 🎯 Frontend SolidJS Application
│   ├── components/               # 🧩 Reusable UI Components
│   │   ├── auth/                 # Authentication UI components
│   │   ├── vault/                # Vault management components
│   │   ├── send/                 # Send feature components
│   │   ├── ui/                   # Design system primitives
│   │   └── layout/               # Layout components
│   ├── hooks/                    # 🎣 Custom SolidJS Hooks
│   │   ├── useAuth.ts
│   │   ├── useVault.ts
│   │   └── ...
│   ├── lib/                      # 📚 Core Libraries & Setup
│   │   ├── router.tsx            # TanStack Router configuration
│   │   ├── query-client.ts       # TanStack Query setup
│   │   └── ...
│   ├── routes/                    # 🗂️ TanStack Router File-Based Routing
│   │   ├── __root.tsx            # Root layout with context providers
│   │   ├── index.tsx             # Landing/redirect page (/)
│   │   ├── login.tsx             # Authentication (/login)
│   │   ├── signup.tsx            # Account creation (/signup)
│   │   ├── finish-signup.tsx     # Account completion (/finish-signup)
│   │   ├── unlock.tsx            # Vault unlock (/unlock)
│   │   ├── 2fa.tsx               # Two-factor auth (/2fa)
│   │   ├── sso.tsx               # SSO authentication (/sso)
│   │   ├── login-with-device.tsx # Device login (/login-with-device)
│   │   ├── login-initiated.tsx   # Login initiated (/login-initiated)
│   │   ├── device-verification.tsx # Device trust (/device-verification)
│   │   ├── set-password.tsx      # Password setup (/set-password)
│   │   ├── set-password-jit.tsx  # JIT password setup (/set-password-jit)
│   │   ├── update-temp-password.tsx # Temp password update (/update-temp-password)
│   │   ├── authentication-timeout.tsx # Auth timeout (/authentication-timeout)
│   │   ├── vault/                # 🔒 Protected Vault Routes
│   │   │   ├── __layout.tsx      # Vault layout wrapper with sidebar
│   │   │   ├── index.tsx         # Main vault view (/vault)
│   │   │   ├── add.tsx           # Add item (/vault/add)
│   │   │   ├── add.$type.tsx     # Add specific type (/vault/add/login)
│   │   │   ├── edit.$id.tsx      # Edit item (/vault/edit/[id])
│   │   │   ├── view.$id.tsx      # View item (/vault/view/[id])
│   │   │   ├── clone.$id.tsx     # Clone item (/vault/clone/[id])
│   │   │   ├── search.tsx        # Search results (/vault/search)
│   │   │   ├── favorites.tsx     # Favorites view (/vault/favorites)
│   │   │   ├── trash.tsx         # Deleted items (/vault/trash)
│   │   │   ├── generator.tsx     # Password generator (/vault/generator)
│   │   │   └── folder/           # Folder management
│   │   │       ├── add.tsx       # Add folder (/vault/folder/add)
│   │   │       └── edit.$id.tsx  # Edit folder (/vault/folder/edit/[id])
│   │   ├── send/                 # 📤 Bitwarden Send Routes
│   │   │   ├── index.tsx         # Send dashboard (/send)
│   │   │   ├── add.tsx           # Create send (/send/add)
│   │   │   ├── edit.$id.tsx      # Edit send (/send/edit/[id])
│   │   │   └── view.$id.tsx      # View send (/send/view/[id])
│   │   ├── settings/             # ⚙️ Settings Routes
│   │   │   ├── __layout.tsx      # Settings layout with navigation
│   │   │   ├── index.tsx         # General settings (/settings)
│   │   │   ├── security.tsx      # Security settings (/settings/security)
│   │   │   ├── vault.tsx         # Vault preferences (/settings/vault)
│   │   │   ├── account.tsx       # Account settings (/settings/account)
│   │   │   ├── organizations.tsx # Organization management (/settings/organizations)
│   │   │   └── about.tsx         # About/version info (/settings/about)
│   │   ├── fido2.tsx             # FIDO2 authentication (/fido2)
│   │   ├── accessibility-cookie.tsx # Accessibility settings
│   │   └── 404.tsx               # 404 error page
│   ├── services/                 # 🔧 Business Logic Services
│   │   ├── auth.service.ts
│   │   ├── vault.service.ts
│   │   └── ...
│   ├── stores/                   # 📦 Global State Management
│   │   ├── auth.store.ts
│   │   ├── vault.store.ts
│   │   └── ...
│   ├── types/                    # 📝 TypeScript Definitions
│   │   ├── auth.types.ts
│   │   ├── vault.types.ts
│   │   └── ...
│   └── utils/                    # 🛠️ Utility Functions
│       ├── crypto.utils.ts
│       ├── validation.utils.ts
│       └── ...
├── src-tauri/                    # 🦀 Rust Backend
│   ├── src/
│   │   ├── main.rs               # Application entry point
│   │   ├── lib.rs                # Library configuration
│   │   ├── commands/             # Tauri command handlers
│   │   ├── services/             # Backend business logic
│   │   ├── models/               # Data models
│   │   ├── storage/              # Storage implementations
│   │   ├── crypto/               # Cryptographic operations
│   │   ├── api/                  # External API client
│   │   ├── errors.rs             # Error definitions
│   │   └── ...
│   ├── migrations/               # Database schema migrations
│   ├── build.rs                  # Build script
│   ├── Cargo.toml               # Rust dependencies
│   └── tauri.conf.json          # Tauri configuration
├── docs/                         # 📖 Documentation
├── tests/                        # 🧪 Testing Suite
├── messages/                     # 🌍 Internationalization
└── public/                       # 📁 Static Assets
```

## 🗺️ Routing Architecture

Chiikawarden leverages **TanStack Router's file-based routing system** for maximum type safety, performance, and developer experience.

### Key Benefits

- **🛡️ Type-Safe Navigation**: Compile-time route validation and auto-completion.
- **⚡ Automatic Code Splitting**: Each route becomes a separate chunk, improving load times.
- **📦 Data Loaders**: Pre-load data before a route renders for a smoother user experience.
- **🔍 Search Param Validation**: Type-safe validation and parsing of URL search parameters.
- **🎨 Nested Layouts**: Efficiently compose layouts and share UI across routes.
- **🔄 Intelligent Preloading**: Preload routes based on user intent (e.g., hovering over a link).

### Router Configuration

The main router instance is configured in `src/lib/router.tsx`, where the generated `routeTree` is imported and the global context (like `queryClient` and `auth` state) is provided.

```typescript
// src/lib/router.tsx
import { Router } from '@tanstack/react-router';
import { routeTree } from '../routeTree.gen';
import { QueryClient } from '@tanstack/react-query';
import { authState } from '@/stores/auth.store';

export const router = new Router({
  routeTree,
  defaultPreload: 'intent',
  context: {
    queryClient: undefined as unknown as QueryClient,
    auth: undefined as unknown as typeof authState,
  },
  // ...
});
```

The root layout, defined in `src/routes/__root.tsx`, wraps the entire application. It's the ideal place for context providers like `QueryClientProvider` and `ErrorBoundary`.

```typescript
// src/routes/__root.tsx
import { createRootRoute, Outlet } from '@tanstack/solid-router';
import { QueryClientProvider } from '@tanstack/solid-query';
// ...

export const Route = createRootRoute({
  component: RootComponent,
  context: () => ({
    queryClient: new QueryClient(),
    auth: authState,
  }),
});

function RootComponent() {
  return (
    <QueryClientProvider client={Route.useRouteContext().queryClient}>
      <ErrorBoundary>
        <Outlet />
      </ErrorBoundary>
    </QueryClientProvider>
  );
}
```

### Route Protection & Guards

Route protection is handled using the `beforeLoad` option in route definitions. This function is executed before a route is loaded, allowing for authentication checks and redirects.

A common pattern is to create a reusable guard hook, like `useVaultGuard`, to protect entire sections of the application.

```typescript
// src/routes/vault/__layout.tsx - Protected Layout
export const Route = createFileRoute('/vault')({
  beforeLoad: async ({ context }) => {
    // This guard protects all nested routes under /vault
    if (!context.auth.isAuthenticated) {
      throw redirect({ to: '/login' });
    }
    if (context.auth.authStatus === 'locked') {
      throw redirect({ to: '/unlock' });
    }
  },
  component: VaultLayout,
})
```

### Type-Safe Navigation Example

A typed navigation hook can be created to provide easy, type-safe navigation functions throughout the app, preventing common errors with route paths or parameters.

```typescript
// src/lib/navigation.ts
import { useRouter } from '@tanstack/solid-router';

export const useTypedNavigation = () => {
  const router = useRouter();

  return {
    // ✅ Type-safe with auto-completion
    toEditCipher: (id: string) => {
      router.navigate({ to: '/vault/edit/$id', params: { id } });
    },
    toVaultSearch: (search?: { query?: string; type?: 'login' | 'card' }) => {
      router.navigate({ to: '/vault/search', search });
    },
    // ❌ The following would cause a TypeScript error
    // toEditCipher: (id: number) => { ... } // param `id` must be a string
    // navigate({ to: '/invalid-route' }) // route does not exist
  };
};
``` 