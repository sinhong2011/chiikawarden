import { Input } from "@heroui/input";
import type React from "react";
import { forwardRef, useCallback } from "react";
import { cn } from "@/lib/utils";

// Extract Hero UI component prop types
type HeroUIInputProps = React.ComponentProps<typeof Input>;

// Common props that extend Hero UI's native props
type BaseTextInputProps = {
  // Form-specific props
  name: string;
  error?: string;
  required?: boolean;
  disabled?: boolean;
  readOnly?: boolean;

  // TextInput-specific props
  icon?: React.ReactNode;
  validate?: (value: string) => string | undefined;
  onClear?: () => void;
};

// For single-line input, extend Hero UI Input props
type SingleLineTextInputProps = BaseTextInputProps &
  Omit<HeroUIInputProps, "isRequired" | "isDisabled" | "isReadOnly" | "startContent"> & {
    multiline?: false;
  };

type TextInputProps = SingleLineTextInputProps;

export const TextInput = forwardRef<HTMLInputElement | HTMLTextAreaElement, TextInputProps>(
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

    // Common props for both Input and Textarea (without onBlur - handled separately)
    const { onBlur: _, ...heroUIPropsWithoutOnBlur } = heroUIProps;
    const commonProps = {
      ...heroUIPropsWithoutOnBlur,
      name,
      isRequired: required,
      isDisabled: disabled,
      isReadOnly: readOnly,
      isInvalid: !!error,
      errorMessage: error,
      startContent: icon,
      className: cn("font-medium", heroUIProps.className),
      classNames: {
        input: cn("font-medium"),
        inputWrapper: cn(error && "border-danger data-[focus=true]:ring-danger"),
        errorMessage: "text-danger font-medium",
        description: "text-default-500",
        label: cn("font-medium", required && "after:content-['*'] after:text-danger after:ml-0.5"),
        ...heroUIProps.classNames,
      },
    };

    // Handle clear functionality
    const handleClear = () => {
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
    };

    // Render single line input
    return (
      <Input
        {...commonProps}
        ref={ref as React.Ref<HTMLInputElement>}
        isClearable={heroUIProps.isClearable}
        onClear={heroUIProps.isClearable ? handleClear : undefined}
        onBlur={handleInputBlur}
      />
    );
  }
);

TextInput.displayName = "TextInput";
