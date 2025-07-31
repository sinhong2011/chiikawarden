import { Button } from "@heroui/button";
import { Switch } from "@heroui/switch";
import { useMutation } from "@tanstack/react-query";
import { createFileRoute, redirect, useNavigate, useSearch } from "@tanstack/react-router";
import { useEffect } from "react";
import { Controller } from "react-hook-form";
import { z } from "zod";
import { HeroForm } from "@/components/ui/form";
import { TextInput } from "@/components/ui/form/text-input";
import { FormErrorMessage } from "@/components/ui/form-error-message";
import { AnimatedSpinner } from "@/components/ui/icon/spinner";
import { useServerProviderQueries } from "@/hooks/queries/use-server-provider-queries";
import { useAuth } from "@/hooks/use-auth";
import { useAuthStore } from "@/stores/auth.store";

// Search parameters schema for account context
const unlockSearchSchema = z.object({
  accountId: z.string().optional(),
  email: z.string().optional(),
  providerId: z.string().optional(),
});

export const Route = createFileRoute("/_auth/unlock")({
  component: UnlockComponent,
  validateSearch: unlockSearchSchema,
  beforeLoad: ({ context, search }) => {
    console.log(
      `[UnlockRoute] beforeLoad - authStatus: ${context.authStore.authStatus}, isAuthenticated: ${context.authStore.isAuthenticated}, accountId: ${search.accountId}`
    );

    const { authStatus, isAuthenticated } = context.authStore;

    // Always allow access if account context is provided (from account selector)
    if (search.accountId) {
      console.log(`[UnlockRoute] Account context provided (${search.accountId}), allowing access`);
      return; // Allow access when account context is provided
    }

    // Allow access if user is in locked state (from automatic user detection or dev restoration)
    if (authStatus === "locked" || authStatus === "identified") {
      if (__DEV__) {
        console.log(
          `[UnlockRoute] User is ${authStatus} (possibly from dev hot reload), allowing access`
        );
      }
      return; // Allow access
    }

    // Allow access if user is authenticated but not unlocked (edge case)
    if (isAuthenticated && authStatus !== "unlocked") {
      console.log(
        `[UnlockRoute] User authenticated but not unlocked (${authStatus}), allowing access`
      );
      return; // Allow access
    }

    // Only redirect if user is already fully unlocked
    if (authStatus === "unlocked" && isAuthenticated) {
      console.log(`[UnlockRoute] User already unlocked, redirecting to vault`);
      throw redirect({ to: "/vault" });
    }

    // For logged-out users, redirect to login
    console.log(`[UnlockRoute] User logged out, redirecting to login`);
    throw redirect({ to: "/login" });
  },
});

const unlockFormSchema = z
  .object({
    password: z.string().optional(),
    useBiometric: z.boolean().default(false),
  })
  .refine(
    (data) => {
      // Either password must be provided or biometric must be enabled and selected
      return data.password || data.useBiometric;
    },
    {
      message: "Please enter your master password or use biometric unlock",
      path: ["password"], // Show error on password field
    }
  );

type UnlockFormData = z.infer<typeof unlockFormSchema>;

