import { Link as HeroUILink } from "@heroui/link";
import type React from "react";
import { cn } from "@/lib/utils";

export interface LinkProps {
  variant?: "primary" | "secondary" | "accent" | "neutral" | "ghost" | "underline";
  size?: "sm" | "md" | "lg";
  disabled?: boolean;
  external?: boolean;
  children: React.ReactNode;
  href: string;
  target?: string;
  rel?: string;
  className?: string;
  onClick?: () => void;
}

export function Link(props: LinkProps) {
  const {
    variant = "primary",
    size = "md",
    disabled = false,
    external = false,
    children,
    href,
    target,
    rel,
    className,
    onClick,
    ...others
  } = props;

  // Map variant to HeroUI color and underline
  const getHeroUIColor = () => {
    switch (variant) {
      case "primary":
        return "primary";
      case "secondary":
        return "secondary";
      case "accent":
        return "success"; // Map accent to success as closest match
      case "neutral":
        return "foreground";
      case "ghost":
        return "foreground";
      case "underline":
        return "primary";
      default:
        return "primary";
    }
  };

  const getUnderline = () => {
    switch (variant) {
      case "underline":
        return "always";
      case "ghost":
        return "hover";
      default:
        return "none";
    }
  };

  return (
    <HeroUILink
      href={href}
      size={size}
      color={getHeroUIColor()}
      underline={getUnderline()}
      isExternal={external}
      isDisabled={disabled}
      target={target}
      rel={rel}
      onPress={onClick}
      className={cn("font-medium transition-colors duration-200", className)}
      {...others}
    >
      {children}
    </HeroUILink>
  );
}
