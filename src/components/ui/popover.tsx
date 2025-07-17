import { Button } from "@heroui/button";
import { Popover as HeroUIPopover, PopoverContent, PopoverTrigger } from "@heroui/react";
import type React from "react";
import { cn } from "@/lib/utils";

export interface PopoverProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  children: React.ReactNode;
  trigger: React.ReactNode;
  placement?:
    | "top"
    | "bottom"
    | "left"
    | "right"
    | "top-start"
    | "top-end"
    | "bottom-start"
    | "bottom-end"
    | "left-start"
    | "left-end"
    | "right-start"
    | "right-end";
  offset?: number;
  showArrow?: boolean;
  backdrop?: "transparent" | "opaque" | "blur";

  className?: string;
  contentClassName?: string;
}

export function Popover(props: PopoverProps) {
  const {
    open,
    onOpenChange,
    children,
    trigger,
    placement = "bottom",
    offset = 8,
    showArrow = true,
    backdrop = "transparent",

    className,
    contentClassName,
  } = props;

  return (
    <HeroUIPopover
      isOpen={open}
      onOpenChange={onOpenChange}
      placement={placement}
      offset={offset}
      showArrow={showArrow}
      backdrop={backdrop}
      className={cn(className)}
      classNames={{
        content: cn(
          "p-0 shadow-xl rounded-lg",
          "transition-all duration-200 ease-out",
          contentClassName
        ),
      }}
    >
      <PopoverTrigger asChild>{trigger}</PopoverTrigger>
      <PopoverContent>{children}</PopoverContent>
    </HeroUIPopover>
  );
}

export interface ConfirmPopoverProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  trigger: React.ReactNode;
  title?: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
  variant?: "destructive" | "primary" | "secondary";
  isLoading?: boolean;
  error?: string | null;
  onConfirm: () => void;
  onCancel: () => void;
  placement?: PopoverProps["placement"];
  icon?: React.ReactNode;
}

export function ConfirmPopover(props: ConfirmPopoverProps) {
  const {
    open,
    onOpenChange,
    trigger,
    title,
    message,
    confirmText = "Confirm",
    cancelText = "Cancel",
    variant = "primary",
    isLoading = false,
    error,
    onConfirm,
    onCancel,
    placement = "bottom-start",
    icon,
  } = props;

  const getConfirmButtonColor = () => {
    switch (variant) {
      case "destructive":
        return "danger";
      case "primary":
        return "primary";
      case "secondary":
        return "secondary";
      default:
        return "primary";
    }
  };

  return (
    <Popover
      open={open}
      onOpenChange={onOpenChange}
      trigger={trigger}
      placement={placement}
      contentClassName="min-w-[300px] max-w-[400px]"
    >
      <div className="p-4 space-y-4">
        {/* Header with icon and title */}
        {(icon || title) && (
          <div className="flex items-center gap-3">
            {icon && (
              <div
                className={cn(
                  "flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center",
                  variant === "destructive" && "bg-danger/10 text-danger",
                  variant === "primary" && "bg-primary/10 text-primary",
                  variant === "secondary" && "bg-secondary/10 text-secondary"
                )}
              >
                {icon}
              </div>
            )}
            {title && <h4 className="font-medium text-base-content">{title}</h4>}
          </div>
        )}

        {/* Message */}
        <p className="text-sm text-base-content/70 leading-relaxed">{message}</p>

        {/* Error message */}
        {error && <div className="text-danger text-sm">{error}</div>}

        {/* Actions */}
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="light" size="sm" onPress={onCancel} isDisabled={isLoading}>
            {cancelText}
          </Button>
          <Button
            color={getConfirmButtonColor()}
            size="sm"
            onPress={onConfirm}
            isLoading={isLoading}
          >
            {confirmText}
          </Button>
        </div>
      </div>
    </Popover>
  );
}
