import { Input } from "@heroui/input";
import type React from "react";
import { forwardRef, useCallback } from "react";
import { cn } from "@/lib/utils";

// Extract Hero UI component prop types
type HeroUIInputProps = React.ComponentProps<typeof Input>;

// Base props that are common to all text input variants
export type BaseTextInputProps = {
  // Form-specific props
  name: string;
  error?: string;
  required?: boolean;
  disabled?: boolean;
  readOnly?: boolean;

  // Common input props
  icon?: React.ReactNode;
  validate?: (value: string) => string | undefined;
  onClear?: () => void;
};

// Props for the BaseTextInput component
export type BaseTextInputComponentProps = BaseTextInputProps &
  Omit<HeroUIInputProps, "isRequired" | "isDisabled" | "isReadOnly" | "startContent"> & {
    // Allow overriding startContent for specialized components
    startContent?: React.ReactNode;
    // Allow overriding endContent for specialized components
    endContent?: React.ReactNode;
    // Allow overriding type for specialized components
    type?: string;
  };

/**
 * BaseTextInput - A foundational input component that provides common functionality
 * for all text input variants in the form system.
 *
 * Features:
 * - HeroUI Input integration with consistent styling
 * - Form validation support with react-hook-form
 * - Error handling and display
 * - Accessibility features with proper ARIA labels
 * - Clear functionality
 * - TypeScript type safety
 * - Customizable icons and content
 *
 * This component is designed to be extended by specialized input components
 * like TextInput and PasswordInput, providing a consistent foundation while
 * allowing for component-specific customizations.
 *
 * @example
 * ```tsx
 * // Basic usage (typically used by other components)
 * <BaseTextInput
 *   name="email"
 *   type="email"
 *   label="Email"
 *   placeholder="Enter your email"
 *   required
 *   error={error}
 * />
 * ```
 */
export const BaseTextInput = forwardRef<HTMLInputElement, BaseTextInputComponentProps>(
  (props, ref) => {
    const {
      name,
      error = "",
      required,
      disabled,
      readOnly,
      icon,
      validate,
      onClear,
      startContent,
      endContent,
      type = "text",
      ...heroUIProps
    } = props;

    // Handle validation on blur for input
    const handleInputBlur = useCallback(
      (e: React.FocusEvent<HTMLInputElement>) => {
        // Call the original onBlur handler if provided
        if (heroUIProps.onBlur) {
          heroUIProps.onBlur(e);
        }

        // Perform validation if validate function is provided and no external error is set
        if (validate && !error) {
          const validationError = validate(e.target.value);
          if (validationError) {
            // Note: This validation result would typically be handled by a parent form component
            // The component itself doesn't manage validation state internally to avoid conflicts
            // with external form libraries like react-hook-form
            console.warn(`Validation error for field "${name}": ${validationError}`);
          }
        }
      },
      [heroUIProps.onBlur, validate, error, name]
    );

    // Handle clear functionality
    const handleClear = useCallback(() => {
      if (onClear) {
        onClear();
      } else if (heroUIProps.onChange) {
        // Create synthetic event for clearing
        const syntheticEvent = {
          target: { value: "", name },
          currentTarget: { value: "", name },
        } as React.ChangeEvent<HTMLInputElement>;
        heroUIProps.onChange(syntheticEvent);
      }
    }, [onClear, heroUIProps.onChange, name]);

    // Prepare props for HeroUI Input (without onBlur - handled separately)
    const { onBlur: _, ...heroUIPropsWithoutOnBlur } = heroUIProps;
    const inputProps = {
      ...heroUIPropsWithoutOnBlur,
      ref,
      name,
      type,
      isRequired: required,
      isDisabled: disabled,
      isReadOnly: readOnly,
      isInvalid: !!error,
      errorMessage: error,
      startContent: startContent || icon,
      endContent,
      className: cn("font-medium gap-1", heroUIProps.className),
      classNames: {
        input: cn("font-medium"),
        inputWrapper: cn(error && "border-danger data-[focus=true]:ring-danger"),
        errorMessage: "text-danger font-medium",
        description: "text-default-500",
        label: cn("font-medium", required && "after:content-['*'] after:text-danger after:ml-0.5"),
        ...heroUIProps.classNames,
      },
      isClearable: heroUIProps.isClearable,
      onClear: heroUIProps.isClearable ? handleClear : undefined,
      onBlur: handleInputBlur,
    };

    return <Input {...inputProps} />;
  }
);

BaseTextInput.displayName = "BaseTextInput";