function UnlockComponent() {
  const navigate = useNavigate();
  const search = useSearch({ from: "/_auth/unlock" });
  const auth = useAuth();
  const { providerInfo } = useServerProviderQueries();
  const authStore = useAuthStore();

  // Get account context from search parameters
  const accountContext = {
    accountId: search.accountId,
    email: search.email || auth.email,
    providerId: search.providerId,
  };

  // Get provider information for display
  const accountProvider = providerInfo.data?.all_providers?.find(
    (p) => p.id === accountContext.providerId
  );

  // Create custom unlock mutation that handles account context
  const unlockMutation = useMutation({
    mutationFn: async (credentials: { biometric: boolean } | { password: string }) => {
      // If we have account context but no userId in auth store, set up user context first
      if (!authStore.userId && accountContext.accountId && accountContext.email) {
        console.log("Setting up user context for unlock", {
          accountId: accountContext.accountId,
          email: accountContext.email,
        });

        // Set up user context in auth store for unlock
        authStore.setupUserContextForUnlock(accountContext.accountId, accountContext.email);
      }

      // Convert credentials to the format expected by auth store
      let unlockCredentials: { password?: string; biometric?: boolean };

      if ("password" in credentials && credentials.password) {
        unlockCredentials = { password: credentials.password };
      } else if ("biometric" in credentials && credentials.biometric) {
        unlockCredentials = { biometric: true };
      } else {
        throw new Error("No valid unlock method provided");
      }

      // Use the auth store's unlock method
      const success = await authStore.unlock(unlockCredentials);
      if (!success) {
        throw new Error("Unlock failed. Please check your credentials and try again.");
      }

      return success;
    },
    onError: (error) => {
      console.error("Unlock failed:", error);
    },
  });

  // Redirect if already unlocked
  useEffect(() => {
    if (auth.isUnlocked) {
      navigate({ to: "/vault" });
    }
  }, [auth.isUnlocked, navigate]);

  // Handle unlock form submission
  const handleUnlock = async (values: UnlockFormData) => {
    try {
      let credentials: { biometric: boolean } | { password: string };

      if (values.useBiometric && auth.biometricEnabled) {
        credentials = { biometric: true };
      } else if (values.password) {
        credentials = { password: values.password };
      } else {
        // This should be handled by form validation, but adding as fallback
        return;
      }

      const success = await unlockMutation.mutateAsync(credentials);
      if (success) {
        navigate({ to: "/vault" });
      }
    } catch (error) {
      console.error("Unlock failed:", error);
      // Error handling is managed by the mutation state
    }
  };

  // Handle logout
  const handleLogout = async () => {
    await auth.logout();
    navigate({ to: "/login" });
  };

  return (
    <div className="flex flex-col h-full p-4 gap-5">
      <h1 className="text-2xl font-bold text-base-content w-full text-center">Chiikawarden</h1>

      <div className="flex-1 flex items-center justify-center">
        <div className="w-fit">
          <div className="mb-6 text-center">
            <h2 className="text-2xl font-semibold mb-2">Vault is Locked</h2>
            <p className="text-base-content/70 text-sm">
              Welcome back,{" "}
              <span className="font-medium text-base-content">{accountContext.email}</span>
            </p>
            {accountProvider && (
              <p className="text-base-content/60 text-xs mt-1">
                Server: <span className="font-medium">{accountProvider.label}</span>
                {accountProvider.urls.base && (
                  <span className="ml-1">({new URL(accountProvider.urls.base).hostname})</span>
                )}
              </p>
            )}
            <p className="text-base-content/70 text-sm mt-2">
              Enter your master password to unlock your vault
            </p>
          </div>

          <HeroForm
            schema={unlockFormSchema}
            defaultValues={{
              password: "",
              useBiometric: false,
            }}
            onSubmit={handleUnlock}
            className="space-y-4"
            validationBehavior="aria"
          >
            {(form) => (
              <>
                {/* Password field */}
                <Controller
                  name="password"
                  control={form.control}
                  render={({
                    field: { name, value, onChange, onBlur, ref },
                    fieldState: { error },
                  }) => (
                    <TextInput
                      ref={ref}
                      name={name}
                      type="password"
                      label="Master Password"
                      placeholder="Enter your master password"
                      value={value || ""}
                      onChange={onChange}
                      onBlur={onBlur}
                      error={error?.message}
                      size="lg"
                      validationBehavior="aria"
                    />
                  )}
                />

                {/* Biometric option */}
                {auth.biometricEnabled && (
                  <Controller
                    name="useBiometric"
                    control={form.control}
                    render={({ field: { name, value, onChange } }) => (
                      <Switch name={name} isSelected={value} onValueChange={onChange} size="md">
                        <div className="flex flex-col">
                          <span className="text-sm font-medium">Use biometric unlock</span>
                          <span className="text-xs text-base-content/70">
                            Unlock using your fingerprint or face recognition
                          </span>
                        </div>
                      </Switch>
                    )}
                  />
                )}

                {/* Error message */}
                <FormErrorMessage
                  error={
                    unlockMutation.isError
                      ? unlockMutation.error instanceof Error
                        ? unlockMutation.error.message
                        : "Unlock failed. Please try again."
                      : ""
                  }
                />

                {/* Submit button */}
                <Button
                  type="submit"
                  color="primary"
                  size="lg"
                  isDisabled={unlockMutation.isPending}
                  isLoading={unlockMutation.isPending}
                  className="w-full"
                  spinner={<AnimatedSpinner />}
                >
                  {unlockMutation.isPending ? "Unlocking..." : "Unlock Vault"}
                </Button>

                {/* Logout option */}
                <div className="text-center">
                  <button
                    type="button"
                    onClick={handleLogout}
                    className="text-base-content/70 hover:text-base-content text-sm font-medium transition-colors"
                  >
                    Not you? Sign out
                  </button>
                </div>
              </>
            )}
          </HeroForm>
        </div>
      </div>
    </div>
  );
}
