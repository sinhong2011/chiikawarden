import { Button } from "@heroui/button";
import { Modal as HeroUIModal, ModalBody, ModalContent, ModalHeader } from "@heroui/modal";
import { X } from "lucide-react";
import type React from "react";
import { cn } from "@/lib/utils";

export interface ModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title?: string;
  description?: string;
  children: React.ReactNode;
  size?: "sm" | "md" | "lg" | "xl" | "full";
  showCloseButton?: boolean;
  closeOnOverlayClick?: boolean;
  closeOnEscape?: boolean;
  animateHeight?: boolean;
  heightAnimationType?: "smooth" | "spring" | "bounce" | "fast" | "slow";
  className?: string;
  contentClassName?: string;
}

export function Modal(props: ModalProps) {
  const {
    open,
    onOpenChange,
    title,
    description,
    children,
    size = "md",
    showCloseButton = true,
    closeOnOverlayClick = true,
    closeOnEscape = true,
    className,
    contentClassName,
    ...others
  } = props;

  // Map size to HeroUI size
  const getHeroUISize = () => {
    switch (size) {
      case "sm":
        return "sm";
      case "lg":
        return "lg";
      case "xl":
        return "xl";
      case "full":
        return "full";
      default:
        return "md";
    }
  };

  return (
    <HeroUIModal
      isOpen={open}
      onOpenChange={onOpenChange}
      size={getHeroUISize()}
      isDismissable={closeOnOverlayClick}
      isKeyboardDismissDisabled={!closeOnEscape}
      className={cn("backdrop-blur-xl", className)}
      classNames={{
        backdrop: cn("bg-black/30 backdrop-blur-xl"),
        wrapper: cn("flex items-center justify-center p-4"),
        base: cn(
          "relative rounded-xl border shadow-2xl",
          "transition-all duration-300 ease-out",
          contentClassName
        ),
      }}
      motionProps={{
        variants: {
          enter: {
            y: 0,
            opacity: 1,
            scale: 1,
            transition: {
              duration: 0.3,
              ease: "easeOut",
            },
          },
          exit: {
            y: -20,
            opacity: 0,
            scale: 0.98,
            transition: {
              duration: 0.25,
              ease: "easeOut",
            },
          },
        },
      }}
      {...others}
    >
      <ModalContent>
        {(onClose) => (
          <>
            {/* Header */}
            {(title || showCloseButton) && (
              <ModalHeader className="flex items-start justify-between p-6 pb-4 border-b">
                <div className="flex-1">
                  {title && <h2 className="text-lg font-semibold tracking-tight">{title}</h2>}
                  {description && (
                    <p className="text-sm text-default-500 mt-1 leading-relaxed">{description}</p>
                  )}
                </div>
                {showCloseButton && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onPress={onClose}
                    className="h-8 w-8 p-0 text-default-500 hover:text-default-700 hover:bg-default-100 ml-4 rounded-md transition-all duration-150 ease-out"
                  >
                    <X size={16} />
                    <span className="sr-only">Close</span>
                  </Button>
                )}
              </ModalHeader>
            )}

            {/* Content */}
            <ModalBody className="p-6">{children}</ModalBody>
          </>
        )}
      </ModalContent>
    </HeroUIModal>
  );
}
