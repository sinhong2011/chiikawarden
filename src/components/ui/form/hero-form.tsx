import { Form as HeroUIForm } from "@heroui/form";
import type React from "react";
import { createContext, type ReactNode, useContext } from "react";
import {
  type FieldValues,
  FormProvider,
  type UseFormProps,
  type UseFormReturn,
} from "react-hook-form";
import type { ZodType } from "zod";
import { useHeroForm } from "@/hooks/use-hero-form";
import { cn } from "@/lib/utils";

// Form context for sharing form state with child components
interface HeroFormContextValue<TFieldValues extends FieldValues = FieldValues> {
  form: UseFormReturn<TFieldValues>;
  validationBehavior: "native" | "aria";
}

const HeroFormContext = createContext<HeroFormContextValue | null>(null);

// Hook to access form context
export function useHeroFormContext<TFieldValues extends FieldValues = FieldValues>() {
  const context = useContext(HeroFormContext);
  if (!context) {
    throw new Error("useHeroFormContext must be used within a HeroForm component");
  }
  return context as HeroFormContextValue<TFieldValues>;
}

// Props for the HeroForm component
export interface HeroFormProps<TFieldValues extends FieldValues = FieldValues>
  extends Omit<
    React.FormHTMLAttributes<HTMLFormElement>,
    "onSubmit" | "children" | "encType" | "method" | "target" | "autoComplete"
  > {
  children: ReactNode | ((form: UseFormReturn<TFieldValues>) => ReactNode);
  schema?: ZodType<TFieldValues>;
  defaultValues?: UseFormProps<TFieldValues>["defaultValues"];
  mode?: UseFormProps<TFieldValues>["mode"];
  reValidateMode?: UseFormProps<TFieldValues>["reValidateMode"];
  validationBehavior?: "native" | "aria";
  validationErrors?: Record<string, string | string[]>;
  onSubmit?: (data: TFieldValues, form: UseFormReturn<TFieldValues>) => void | Promise<void>;
  onReset?: () => void;
  className?: string;
  encType?: "application/x-www-form-urlencoded" | "multipart/form-data" | "text/plain";
  method?: "get" | "post" | "dialog";
  target?: "_blank" | "_self" | "_parent" | "_top";
  autoComplete?: "off" | "on";
}

/**
 * HeroForm - A wrapper component that integrates HeroUI Form with react-hook-form + zod validation
 *
 * Features:
 * - Integrates HeroUI Form component with react-hook-form
 * - Supports zod schema validation through zodResolver
 * - Provides server-side validation through validationErrors prop
 * - Maintains compatibility with existing form components
 * - Supports both native and ARIA validation behaviors
 * - Type-safe form handling with TypeScript
 *
 * @example
 * ```tsx
 * const schema = z.object({
 *   email: z.string().email(),
 *   password: z.string().min(8),
 * });
 *
 * <HeroForm
 *   schema={schema}
 *   defaultValues={{ email: "", password: "" }}
 *   onSubmit={(data) => console.log(data)}
 *   validationBehavior="native"
 * >
 *   {(form) => (
 *     <>
 *       <TextInput name="email" label="Email" />
 *       <TextInput name="password" type="password" label="Password" />
 *       <Button type="submit">Submit</Button>
 *     </>
 *   )}
 * </HeroForm>
 * ```
 */
export function HeroForm<TFieldValues extends FieldValues = FieldValues>({
  children,
  schema,
  defaultValues,
  mode = "onBlur",
  reValidateMode = "onChange",
  validationBehavior = "native",
  validationErrors,
  onSubmit,
  onReset,
  className,
  encType,
  method,
  target,
  autoComplete,
  ...formProps
}: HeroFormProps<TFieldValues>) {
  // Use the custom useHeroForm hook for enhanced form management
  const {
    form,
    validationErrors: hookValidationErrors,
    handleSubmit,
  } = useHeroForm<TFieldValues>({
    schema,
    defaultValues,
    mode,
    reValidateMode,
    validationBehavior,
    onSubmit,
  });

  // Handle form reset
  const handleReset = () => {
    form.reset();
    onReset?.();
  };

  // Convert react-hook-form errors to HeroUI validationErrors format
  const getValidationErrors = (): Record<string, string | string[]> => {
    const formErrors: Record<string, string | string[]> = {};

    // Add react-hook-form errors
    Object.entries(form.formState.errors).forEach(([fieldName, error]) => {
      if (error?.message && typeof error.message === "string") {
        formErrors[fieldName] = error.message;
      }
    });

    // Merge with hook validation errors
    Object.assign(formErrors, hookValidationErrors);

    // Merge with external validation errors (highest priority)
    if (validationErrors) {
      Object.assign(formErrors, validationErrors);
    }

    return formErrors;
  };

  const contextValue: HeroFormContextValue<TFieldValues> = {
    form,
    validationBehavior,
  };

  return (
    <FormProvider {...form}>
      <HeroFormContext.Provider value={contextValue as HeroFormContextValue<FieldValues>}>
        <HeroUIForm
          encType={encType}
          method={method}
          target={target}
          autoComplete={autoComplete}
          validationBehavior={validationBehavior}
          validationErrors={getValidationErrors()}
          onSubmit={handleSubmit}
          onReset={handleReset}
          className={cn("space-y-4", className)}
          {...(formProps as Omit<
            React.FormHTMLAttributes<HTMLFormElement>,
            "autoCapitalize" | "role" | "encType" | "method" | "target" | "autoComplete"
          >)}
        >
          {typeof children === "function" ? children(form) : children}
        </HeroUIForm>
      </HeroFormContext.Provider>
    </FormProvider>
  );
}

export type { FieldValues, UseFormReturn } from "react-hook-form";
// Re-export for convenience
export { useForm } from "react-hook-form";
export { useHeroForm } from "@/hooks/use-hero-form";
