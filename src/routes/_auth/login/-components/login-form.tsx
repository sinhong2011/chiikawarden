import { Button } from "@heroui/button";
import { Input } from "@heroui/input";
import { Switch } from "@heroui/switch";
import { useLingui } from "@lingui/react/macro";
import { useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { z } from "zod";
import { HeroForm } from "@/components/ui/form";
import { useAuth } from "@/hooks/use-auth";
import { authService, type KdfConfig, type PreloginResponse } from "@/services/auth.service";

type LoginFormProps = {
  email: string;
  kdfSettings: PreloginResponse;
  onBack: () => void;
};

export default function LoginForm(props: LoginFormProps) {
  const { t } = useLingui();
  const navigate = useNavigate();
  const auth = useAuth();
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  // Create schema with i18n support
  const loginFormSchema = z.object({
    password: z.string().min(1, t`validation.password_required`),
    rememberMe: z.boolean(),
  });

  type LoginFormData = z.infer<typeof loginFormSchema>;

  // State for remember me switch
  const [rememberMe, setRememberMe] = useState(false);

  // Convert PreloginResponse to KdfConfig
  const getKdfConfig = (): KdfConfig => ({
    kdf_type: props.kdfSettings.kdf,
    iterations: props.kdfSettings.kdfIterations,
    memory: props.kdfSettings.kdfMemory,
    parallelism: props.kdfSettings.kdfParallelism,
  });

  // Login form handler
  const handleLogin = async (data: LoginFormData) => {
    setError("");
    setIsLoading(true);

    // Add rememberMe to the data
    const loginData = { ...data, rememberMe };

    try {
      const kdfConfig = getKdfConfig();
      const response = await authService.loginWithPassword(
        props.email,
        loginData.password,
        kdfConfig
      );

      if (response.success) {
        // Update auth state through the auth hook
        const loginSuccess = await auth.login({
          email: props.email,
          password: loginData.password,
          rememberMe: loginData.rememberMe,
        });

        if (loginSuccess) {
          // Navigate to vault on successful login
          navigate({ to: "/vault" });
        } else {
          setError(t`error.login_failed`);
        }
      } else {
        setError(t`error.invalid_credentials`);
      }
    } catch (err) {
      console.error("Login error:", err);
      setError(err instanceof Error ? err.message : t`error.login_failed`);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="">
      <div className="mb-6">
        <h2 className="text-2xl font-semibold text-center mb-2">
          {t`Welcome back` /* 欢迎回来 */}
        </h2>
        <p className="text-base-content/70 text-center text-sm">
          {t`Sign in to` /* 登录到 */}{" "}
          <span className="font-medium text-base-content">{props.email}</span>
        </p>
      </div>

      <HeroForm schema={loginFormSchema} defaultValues={{ password: "" }} onSubmit={handleLogin}>
        <div className="space-y-4">
          {/* Email display (read-only) */}
          <div className="space-y-2">
            <div className="block text-sm font-medium text-base-content mb-2">
              {t`Email Address` /* 邮箱地址 */}
            </div>
            <div className="flex items-center gap-2 p-3 bg-base-200 rounded-lg border border-base-300">
              <span className="text-base-content flex-1">{props.email}</span>
              <button
                type="button"
                onClick={props.onBack}
                className="text-primary hover:text-primary/80 text-sm font-medium transition-colors"
              >
                {t`Change` /* 更改 */}
              </button>
            </div>
          </div>

          {/* Password field */}
          <Input
            name="password"
            type="password"
            label={t`Master Password` /* 主密码 */}
            placeholder={t`Enter your master password` /* 输入您的主密码 */}
            required
            size="lg"
          />

          {/* Remember me switch */}
          <Switch isSelected={rememberMe} onValueChange={setRememberMe} size="md">
            <div className="flex flex-col">
              <span className="text-sm font-medium">{t`Remember me` /* 记住我 */}</span>
              <span className="text-xs text-base-content/70">
                {t`Keep me signed in on this device` /* 在此设备上保持登录状态 */}
              </span>
            </div>
          </Switch>

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
            {isLoading ? t`Signing in...` /* 登录中... */ : t`Sign In` /* 登录 */}
          </Button>

          {/* Additional options */}
          <div className="text-center">
            <button
              type="button"
              className="text-primary hover:text-primary/80 text-sm font-medium transition-colors"
            >
              {t`Can't access your account?` /* 无法访问您的账户？ */}
            </button>
          </div>
        </div>
      </HeroForm>

      {/* KDF Settings info (for debugging/transparency) */}
      {import.meta.env.DEV && (
        <div className="mt-6 p-3 bg-base-200/50 rounded-lg border border-base-300/50">
          <details className="text-xs">
            <summary className="cursor-pointer text-base-content/70 font-medium">
              Security Settings (Dev Info)
            </summary>
            <div className="mt-2 space-y-1 text-base-content/60">
              <div>KDF: {props.kdfSettings.kdf === 0 ? "PBKDF2" : "Argon2id"}</div>
              <div>Iterations: {props.kdfSettings.kdfIterations.toLocaleString()}</div>
              {props.kdfSettings.kdfMemory && <div>Memory: {props.kdfSettings.kdfMemory} KB</div>}
              {props.kdfSettings.kdfParallelism && (
                <div>Parallelism: {props.kdfSettings.kdfParallelism}</div>
              )}
            </div>
          </details>
        </div>
      )}
    </div>
  );
}
