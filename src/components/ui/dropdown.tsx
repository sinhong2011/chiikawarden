import {
  Button,
  type ButtonProps,
  DropdownItem,
  DropdownMenu,
  DropdownSection,
  DropdownTrigger,
  Dropdown as HeroDropdown,
} from "@heroui/react";
import { ChevronDown } from "lucide-react";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

export type Option = {
  label: string;
  value: string;
  disabled?: boolean;
  endContent?: ReactNode;
  onEndContentClick?: (value: string) => void;
};

export type Section = {
  title: string;
  options: Option[];
  showDivider?: boolean;
};

export type DropdownProps = {
  placeholder?: string;
  options?: Option[];
  sections?: Section[];
  value: string | undefined;
  disabled?: boolean;
  size?: "sm" | "md" | "lg";
  variant?: ButtonProps["variant"];
  onChange: (value: string) => void;
  className?: string;
  colors?: ButtonProps["color"];
};

export function Dropdown(props: DropdownProps) {
  // Find selected option from either options or sections
  const findSelectedOption = () => {
    if (props.options) {
      return props.options.find((option) => option.value === props.value);
    }
    if (props.sections) {
      for (const section of props.sections) {
        const found = section.options.find((option) => option.value === props.value);
        if (found) return found;
      }
    }
    return undefined;
  };

  const selectedOption = findSelectedOption();

  // Map variant to HeroUI Button variant

  // Render dropdown content based on whether sections or options are provided
  const renderDropdownContent = () => {
    if (props.sections) {
      const sections = props.sections;
      return sections.map((section, index) => (
        <DropdownSection
          key={section.title}
          title={section.title}
          showDivider={section.showDivider ?? index < sections.length - 1}
          classNames={{
            heading: "text-xs font-semibold text-default-500 uppercase tracking-wide px-2 py-1",
            group: "px-1",
            divider: "my-2",
          }}
        >
          {section.options.map((option) => (
            <DropdownItem
              key={option.value}
              className={cn(
                "text-sm",
                option.disabled && "opacity-50 cursor-not-allowed",
                option.value === props.value && "font-medium"
              )}
              {...(option.disabled && { "data-disabled": true })}
              endContent={
                option.endContent ? (
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      option.onEndContentClick?.(option.value);
                    }}
                    className="flex items-center p-1 rounded hover:bg-default-100 transition-colors"
                    aria-label="Action button"
                  >
                    {option.endContent}
                  </button>
                ) : undefined
              }
            >
              {option.label}
            </DropdownItem>
          ))}
        </DropdownSection>
      ));
    }

    if (props.options) {
      return props.options.map((option) => (
        <DropdownItem
          key={option.value}
          className={cn(
            "text-sm",
            option.disabled && "opacity-50 cursor-not-allowed",
            option.value === props.value && "font-medium"
          )}
          {...(option.disabled && { "data-disabled": true })}
          endContent={
            option.endContent ? (
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  option.onEndContentClick?.(option.value);
                }}
                className="flex items-center p-1 rounded hover:bg-default-100 transition-colors"
                aria-label="Action button"
              >
                {option.endContent}
              </button>
            ) : undefined
          }
        >
          {option.label}
        </DropdownItem>
      ));
    }

    return null;
  };

  return (
    <HeroDropdown isDisabled={props.disabled}>
      <DropdownTrigger>
        <Button
          variant={props.variant}
          size={props.size || "md"}
          endContent={<ChevronDown className="w-4 h-4 text-default-400" />}
          className={cn("justify-between font-medium min-w-[200px]", props.className)}
          isDisabled={props.disabled}
          color={props.colors}
        >
          {selectedOption?.label || props.placeholder || "Select an option"}
        </Button>
      </DropdownTrigger>

      <DropdownMenu
        aria-label="Dropdown selection"
        onAction={(key) => {
          const selectedKey = key as string;
          if (selectedKey && selectedKey !== props.value) {
            props.onChange(selectedKey);
          }
        }}
        selectedKeys={props.value ? [props.value] : []}
        selectionMode="single"
        className="min-w-[200px]"
      >
        {renderDropdownContent()}
      </DropdownMenu>
    </HeroDropdown>
  );
}
