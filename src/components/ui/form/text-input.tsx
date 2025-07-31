import type React from "react";
import { forwardRef } from "react";
import { BaseTextInput, type BaseTextInputProps } from "./base-text-input";

// Extract Hero UI component prop types for compatibility
type HeroUIInputProps = React.ComponentProps<typeof import("@heroui/input").Input>;

// TextInput-specific props that extend the base props
type TextInputSpecificProps = {
  multiline?: false; // Maintained for backward compatibility
};

// For single-line input, extend base props with HeroUI Input props
type TextInputProps = BaseTextInputProps &
  TextInputSpecificProps &
  Omit<
    HeroUIInputProps,
    "isRequired" | "isDisabled" | "isReadOnly" | "startContent" | "endContent"
  > & {
    // Allow type prop for backward compatibility
    type?: string;
  };

/**
 * TextInput - A standard text input component for forms
 *
 * Features:
 * - All functionality from BaseTextInput
 * - Support for various input types (text, email, url, etc.)
 * - Integration with react-hook-form and zod validation
 * - Consistent styling with other form components
 * - TypeScript type safety
 * - Accessibility support
 *
 * @example
 * ```tsx
 * // Basic usage
 * <TextInput
 *   name="email"
 *   type="email"
 *   label="Email Address"
 *   placeholder="Enter your email"
 *   required
 * />
 *
 * // With react-hook-form Controller
 * <Controller
 *   name="email"
 *   control={form.control}
 *   render={({ field, fieldState }) => (
 *     <TextInput
 *       {...field}
 *       error={fieldState.error?.message}
 *       label="Email Address"
 *       placeholder="Enter your email"
 *       required
 *     />
 *   )}
 * />
 * ```
 */
export const TextInput = forwardRef<HTMLInputElement | HTMLTextAreaElement, TextInputProps>(
  (props, ref) => {
    // TextInput is a simple wrapper around BaseTextInput
    // All the common functionality is handled by BaseTextInput
    // The multiline prop is maintained for backward compatibility but not used
    return <BaseTextInput {...props} ref={ref as React.Ref<HTMLInputElement>} />;
  }
);

TextInput.displayName = "TextInput";
