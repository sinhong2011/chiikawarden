# TanStack Query + Tauri Integration Guide

## Overview

This guide covers best practices for integrating TanStack Query with Tauri's invoke functionality in your authentication service and beyond.

## Current vs Recommended Architecture

### Current Direct Promise Approach
```typescript
// src/services/auth.service.ts - Current
export const authService = {
  async prelogin(email: string): Promise<PreloginResponse> {
    try {
      const request: PreloginRequest = { email };
      const response = await invoke<PreloginResponse>("prelogin", { request });
      return response;
    } catch (error) {
      throw new Error(`Prelogin failed: ${error}`);
    }
  }
};

// Component usage - Current
const handlePrelogin = async (email: string) => {
  setLoading(true);
  try {
    const response = await authService.prelogin(email);
    // Handle success
  } catch (error) {
    // Handle error
  } finally {
    setLoading(false);
  }
};
```

### Recommended TanStack Query Approach
```typescript
// src/hooks/useAuthQueries.ts - Recommended
export const useAuthQueries = () => {
  const preloginQuery = (email: string) =>
    createQuery(() => ({
      queryKey: queryKeys.prelogin(email),
      queryFn: async () => {
        if (!email || !email.includes("@")) {
          throw new Error("Valid email is required for prelogin");
        }
        return await authService.prelogin(email);
      },
      enabled: !!email && email.includes("@"),
      staleTime: 1000 * 60 * 5, // 5 minutes
      retry: (failureCount, error) => {
        if (error.message.includes("Valid email is required")) {
          return false;
        }
        return failureCount < 2;
      },
    }));
    
  return { prelogin: preloginQuery };
};

// Component usage - Recommended
const { prelogin } = useAuthQueries();
const preloginQuery = prelogin(email());

// Automatic loading states, error handling, and caching!
```

## Benefits for Tauri Desktop Applications

### 1. **Caching & Performance**
- Reduces redundant Tauri invoke calls
- Intelligent background updates
- Offline-first capabilities

### 2. **Error Handling**
- Centralized retry logic
- Automatic error recovery
- Network-aware error handling

### 3. **Loading States**
- Built-in loading/pending states
- No manual state management needed
- Consistent UI patterns

### 4. **Developer Experience**
- Declarative data fetching
- DevTools integration
- Type-safe queries

## Implementation Patterns

### Pattern 1: Query for Data Fetching
Use queries for operations that fetch data:

```typescript
// ✅ Good for: prelogin, getUserProfile, getSettings
const preloginQuery = createQuery(() => ({
  queryKey: ["auth", "prelogin", email()],
  queryFn: () => authService.prelogin(email()),
  enabled: !!email(),
  staleTime: 1000 * 60 * 5,
}));
```

### Pattern 2: Mutations for Actions
Use mutations for operations that change state:

```typescript
// ✅ Good for: login, logout, updateProfile, changePassword
const loginMutation = createMutation(() => ({
  mutationFn: (credentials: LoginCredentials) => authService.login(credentials),
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ["auth"] });
    navigate("/vault");
  },
}));
```

### Pattern 3: Dependent Queries
Chain queries that depend on each other:

```typescript
// First get user ID, then fetch profile
const userQuery = createQuery(() => ({
  queryKey: ["auth", "user"],
  queryFn: () => authService.getCurrentUser(),
}));

const profileQuery = createQuery(() => ({
  queryKey: ["user", "profile", userQuery.data?.id],
  queryFn: () => authService.getUserProfile(userQuery.data!.id),
  enabled: !!userQuery.data?.id, // Only run when we have user ID
}));
```

## Migration Strategy

### Step 1: Keep Existing Services
Don't remove your existing service layer - TanStack Query will use it:

```typescript
// Keep this - TanStack Query will call it
export const authService = {
  async prelogin(email: string): Promise<PreloginResponse> {
    const request: PreloginRequest = { email };
    const response = await invoke<PreloginResponse>("prelogin", { request });
    return response;
  }
};
```

### Step 2: Create Query Hooks
Add TanStack Query hooks that wrap your services:

```typescript
// New - Add this
export const useAuthQueries = () => {
  const preloginQuery = (email: string) =>
    createQuery(() => ({
      queryKey: queryKeys.prelogin(email),
      queryFn: () => authService.prelogin(email), // Uses existing service
      enabled: !!email && email.includes("@"),
      staleTime: 1000 * 60 * 5,
    }));
    
  return { prelogin: preloginQuery };
};
```

### Step 3: Update Components Gradually
Migrate components one by one:

