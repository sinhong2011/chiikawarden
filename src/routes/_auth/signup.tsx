import { Button } from "@heroui/button";
import { useLingui } from "@lingui/react/macro";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { z } from "zod";
import { HeroForm, TextInput } from "@/components/ui/form";
import { useAuthQueries } from "@/hooks/queries/use-auth-queries";
import { useAuth } from "@/hooks/use-auth";

// Form schema - will be created inside component to access t function
const createSignupFormSchema = (t: any) =>
  z
    .object({
      email: z.string().email(t`validation.email_invalid`),
      password: z.string().min(8, t`validation.password_min_length`),
      confirmPassword: z.string().min(1, t`validation.confirm_password_required`),
    })
    .refine((data) => data.password === data.confirmPassword, {
      message: t`validation.passwords_do_not_match`,
      path: ["confirmPassword"],
    });

export const Route = createFileRoute("/_auth/signup")({
  component: SignupComponent,
});

function SignupComponent() {
  const { t } = useLingui();
  const navigate = useNavigate();
  const auth = useAuth();
  const authQueries = useAuthQueries();

  const [error, setError] = useState("");

  // Create schema with i18n support
  const signupFormSchema = createSignupFormSchema(t);
  type SignupForm = z.infer<typeof signupFormSchema>;

  // Track submission state
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Redirect if already authenticated
  useEffect(() => {
    if (auth.isUnlocked) {
      navigate({ to: "/vault" });
    }
  }, [auth.isUnlocked, navigate]);

  // Signup form handler
  const handleSignup = async (values: SignupForm) => {
    setError("");
    setIsSubmitting(true);
    try {
      await authQueries.setupAccount.mutateAsync({
        email: values.email,
        password: values.password,
      });
      navigate({ to: "/vault" });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Account creation failed");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="h-full bg-base-200 flex items-center justify-center p-4">
      <div className="w-full">
        {/* Logo and Title */}
        <div className="text-center mb-8">
          <div className=" w-16 h-16 bg-primary rounded-full flex items-center justify-center mb-4">
            <svg
              className="w-8 h-8 text-primary-content"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              aria-hidden="true"
            >
              <title>Lock icon</title>
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
              />
            </svg>
          </div>
          <h1 className="text-3xl font-bold text-base-content">Chiikawarden</h1>
          <p className="text-base-content/70 mt-2">Create your secure vault</p>
        </div>

        {/* Main Form Card */}
        <div className="card bg-base-100 shadow-xl">
          <div className="card-body">
            <HeroForm
              schema={signupFormSchema}
              defaultValues={{
                email: "",
                password: "",
                confirmPassword: "",
              }}
              onSubmit={handleSignup}
              className="space-y-4"
            >
              {/* Email Field */}
              <TextInput
                name="email"
                type="email"
                label="Email Address"
                placeholder="Enter your email"
                required
                size="lg"
              />

              {/* Password Field */}
              <TextInput
                name="password"
                type="password"
                label="Master Password"
                placeholder="Enter a strong password"
                required
                size="lg"
              />

              {/* Confirm Password Field */}
              <TextInput
                name="confirmPassword"
                type="password"
                label="Confirm Password"
                placeholder="Confirm your password"
                required
                size="lg"
              />

              {/* Error Message */}
              {error && (
                <div className="alert alert-error mt-4">
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <title>Error icon</title>
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <span>{error}</span>
                </div>
              )}

              {/* Submit Button */}
              <div className="form-control mt-6">
                <Button
                  type="submit"
                  color="primary"
                  size="lg"
                  isDisabled={isSubmitting || authQueries.setupAccount.isPending}
                  isLoading={isSubmitting || authQueries.setupAccount.isPending}
                  className="w-full"
                >
                  {isSubmitting || authQueries.setupAccount.isPending
                    ? "Creating..."
                    : "Create Account"}
                </Button>
              </div>
            </HeroForm>

            {/* Login Link */}
            <div className="text-center mt-4">
              <button
                type="button"
                onClick={() => navigate({ to: "/login" })}
                className="link link-primary text-sm"
              >
                Already have an account? Sign in
              </button>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="text-center mt-8">
          <p className="text-xs text-base-content/50">Protected by end-to-end encryption</p>
        </div>
      </div>
    </div>
  );
}
