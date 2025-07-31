import { Button } from "@heroui/button";
import { useLingui } from "@lingui/react/macro";
import { useNavigate } from "@tanstack/react-router";
import { Controller } from "react-hook-form";
import { z } from "zod";
import { HeroForm } from "@/components/ui/form";
import { PasswordInput } from "@/components/ui/form/password-input";
import { FormErrorMessage } from "@/components/ui/form-error-message";
import { AnimatedSpinner } from "@/components/ui/icon/spinner";
import { useAuthQueries } from "@/hooks/queries/use-auth-queries";
import type { PreloginResponse } from "@/services/auth.service";
import type { LoginCredentials } from "@/types/auth.types";

export interface LoginFormProps {
  email: string;
  kdfSettings: PreloginResponse;
  rememberMe: boolean;
  onBack: () => void;
}

/**
 * Enhanced Login Form Component
 *
 * Features:
 * - Modern, minimalist design with smooth animations
 * - Comprehensive error handling with retry functionality
 * - Password visibility toggle
 * - Accessible form controls with proper ARIA labels
 * - Loading states with visual feedback
 * - Responsive design
 * - Integration with established design system
 */
export default function LoginForm(props: LoginFormProps) {
  const { email, kdfSettings, rememberMe, onBack } = props;
  const navigate = useNavigate();
  const { t } = useLingui();
  const { login: loginMutation } = useAuthQueries();

  // Create schema with i18n support
  const loginFormSchema = z.object({
    password: z.string().min(1, t`validation.password_required` /* 密码不能为空 */),
  });

  type LoginFormData = z.infer<typeof loginFormSchema>;

  // Login form handler - trigger mutation on form submit
  const handleLogin = async (values: LoginFormData) => {
    console.log("Login submitted:", { email, rememberMe });

    try {
      // Prepare credentials for auth store
      const credentials: LoginCredentials = {
        email,
        password: values.password,
        rememberMe,
      };

      // Trigger the login mutation - this handles all authentication logic and navigation
      const ok = await loginMutation.mutateAsync(credentials);

      console.log("Login result:", ok);

      // Navigation is now handled in the mutation's onSuccess callback
      if (!ok) {
        throw new Error("Login failed. Please check your credentials and try again.");
      }

      navigate({
        to: "/vault",
      });
    } catch (error) {
      console.error("Login failed:", error);
      // Error handling is managed by the mutation state
    }
  };

  // Determine loading state
  const isLoading = loginMutation.isPending;

  // Determine error message - now properly translated from the mutation
  const errorMessage = loginMutation.isError
    ? loginMutation.error instanceof Error
      ? loginMutation.error.message
      : t`Login failed. Please check your credentials and try again.` /* 登录失败。请检查您的凭据并重试。 */
    : "";

  return (
    <div className="w-full max-w-sm py-10 px-5">
      {/* Header Section */}
      <div className="mb-10 text-center">
        <p className="text-muted-foreground text-base leading-relaxed">
          {t`Sign in to` /* 登录到 */}{" "}
          <button
            type="button"
            onClick={onBack}
            className="font-semibold text-foreground hover:text-primary transition-colors underline decoration-dotted underline-offset-4"
          >
            {email}
          </button>
        </p>
      </div>

      <HeroForm
        schema={loginFormSchema}
        defaultValues={{ password: "" }}
        onSubmit={handleLogin}
        className="space-y-10"
        validationBehavior="aria"
      >
        {(form) => (
          <>
            {/* Password Field */}
            <Controller
              name="password"
              control={form.control}
              render={({
                field: { name, value, onChange, onBlur, ref },
                fieldState: { error },
              }) => (
                <PasswordInput
                  ref={ref}
                  name={name}
                  label={t`Master Password` /* 主密码 */}
                  placeholder={t`Enter your master password` /* 输入您的主密码 */}
                  value={value}
                  onChange={onChange}
                  onBlur={onBlur}
                  size="lg"
                  required
                  error={error?.message}
                  validationBehavior="aria"
                />
              )}
            />

            <FormErrorMessage error={errorMessage} />

            <Button
              type="submit"
              color="primary"
              size="lg"
              isDisabled={isLoading}
              isLoading={isLoading}
              className="w-full"
              spinner={<AnimatedSpinner />}
            >
              {isLoading ? t`Signing in...` /* 登录中... */ : t`Sign In` /* 登录 */}
            </Button>
          </>
        )}
      </HeroForm>

      {/* KDF Settings info (for debugging/transparency) */}
      {import.meta.env.DEV && (
        <div className="mt-8 p-4 bg-muted/30 rounded-xl border border-border/30">
          <details className="text-xs">
            <summary className="cursor-pointer text-muted-foreground font-medium hover:text-foreground transition-colors">
              {t`Security Settings (Dev Info)` /* 安全设置（开发信息） */}
            </summary>
            <div className="mt-3 space-y-2 text-muted-foreground">
              <div className="flex justify-between">
                <span>KDF:</span>
                <span className="font-mono">{kdfSettings.kdf === 0 ? "PBKDF2" : "Argon2id"}</span>
              </div>
              <div className="flex justify-between">
                <span>Iterations:</span>
                <span className="font-mono">{kdfSettings.kdfIterations.toLocaleString()}</span>
              </div>
              {kdfSettings.kdfMemory && (
                <div className="flex justify-between">
                  <span>Memory:</span>
                  <span className="font-mono">{kdfSettings.kdfMemory} KB</span>
                </div>
              )}
              {kdfSettings.kdfParallelism && (
                <div className="flex justify-between">
                  <span>Parallelism:</span>
                  <span className="font-mono">{kdfSettings.kdfParallelism}</span>
                </div>
              )}
            </div>
          </details>
        </div>
      )}
    </div>
  );
}
