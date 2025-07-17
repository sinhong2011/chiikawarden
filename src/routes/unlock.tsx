import { Button } from "@heroui/button";
import { Switch } from "@heroui/switch";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { z } from "zod";
import { HeroForm, TextInput } from "@/components/ui/form";
import { useAuth } from "@/hooks/use-auth";

export const Route = createFileRoute("/unlock")({
  component: UnlockComponent,
  beforeLoad: ({ context }) => {
    // Redirect if not in locked state
    if (context.auth.authStatus !== "locked") {
      if (context.auth.authStatus === "unlocked" && context.auth.isAuthenticated) {
        throw new Error("Already unlocked, redirecting to vault");
      } else {
        throw new Error("Not logged in, redirecting to login");
      }
    }
  },
});

const unlockFormSchema = z.object({
  password: z.string().optional(),
  useBiometric: z.boolean(),
});

type UnlockFormData = z.infer<typeof unlockFormSchema>;

function UnlockComponent() {
  const navigate = useNavigate();
  const auth = useAuth();
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  // State for biometric switch
  const [useBiometric, setUseBiometric] = useState(false);

  // Redirect if already unlocked
  useEffect(() => {
    if (auth.isUnlocked) {
      navigate({ to: "/vault" });
    }
  }, [auth.isUnlocked, navigate]);

  // Handle unlock form submission
  const handleUnlock = async (values: UnlockFormData) => {
    setError("");
    setIsLoading(true);

    try {
      let success = false;

      if (useBiometric && auth.biometricEnabled) {
        success = await auth.unlock({ biometric: true });
      } else if (values.password) {
        success = await auth.unlock({ password: values.password });
      } else {
        setError("Please enter your master password or use biometric unlock");
        setIsLoading(false);
        return;
      }

      if (success) {
        navigate({ to: "/vault" });
      } else {
        setError("Invalid password. Please try again.");
      }
    } catch (err) {
      console.error("Unlock error:", err);
      setError(err instanceof Error ? err.message : "Unlock failed. Please try again.");
    } finally {
      setIsLoading(false);
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
        <div className="w-full ">
          <div className="mb-6 text-center">
            <h2 className="text-2xl font-semibold mb-2">Vault is Locked</h2>
            <p className="text-base-content/70 text-sm">
              Welcome back, <span className="font-medium text-base-content">{auth.email}</span>
            </p>
            <p className="text-base-content/70 text-sm">
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
          >
            <div className="space-y-4">
              {/* Password field */}
              <TextInput
                name="password"
                type="password"
                label="Master Password"
                placeholder="Enter your master password"
                required={!auth.biometricEnabled && !useBiometric}
                size="lg"
                validate={(value) => {
                  if (!value && !useBiometric && !auth.biometricEnabled) {
                    return "Master password is required";
                  }
                  return undefined;
                }}
              />

              {/* Biometric option */}
              {auth.biometricEnabled && (
                <Switch isSelected={useBiometric} onValueChange={setUseBiometric} size="md">
                  <div className="flex flex-col">
                    <span className="text-sm font-medium">Use biometric unlock</span>
                    <span className="text-xs text-base-content/70">
                      Unlock using your fingerprint or face recognition
                    </span>
                  </div>
                </Switch>
              )}

              {/* Error message */}
              {error && (
                <div className="p-3 bg-error/10 border border-error/20 rounded-lg">
                  <div className="text-error text-sm font-medium">{error}</div>
                </div>
              )}

              {/* Submit button */}
              <Button
                type="submit"
                color="primary"
                size="lg"
                isDisabled={isLoading}
                isLoading={isLoading}
                className="w-full"
              >
                {isLoading ? "Unlocking..." : "Unlock Vault"}
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
            </div>
          </HeroForm>
        </div>
      </div>
    </div>
  );
}
