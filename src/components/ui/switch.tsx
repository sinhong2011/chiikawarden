import { Switch as HeroUISwitch } from "@heroui/switch";
import { cn } from "@/lib/utils";

type SwitchProps = {
  name?: string;
  label: string;
  description?: string;
  value?: string;
  defaultChecked?: boolean;
  checked?: boolean;
  error?: string;
  required?: boolean;
  disabled?: boolean;
  size?: "sm" | "md" | "lg";
  id?: string;
  onValueChange?: (checked: boolean) => void;
  onCheckedChange?: (checked: boolean) => void;
  className?: string;
};

export function Switch(props: SwitchProps) {
  return (
    <div className={cn("flex flex-col gap-2", props.className)}>
      <HeroUISwitch
        name={props.name}
        value={props.value}
        defaultSelected={props.defaultChecked}
        isSelected={props.checked ?? props.defaultChecked}
        onValueChange={props.onValueChange || props.onCheckedChange}
        isDisabled={props.disabled}
        required={props.required}
        size={props.size || "md"}
        color={props.error ? "danger" : "primary"}
        classNames={{
          base: "flex items-center gap-3",
          wrapper: cn(props.error && "ring-2 ring-danger"),
          thumb: "bg-white",
          label: cn(
            "font-medium font-sans",
            props.size === "sm" ? "text-sm" : props.size === "lg" ? "text-lg" : "text-base",
            props.error && "text-danger"
          ),
        }}
      >
        {props.label}
        {props.required && <span className="text-danger ml-0.5">*</span>}
      </HeroUISwitch>

      {/* Description */}
      {props.description && (
        <p
          className={cn(
            "text-default-500 font-sans ml-14",
            props.size === "sm" ? "text-xs" : "text-sm",
            props.disabled && "opacity-50"
          )}
        >
          {props.description}
        </p>
      )}

      {/* Error Message */}
      {props.error && (
        <p className="text-danger text-sm font-sans ml-14" role="alert">
          {props.error}
        </p>
      )}
    </div>
  );
}
