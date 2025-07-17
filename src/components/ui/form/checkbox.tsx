import { Checkbox as HeroUICheckbox } from "@heroui/checkbox";
import type React from "react";
import { cn } from "@/lib/utils";

// Extract Hero UI Checkbox component prop types
type HeroUICheckboxProps = React.ComponentProps<typeof HeroUICheckbox>;

type CheckboxProps = {
  // Form-specific props
  name: string;
  label: string;
  description?: string;
  value?: string;
  checked?: boolean | undefined;
  error?: string;
  required?: boolean;
  disabled?: boolean;
  onChange?: React.ChangeEventHandler<HTMLInputElement>;
} & Omit<
  HeroUICheckboxProps,
  "isRequired" | "isDisabled" | "isSelected" | "onValueChange" | "children"
>;

export function Checkbox(props: CheckboxProps) {
  const {
    name,
    label,
    description,
    value,
    checked,
    error = "",
    required,
    disabled,
    onChange,
    ...heroUIProps
  } = props;

  return (
    <div className="space-y-2">
      <HeroUICheckbox
        {...heroUIProps}
        name={name}
        value={value}
        isSelected={checked}
        onValueChange={(isSelected) => {
          // Create a synthetic event for compatibility
          const syntheticEvent = {
            target: { checked: isSelected, name, value },
            currentTarget: { checked: isSelected, name, value },
          } as React.ChangeEvent<HTMLInputElement>;
          onChange?.(syntheticEvent);
        }}
        isRequired={required}
        isDisabled={disabled}
        color={error ? "danger" : heroUIProps.color || "primary"}
        className={cn("font-medium", error && "text-danger", heroUIProps.className)}
        classNames={{
          base: "flex items-start gap-3",
          wrapper: cn(error && "ring-2 ring-danger"),
          icon: "text-white",
          label: cn(
            "font-medium cursor-pointer select-none leading-relaxed",
            disabled && "opacity-50 cursor-not-allowed",
            error && "text-danger"
          ),
          ...heroUIProps.classNames,
        }}
      >
        <div className="flex-1 min-w-0">
          <span className="flex items-center">
            {label}
            {required && <span className="text-danger ml-0.5">*</span>}
          </span>
          {description && (
            <p
              className={cn(
                "mt-1 text-default-500 leading-relaxed",
                heroUIProps.size === "sm" ? "text-xs" : "text-sm",
                disabled && "opacity-50"
              )}
            >
              {description}
            </p>
          )}
        </div>
      </HeroUICheckbox>
      {error && <div className="text-sm text-danger font-medium ml-8">{error}</div>}
    </div>
  );
}