```typescript
// Before
const [loading, setLoading] = createSignal(false);
const [error, setError] = createSignal("");
const [data, setData] = createSignal(null);

const handlePrelogin = async (email: string) => {
  setLoading(true);
  try {
    const response = await authService.prelogin(email);
    setData(response);
  } catch (err) {
    setError(err.message);
  } finally {
    setLoading(false);
  }
};

// After
const { prelogin } = useAuthQueries();
const preloginQuery = prelogin(email());

// preloginQuery.isLoading, preloginQuery.error, preloginQuery.data
// All handled automatically!
```

## Configuration for Tauri

Your existing query client configuration is already well-suited for Tauri:

```typescript
// src/lib/query-client.ts - Already configured well!
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // Good for desktop apps
      gcTime: 1000 * 60 * 30, // Reasonable cache time
      refetchOnWindowFocus: true, // Good for desktop
      refetchOnReconnect: true, // Handle network changes
      networkMode: "offlineFirst", // Perfect for desktop
      retry: (failureCount, error) => {
        // Don't retry auth errors - Good!
        if (error.message.includes("401") || error.message.includes("403")) {
          return false;
        }
        return failureCount < 3;
      },
    },
  },
});
```

## Trade-offs Analysis

### TanStack Query Approach
**Pros:**
- ✅ Automatic caching and background updates
- ✅ Built-in loading/error states
- ✅ Consistent patterns across app
- ✅ Offline support
- ✅ DevTools integration
- ✅ Optimistic updates
- ✅ Automatic retries

**Cons:**
- ❌ Additional learning curve
- ❌ More abstraction layers
- ❌ Slightly larger bundle size

### Direct Promise Approach
**Pros:**
- ✅ Simple and direct
- ✅ Less abstraction
- ✅ Smaller bundle size

**Cons:**
- ❌ Manual state management
- ❌ No caching benefits
- ❌ Repetitive error handling
- ❌ Inconsistent with rest of app
- ❌ No offline support

## Recommendation

**Use TanStack Query for your authentication service** because:

1. **Consistency**: Your app already uses TanStack Query extensively
2. **Desktop Benefits**: Caching reduces Tauri invoke overhead
3. **User Experience**: Better loading states and error handling
4. **Maintainability**: Consistent patterns across the codebase
5. **Future-Proof**: Easier to add features like offline support

The benefits significantly outweigh the minimal additional complexity, especially in a desktop application where caching and offline support are valuable.

## Specific Implementation: Prelogin Example

Here's how to refactor your current prelogin implementation:

### Current Implementation
```typescript
// src/routes/_auth/login/-components/Prelogin.tsx - Current
const handlePrelogin: SubmitHandler<PreloginFormData> = async (values) => {
  setError("");
  setIsLoading(true);

  try {
    const response = await authService.prelogin(values.email);
    console.log("KDF Settings retrieved:", response);
    props.onFinish(values.email, response);
  } catch (err) {
    setError(err instanceof Error ? err.message : "Failed to retrieve login settings");
  } finally {
    setIsLoading(false);
  }
};
```

### Recommended Implementation
```typescript
// src/routes/_auth/login/-components/PreloginWithQuery.tsx - Recommended
const PreloginFormWithQuery = (props: PreloginFormProps) => {
  const [email, setEmail] = createSignal("");
  const { prelogin } = useAuthQueries();

  const preloginQuery = prelogin(email());

  createEffect(() => {
    if (preloginQuery.isSuccess && preloginQuery.data) {
      props.onFinish(email(), preloginQuery.data);
    }
  });

  const handlePrelogin: SubmitHandler<PreloginFormData> = async (values) => {
    setEmail(values.email); // This triggers the query automatically
  };

  const isLoading = () => preloginQuery.isFetching;
  const errorMessage = () => preloginQuery.error?.message || "";

  // Rest of component uses isLoading() and errorMessage()
};
```

### Benefits of This Approach
1. **Automatic Caching**: Same email won't trigger duplicate requests
2. **Background Updates**: KDF settings refresh automatically if stale
3. **Error Recovery**: Automatic retries on network failures
4. **Loading States**: Built-in loading management
5. **DevTools**: Query inspection in browser DevTools

## Next Steps

1. **Start with Prelogin**: Implement the TanStack Query version alongside your current implementation
2. **Test Both Approaches**: Compare the developer experience and user experience
3. **Gradual Migration**: Once satisfied, migrate other auth operations
4. **Remove Old Code**: Clean up direct promise calls after migration

The example files created show exactly how to implement this pattern in your existing codebase.
