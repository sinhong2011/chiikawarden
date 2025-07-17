import { Button } from "@heroui/button";
import { Input } from "@heroui/input";
import { useLingui } from "@lingui/react/macro";
import { Controller } from "react-hook-form";
import { z } from "zod";
import { HeroForm } from "@/components/ui/form";
import { FormErrorMessage } from "@/components/ui/form-error-message";
import { AnimatedSpinner } from "@/components/ui/icon/spinner";
import { useAuthQueries } from "@/hooks/queries/use-auth-queries";
import type { PreloginResponse } from "@/services/auth.service";

type PreLoginProps = {
  onFinish: (email: string, kdfSettings: PreloginResponse) => void;
};

export default function PreLogin(props: PreLoginProps) {
  return <PreloginForm onFinish={props.onFinish} />;
}

type PreloginFormProps = {
  onFinish: (email: string, kdfSettings: PreloginResponse) => void;
};

const PreloginForm = (props: PreloginFormProps) => {
  const { preloginMutation } = useAuthQueries();
  const { t } = useLingui();

  // Create schema with i18n support
  const preloginFormSchema = z.object({
    email: z.email(t`validation.email_invalid`).min(1, t`validation.email_required`),
  });

  type PreloginFormData = z.infer<typeof preloginFormSchema>;

  // Prelogin form handler - trigger mutation on form submit
  const handlePrelogin = async (values: PreloginFormData) => {
    console.log("Email submitted:", values.email);

    try {
      // Trigger the prelogin mutation with the email
      const result = await preloginMutation.mutateAsync(values.email);
      console.log("KDF Settings retrieved:", result);

      // Call onFinish with the email and response
      props.onFinish(values.email, result);
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
      <HeroForm
        schema={preloginFormSchema}
        defaultValues={{ email: "" }}
        onSubmit={handlePrelogin}
        className="space-y-10"
        validationBehavior="aria"
      >
        {(form) => (
          <>
            <Controller
              name="email"
              control={form.control}
              render={({
                field: { name, value, onChange, onBlur, ref },
                fieldState: { invalid, error },
              }) => (
                <Input
                  ref={ref}
                  name={name}
                  type="email"
                  label={t`Email` /* 邮箱 */}
                  placeholder={t`Enter your email address` /* 输入您的邮箱地址 */}
                  value={value}
                  onChange={onChange}
                  onBlur={onBlur}
                  isRequired
                  isInvalid={invalid}
                  errorMessage={error?.message}
                  size="lg"
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
              {isLoading ? t`Verifying email...` /* 验证邮箱中... */ : t`Continue` /* 继续 */}
            </Button>
          </>
        )}
      </HeroForm>
    </div>
  );
};
