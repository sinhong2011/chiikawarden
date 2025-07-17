import { Select as HeroUISelect, SelectItem } from "@heroui/select";
import type React from "react";
import { cn } from "@/lib/utils";

// Extract Hero UI Select component prop types
type HeroUISelectProps = React.ComponentProps<typeof HeroUISelect>;

type Option = {
  label: string;
  value: string;
  disabled?: boolean;
};

type SelectProps = {
  // Form-specific props
  name: string;
  options: Option[];
  value?: string | undefined;
  error?: string;
  required?: boolean;
  disabled?: boolean;
  onChange?: React.ChangeEventHandler<HTMLSelectElement>;
} & Omit<
  HeroUISelectProps,
  "isRequired" | "isDisabled" | "children" | "onSelectionChange" | "selectedKeys"
>;

export function Select(props: SelectProps) {
  const { name, options, value, error = "", required, disabled, onChange, ...heroUIProps } = props;

  return (
    <HeroUISelect
      {...heroUIProps}
      name={name}
      selectedKeys={value ? [value] : []}
      onSelectionChange={(keys) => {
        const selectedKey = Array.from(keys)[0] as string;
        if (selectedKey && onChange) {
          const syntheticEvent = {
            target: { value: selectedKey, name },
            currentTarget: { value: selectedKey, name },
          } as React.ChangeEvent<HTMLSelectElement>;
          onChange(syntheticEvent);
        }
      }}
      isRequired={required}
      isDisabled={disabled}
      isInvalid={!!error}
      errorMessage={error}
      className={cn("font-medium", heroUIProps.className)}
      classNames={{
        trigger: cn(error && "border-danger data-[focus=true]:ring-danger"),
        errorMessage: "text-danger",
        ...heroUIProps.classNames,
      }}
    >
      {options.map((option) => (
        <SelectItem
          key={option.value}
          data-disabled={option.disabled}
          className={cn(option.disabled && "opacity-50 cursor-not-allowed")}
        >
          {option.label}
        </SelectItem>
      ))}
    </HeroUISelect>
  );
}
