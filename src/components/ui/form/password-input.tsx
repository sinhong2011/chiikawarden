import { Button } from "@heroui/button";
import { useLingui } from "@lingui/react/macro";
import { Eye, EyeOff } from "lucide-react";
import type React from "react";
import { forwardRef, useState } from "react";
import { BaseTextInput, type BaseTextInputProps } from "./base-text-input";

// Extract Hero UI component prop types for compatibility
type HeroUIInputProps = React.ComponentProps<typeof import("@heroui/input").Input>;

// Password input specific props
type PasswordInputSpecificProps = {
  // Password-specific props
  showToggle?: boolean; // Whether to show the show/hide toggle button
  defaultVisible?: boolean; // Whether password is visible by default
  onVisibilityChange?: (visible: boolean) => void; // Callback when visibility changes
};

// Password input props that extend the base props
type PasswordInputProps = BaseTextInputProps &
  PasswordInputSpecificProps &
  Omit<
    HeroUIInputProps,
    "type" | "isRequired" | "isDisabled" | "isReadOnly" | "startContent" | "endContent"
  >;

/**
 * PasswordInput - A specialized input component for password fields
 *
 * Features:
 * - Built-in show/hide password toggle functionality
 * - Consistent styling with other form components
 * - Integration with react-hook-form and zod validation
 * - TypeScript type safety
 * - Accessibility support with proper ARIA labels
 * - Lock icon as default start content
 *
 * @example
 * ```tsx
 * // Basic usage
 * <PasswordInput
 *   name="password"
 *   label="Password"
 *   placeholder="Enter your password"
 *   required
 * />
 *
 * // With react-hook-form Controller
 * <Controller
 *   name="password"
 *   control={form.control}
 *   render={({ field, fieldState }) => (
 *     <PasswordInput
 *       {...field}
 *       error={fieldState.error?.message}
 *       label="Master Password"
 *       placeholder="Enter your master password"
 *       required
 *     />
 *   )}
 * />
 * ```
 */
export const PasswordInput = forwardRef<HTMLInputElement, PasswordInputProps>((props, ref) => {
  const { showToggle = true, defaultVisible = false, onVisibilityChange, ...baseProps } = props;

  const { t } = useLingui();
  const [isVisible, setIsVisible] = useState(defaultVisible);

  // Handle visibility toggle
  const toggleVisibility = () => {
    const newVisibility = !isVisible;
    setIsVisible(newVisibility);
    onVisibilityChange?.(newVisibility);
  };

  // Create the toggle button for show/hide functionality
  const toggleButton = showToggle ? (
    <Button
      type="button"
      variant="light"
      size="sm"
      isIconOnly
      onPress={toggleVisibility}
      className="text-muted-foreground hover:text-foreground transition-colors"
      aria-label={isVisible ? t`Hide password` /* 隐藏密码 */ : t`Show password` /* 显示密码 */}
    >
      {isVisible ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
    </Button>
  ) : undefined;

  // Use BaseTextInput with password-specific customizations
  return (
    <BaseTextInput
      {...baseProps}
      ref={ref}
      type={isVisible ? "text" : "password"}
      endContent={toggleButton}
      classNames={{
        input: "font-medium text-base",
        inputWrapper: "focus-within:border-primary transition-colors",
        ...baseProps.classNames,
      }}
    />
  );
});

PasswordInput.displayName = "PasswordInput";
