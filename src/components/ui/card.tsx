import {
  Card as HeroUICard,
  CardBody as HeroUICardBody,
  CardFooter as HeroUICardFooter,
  CardHeader as HeroUICardHeader,
} from "@heroui/card";
import type React from "react";
import { cn } from "@/lib/utils";

export interface CardProps {
  children: React.ReactNode;
  className?: string;
  shadow?: "none" | "sm" | "md" | "lg";
  radius?: "none" | "sm" | "md" | "lg";
  isBlurred?: boolean;
  isFooterBlurred?: boolean;
  isHoverable?: boolean;
  isPressable?: boolean;
  disableAnimation?: boolean;
  onPress?: () => void;
}

export interface CardHeaderProps {
  children: React.ReactNode;
  className?: string;
}

export interface CardBodyProps {
  children: React.ReactNode;
  className?: string;
}

export interface CardFooterProps {
  children: React.ReactNode;
  className?: string;
}

export function Card(props: CardProps) {
  const {
    children,
    className,
    shadow = "sm",
    radius = "lg",
    isBlurred = false,
    isFooterBlurred = false,
    isHoverable = false,
    isPressable = false,
    disableAnimation = false,
    onPress,
    ...others
  } = props;

  return (
    <HeroUICard
      shadow={shadow}
      radius={radius}
      isBlurred={isBlurred}
      isFooterBlurred={isFooterBlurred}
      isHoverable={isHoverable}
      isPressable={isPressable}
      disableAnimation={disableAnimation}
      onPress={onPress}
      className={cn(
        "border bg-card text-card-foreground transition-all duration-200",
        isHoverable && "hover:shadow-md hover:scale-[1.02]",
        isPressable && "cursor-pointer active:scale-[0.98]",
        className
      )}
      classNames={{
        base: cn("transition-all duration-200 ease-out", isHoverable && "hover:shadow-md"),
        header: "border-b border-border/50 px-6 py-4",
        body: "px-6 py-4",
        footer: "border-t border-border/50 px-6 py-4",
      }}
      {...others}
    >
      {children}
    </HeroUICard>
  );
}

export function CardHeader(props: CardHeaderProps) {
  const { children, className, ...others } = props;

  return (
    <HeroUICardHeader className={cn("flex flex-col space-y-1.5", className)} {...others}>
      {children}
    </HeroUICardHeader>
  );
}

export function CardBody(props: CardBodyProps) {
  const { children, className, ...others } = props;

  return (
    <HeroUICardBody className={cn("flex-1", className)} {...others}>
      {children}
    </HeroUICardBody>
  );
}

export function CardFooter(props: CardFooterProps) {
  const { children, className, ...others } = props;

  return (
    <HeroUICardFooter className={cn("flex items-center justify-between", className)} {...others}>
      {children}
    </HeroUICardFooter>
  );
}
