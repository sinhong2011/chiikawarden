import { Textarea as HeroUITextarea } from "@heroui/input";
import type React from "react";
import { forwardRef } from "react";
import { cn } from "@/lib/utils";

// Extract Hero UI Textarea component prop types
type HeroUITextareaProps = React.ComponentProps<typeof HeroUITextarea>;

type TextAreaProps = {
  // Form-specific props
  name: string;
  error?: string;
  required?: boolean;
  disabled?: boolean;
  readOnly?: boolean;
  resize?: "none" | "both" | "horizontal" | "vertical";
  validate?: (value: string) => string | undefined;
} & Omit<HeroUITextareaProps, "isRequired" | "isDisabled" | "isReadOnly">;

export const TextArea = forwardRef<HTMLTextAreaElement, TextAreaProps>((props, ref) => {
  const {
    name,
    error = "",
    required,
    disabled,
    readOnly,
    resize = "vertical",
    ...heroUIProps
  } = props;

  return (
    <HeroUITextarea
      {...heroUIProps}
      ref={ref}
      name={name}
      isRequired={required}
      isDisabled={disabled}
      isReadOnly={readOnly}
      isInvalid={!!error}
      errorMessage={error}
      className={cn("font-medium", heroUIProps.className)}
      classNames={{
        input: cn(
          "font-medium",
          resize === "none" && "resize-none",
          resize === "horizontal" && "resize-x",
          resize === "vertical" && "resize-y",
          resize === "both" && "resize"
        ),
        inputWrapper: cn(error && "border-danger data-[focus=true]:ring-danger"),
        errorMessage: "text-danger font-medium",
        description: "text-default-500",
        label: cn("font-medium", required && "after:content-['*'] after:text-danger after:ml-0.5"),
        ...heroUIProps.classNames,
      }}
    />
  );
});

TextArea.displayName = "TextArea";
