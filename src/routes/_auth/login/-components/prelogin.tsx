import { Button } from "@heroui/button";
import { useLingui } from "@lingui/react/macro";
import { useEffect, useState } from "react";
import { Controller } from "react-hook-form";
import { z } from "zod";
import { HeroForm } from "@/components/ui/form";
import { Checkbox } from "@/components/ui/form/checkbox";
import { TextInput } from "@/components/ui/form/text-input";
import { FormErrorMessage } from "@/components/ui/form-error-message";
import { AnimatedSpinner } from "@/components/ui/icon/spinner";
import { useAuthQueries } from "@/hooks/queries/use-auth-queries";
import { useEmailPersistence } from "@/hooks/use-email-persistence";
import type { PreloginResponse } from "@/services/auth.service";
import { useAuthStore } from "@/stores/auth.store";

type PreLoginProps = {
  onFinish: (email: string, kdfSettings: PreloginResponse, rememberMe: boolean) => void;
};

export default function PreLogin(props: PreLoginProps) {
  return <PreloginForm onFinish={props.onFinish} />;
}

type PreloginFormProps = {
  onFinish: (email: string, kdfSettings: PreloginResponse, rememberMe: boolean) => void;
};

const PreloginForm = (props: PreloginFormProps) => {
  const { preloginMutation } = useAuthQueries();
  const { t } = useLingui();
  const { storeEmail, getStoredEmail } = useEmailPersistence();

  // Create schema with i18n support
  const preloginFormSchema = z.object({
    email: z.email(t`validation.email_invalid`).min(1, t`validation.email_required`),
    rememberMe: z.boolean().default(false),
  });

  // Prelogin form handler - trigger mutation on form submit
  const handlePrelogin = async (values: PreloginFormData) => {
    console.log("Email submitted:", values.email, "Remember me:", values.rememberMe);

    try {
      // Handle email persistence based on rememberMe checkbox
      await storeEmail(values.email, values.rememberMe);

      // Trigger the prelogin mutation with the email
      const result = await preloginMutation.mutateAsync(values.email);
      console.log("KDF Settings retrieved:", result);

      // Call onFinish with the email, response, and rememberMe preference
      props.onFinish(values.email, result, values.rememberMe);
    } catch (error) {
      console.error("Prelogin failed:", error);
      // Error handling is managed by the mutation state
    }
  };

  // Determine loading state
  const isLoading = preloginMutation.isPending;

  // Determine error message
  const errorMessage = preloginMutation.isError
    ? preloginMutation.error instanceof Error
      ? preloginMutation.error.message
      : t`error.prelogin_failed`
    : "";

  return (
    <div className="w-full max-w-sm py-10 px-5">
      <PreloginFormWithPersistence
        schema={preloginFormSchema}
        onSubmit={handlePrelogin}
        getStoredEmail={getStoredEmail}
        isLoading={isLoading}
        errorMessage={errorMessage}
      />
    </div>
  );
};

// Component that handles email persistence and form rendering
type PreloginFormData = {
  email: string;
  rememberMe: boolean;
};

type PreloginFormWithPersistenceProps = {
  schema: z.ZodType<PreloginFormData>;
  onSubmit: (values: PreloginFormData) => Promise<void>;
  getStoredEmail: () => Promise<string | null>;
  isLoading: boolean;
  errorMessage: string;
};

const PreloginFormWithPersistence = ({
  schema,
  onSubmit,
  getStoredEmail,
  isLoading,
  errorMessage,
}: PreloginFormWithPersistenceProps) => {
  const { t } = useLingui();
  const authStore = useAuthStore();
  const [initialValues, setInitialValues] = useState<{
    email: string;
    rememberMe: boolean;
  } | null>(null);

  // Load stored email on component mount, with priority for selected account email
  useEffect(() => {
    const loadStoredEmail = async () => {
      try {
        // Use selected account email from store if available, otherwise use stored email
        const emailToUse = authStore.selectedAccountEmail || (await getStoredEmail());
        setInitialValues({
          email: emailToUse || "",
          rememberMe: !!emailToUse, // Set rememberMe to true if email exists
        });

        // Clear selected account email after using it
        if (authStore.selectedAccountEmail) {
          authStore.setSelectedAccountEmail(null);
        }
      } catch (error) {
        console.error("Failed to load stored email:", error);
        setInitialValues({
          email: authStore.selectedAccountEmail || "",
          rememberMe: !!authStore.selectedAccountEmail,
        });

        // Clear selected account email after using it
        if (authStore.selectedAccountEmail) {
          authStore.setSelectedAccountEmail(null);
        }
      }
    };

    loadStoredEmail();
  }, [getStoredEmail, authStore]);

  // Don't render until we've loaded the initial values
  if (initialValues === null) {
    return (
      <div className="w-full max-w-sm py-10 px-5 flex justify-center">
        <AnimatedSpinner />
      </div>
    );
  }

  return (
    <HeroForm
      schema={schema}
      defaultValues={initialValues}
      onSubmit={onSubmit}
      className="space-y-10"
      validationBehavior="aria"
    >
      {(form) => (
        <>
          <Controller
            name="email"
            control={form.control}
            render={({ field: { name, value, onChange, onBlur, ref }, fieldState: { error } }) => (
              <TextInput
                ref={ref}
                name={name}
                type="email"
                label={t`Email` /* 邮箱 */}
                placeholder={t`Enter your email address` /* 输入您的邮箱地址 */}
                value={value}
                onChange={onChange}
                onBlur={onBlur}
                required
                error={error?.message}
                size="lg"
                validationBehavior="aria"
              />
            )}
          />

          {/* Remember Me Checkbox */}
          <Controller
            name="rememberMe"
            control={form.control}
            render={({ field: { name, value, onChange }, fieldState: { error } }) => (
              <Checkbox
                name={name}
                label={t`Remember me` /* 记住我 */}
                description={t`Keep me signed in on this device` /* 在此设备上保持登录状态 */}
                checked={value}
                onChange={(e) => onChange(e.target.checked)}
                error={error?.message}
                size="md"
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
            {isLoading ? t`Verifying email...` /* 验证邮箱中... */ : t`Continue` /* 继续 */}
          </Button>
        </>
      )}
    </HeroForm>
  );
};
