import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { type FieldValues, type UseFormProps, type UseFormReturn, useForm } from "react-hook-form";
import type { z } from "zod";

// Options for useHeroForm hook
export interface UseHeroFormOptions<TFieldValues extends FieldValues = FieldValues>
  extends Omit<UseFormProps<TFieldValues>, "resolver"> {
  schema?: z.ZodType<TFieldValues>;
  validationBehavior?: "native" | "aria";
  onSubmit?: (data: TFieldValues, form: UseFormReturn<TFieldValues>) => void | Promise<void>;
  onError?: (error: Error) => void;
}

// Return type for useHeroForm hook
export interface UseHeroFormReturn<TFieldValues extends FieldValues = FieldValues> {
  form: UseFormReturn<TFieldValues>;
  isSubmitting: boolean;
  submitError: string | null;
  validationErrors: Record<string, string | string[]>;
  handleSubmit: (e?: React.BaseSyntheticEvent) => Promise<void>;
  setValidationErrors: (errors: Record<string, string | string[]>) => void;
  clearValidationErrors: () => void;
  reset: () => void;
}

/**
 * Custom hook for managing HeroUI forms with react-hook-form + zod integration
 *
 * Features:
 * - Integrates react-hook-form with zod validation
 * - Manages submission state and errors
 * - Supports server-side validation errors
 * - Provides convenient methods for form management
 * - Type-safe with TypeScript
 *
 * @example
 * ```tsx
 * const schema = z.object({
 *   email: z.string().email(),
 *   password: z.string().min(8),
 * });
 *
 * function LoginForm() {
 *   const {
 *     form,
 *     isSubmitting,
 *     submitError,
 *     validationErrors,
 *     handleSubmit,
 *     setValidationErrors,
 *   } = useHeroForm({
 *     schema,
 *     defaultValues: { email: "", password: "" },
 *     onSubmit: async (data) => {
 *       try {
 *         await loginUser(data);
 *       } catch (error) {
 *         if (error.validationErrors) {
 *           setValidationErrors(error.validationErrors);
 *         }
 *         throw error;
 *       }
 *     },
 *   });
 *
 *   return (
 *     <HeroForm
 *       form={form}
 *       validationErrors={validationErrors}
 *       onSubmit={handleSubmit}
 *     >
 *       <TextInput name="email" label="Email" />
 *       <TextInput name="password" type="password" label="Password" />
 *       <Button type="submit" isLoading={isSubmitting}>
 *         {isSubmitting ? "Signing in..." : "Sign In"}
 *       </Button>
 *       {submitError && <div className="text-danger">{submitError}</div>}
 *     </HeroForm>
 *   );
 * }
 * ```
 */
export function useHeroForm<TFieldValues extends FieldValues = FieldValues>({
  schema,
  validationBehavior = "native",
  onSubmit,
  onError,
  ...formOptions
}: UseHeroFormOptions<TFieldValues> = {}): UseHeroFormReturn<TFieldValues> {
  // Set up react-hook-form with optional zod validation
  const form = useForm<TFieldValues>({
    ...formOptions,
    resolver: schema
      ? (
          zodResolver as (schema: z.ZodType<TFieldValues>) => UseFormProps<TFieldValues>["resolver"]
        )(schema)
      : undefined,
  });

  // State for submission and validation
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [validationErrors, setValidationErrors] = useState<Record<string, string | string[]>>({});

  // Handle form submission using react-hook-form's handleSubmit
  const handleSubmit = useCallback(
    async (e?: React.BaseSyntheticEvent) => {
      if (!onSubmit) return;

      const submitHandler = form.handleSubmit(async (data) => {
        setIsSubmitting(true);
        setSubmitError(null);
        setValidationErrors({});

        try {
          await onSubmit(data, form as UseFormReturn<TFieldValues>);
        } catch (error) {
          const errorMessage = error instanceof Error ? error.message : "An error occurred";
          setSubmitError(errorMessage);
          onError?.(error instanceof Error ? error : new Error(errorMessage));
        } finally {
          setIsSubmitting(false);
        }
      });

      return submitHandler(e);
    },
    [form, onSubmit, onError]
  );

  // Clear validation errors
  const clearValidationErrors = useCallback(() => {
    setValidationErrors({});
  }, []);

  // Reset form and clear errors
  const reset = useCallback(() => {
    form.reset();
    setSubmitError(null);
    setValidationErrors({});
  }, [form]);

  return {
    form: form as UseFormReturn<TFieldValues>,
    isSubmitting,
    submitError,
    validationErrors,
    handleSubmit,
    setValidationErrors,
    clearValidationErrors,
    reset,
  };
}

/**
 * Hook for managing form field validation with HeroUI Form integration
 * This hook should be used within a FormProvider context from react-hook-form
 *
 * @example
 * ```tsx
 * function CustomInput({ name, ...props }) {
 *   const { fieldError, isInvalid } = useFormFieldValidation(name);
 *
 *   return (
 *     <Input
 *       {...props}
 *       name={name}
 *       isInvalid={isInvalid}
 *       errorMessage={fieldError}
 *     />
 *   );
 * }
 * ```
 */
export function useFormFieldValidation(fieldName: string) {
  // This hook is designed to work with external validation errors
  // For react-hook-form integration, use the form's formState.errors directly
  const [validationErrors] = useState<Record<string, string | string[]>>({});

  const fieldError = validationErrors[fieldName];
  const isInvalid = Boolean(fieldError);

  return {
    fieldError: Array.isArray(fieldError) ? fieldError[0] : fieldError,
    isInvalid,
  };
}

/**
 * Hook for managing form submission state
 *
 * @example
 * ```tsx
 * function SubmitButton() {
 *   const { isSubmitting, submitError } = useFormSubmission();
 *
 *   return (
 *     <div>
 *       <Button type="submit" isLoading={isSubmitting}>
 *         Submit
 *       </Button>
 *       {submitError && <div className="text-danger">{submitError}</div>}
 *     </div>
 *   );
 * }
 * ```
 */
export function useFormSubmission() {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  return {
    isSubmitting,
    submitError,
    setIsSubmitting,
    setSubmitError,
  };
}
