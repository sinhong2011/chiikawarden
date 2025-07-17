import { AlertCircle } from "lucide-react";
import React from "react";
import { cn } from "@/lib/utils";

export interface FormErrorMessageProps {
  /** Error message(s) to display. Can be a single string or array of strings for multiple errors */
  error?: string | string[] | null | undefined;
  /** Additional CSS classes to apply to the container */
  className?: string;
  /** Size variant for the error message */
  size?: "sm" | "md" | "lg";
  /** Whether to show the error icon */
  showIcon?: boolean;
  /** Custom icon to display instead of the default error icon */
  icon?: React.ReactNode;
  /** Whether to animate the appearance of the error message */
  animate?: boolean;
  /** Unique ID for accessibility purposes */
  id?: string;
  /** Additional props to pass to the container div */
  containerProps?: React.HTMLAttributes<HTMLDivElement>;
}

/**
 * FormErrorMessage - A reusable component for displaying form validation errors
 *
 * Features:
 * - Supports single or multiple error messages
 * - Accessible with proper ARIA attributes
 * - Consistent styling with the design system
 * - Responsive and customizable
 * - Optional icon display
 * - Smooth animations
 * - Type-safe with TypeScript
 *
 * @example
 * ```tsx
 * // Single error message
 * <FormErrorMessage error="Email is required" />
 *
 * // Multiple error messages
 * <FormErrorMessage error={["Email is required", "Email must be valid"]} />
 *
 * // Custom styling
 * <FormErrorMessage
 *   error="Password too short"
 *   size="lg"
 *   className="mt-4"
 *   showIcon={false}
 * />
 * ```
 */
export const FormErrorMessage = React.memo<FormErrorMessageProps>(
  ({
    error,
    className,
    size = "sm",
    showIcon = true,
    icon,
    animate = true,
    id,
    containerProps,
  }) => {
    // Normalize error to array for consistent handling
    const errors = Array.isArray(error) ? error.filter(Boolean) : [error].filter(Boolean);

    // Size-based styling
    const getSizeClasses = () => {
      switch (size) {
        case "lg":
          return {
            text: "text-base",
            icon: "h-5 w-5",
            gap: "gap-3",
          };
        case "md":
          return {
            text: "text-sm",
            icon: "h-4 w-4",
            gap: "gap-2.5",
          };
        default:
          return {
            text: "text-sm",
            icon: "h-4 w-4",
            gap: "gap-2",
          };
      }
    };

    const sizeClasses = getSizeClasses();

    // Base container classes
    const containerClasses = cn(
      "flex items-start",
      sizeClasses.gap,
      animate && "animate-in slide-in-from-top-1 duration-200",
      className
    );

    // Error text classes
    const textClasses = cn("text-danger font-medium leading-relaxed", sizeClasses.text);

    // Icon classes
    const iconClasses = cn("text-danger flex-shrink-0 mt-0.5", sizeClasses.icon);

    // Generate unique ID if not provided
    const generatedId = React.useId();
    const errorId = id || `form-error-${generatedId}`;

    // Don't render if no error
    if (!error || (Array.isArray(error) && error.length === 0)) {
      return null;
    }

    // Don't render if no valid errors after filtering
    if (errors.length === 0) {
      return null;
    }

    return (
      <div
        {...containerProps}
        className={containerClasses}
        role="alert"
        aria-live="polite"
        aria-atomic="true"
        id={errorId}
      >
        {/* Error Icon */}
        {showIcon && (
          <div className="flex-shrink-0 mt-0.5">
            {icon || <AlertCircle className={iconClasses} aria-hidden="true" />}
          </div>
        )}

        {/* Error Messages */}
        <div className="flex-1 min-w-0">
          {errors.length === 1 ? (
            // Single error message
            <div className={textClasses}>{errors[0]}</div>
          ) : (
            // Multiple error messages as a list
            <ul className={cn(textClasses, "space-y-1")}>
              {errors.map((errorMsg, index) => (
                <li key={`error-${index}-${errorMsg?.slice(0, 10)}`} className="flex items-start">
                  <span className="mr-2 text-danger">•</span>
                  <span className="flex-1">{errorMsg}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    );
  }
);

FormErrorMessage.displayName = "FormErrorMessage";

// Convenience hook for form error handling
export const useFormErrorMessage = (error?: string | string[] | null | undefined) => {
  const hasError = React.useMemo(() => {
    if (!error) return false;
    if (Array.isArray(error)) return error.some(Boolean);
    return Boolean(error);
  }, [error]);

  const generatedId = React.useId();
  const errorId = React.useMemo(
    () => (hasError ? `form-error-${generatedId}` : undefined),
    [hasError, generatedId]
  );

  return {
    hasError,
    errorId,
    errorProps: hasError
      ? {
          "aria-describedby": errorId,
          "aria-invalid": true,
        }
      : {},
  };
};
