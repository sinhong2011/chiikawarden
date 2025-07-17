import { RadioGroup as HeroUIRadioGroup, Radio } from "@heroui/radio";
import type React from "react";
import { cn } from "@/lib/utils";

// Extract Hero UI RadioGroup component prop types
type HeroUIRadioGroupProps = React.ComponentProps<typeof HeroUIRadioGroup>;

type RadioOption = {
  label: string;
  value: string;
  description?: string;
  disabled?: boolean;
};

type RadioGroupProps = {
  // Form-specific props
  name: string;
  options: RadioOption[];
  error?: string;
  required?: boolean;
  disabled?: boolean;
  onChange?: React.ChangeEventHandler<HTMLInputElement | HTMLTextAreaElement>;
} & Omit<HeroUIRadioGroupProps, "isRequired" | "isDisabled" | "onValueChange" | "children">;

export function RadioGroup(props: RadioGroupProps) {
  const { name, options, error = "", required, disabled, onChange, ...heroUIProps } = props;

  return (
    <HeroUIRadioGroup
      {...heroUIProps}
      name={name}
      onValueChange={(selectedValue) => {
        // Create a synthetic event for compatibility
        const syntheticEvent = {
          target: { value: selectedValue, name },
          currentTarget: { value: selectedValue, name },
        } as React.ChangeEvent<HTMLInputElement>;
        onChange?.(syntheticEvent);
      }}
      isRequired={required}
      isDisabled={disabled}
      isInvalid={!!error}
      errorMessage={error}
      className={cn("font-medium", heroUIProps.className)}
      classNames={{
        base: "space-y-2",
        wrapper: cn(
          "flex gap-4",
          heroUIProps.orientation === "horizontal" ? "flex-row" : "flex-col"
        ),
        label: "font-medium",
        description: "text-default-500 text-sm",
        errorMessage: "text-danger text-sm font-medium",
        ...heroUIProps.classNames,
      }}
    >
      {options.map((option) => (
        <Radio
          key={option.value}
          value={option.value}
          isDisabled={option.disabled}
          className={cn("font-medium")}
          classNames={{
            base: "flex items-start gap-3 max-w-none",
            wrapper: cn(error && "ring-2 ring-danger"),
            control: cn(
              error &&
                "border-danger data-[selected=true]:bg-danger data-[selected=true]:border-danger"
            ),
            label: cn(
              "font-medium cursor-pointer select-none leading-relaxed",
              disabled && "opacity-50 cursor-not-allowed",
              error && "text-danger"
            ),
            description: cn(
              "text-default-500 leading-relaxed",
              heroUIProps.size === "sm" ? "text-xs" : "text-sm",
              disabled && "opacity-50"
            ),
          }}
        >
          <div className="flex-1 min-w-0">
            <span className="block">{option.label}</span>
            {option.description && (
              <p className="mt-1 text-default-500 text-sm">{option.description}</p>
            )}
          </div>
        </Radio>
      ))}
    </HeroUIRadioGroup>
  );
}
