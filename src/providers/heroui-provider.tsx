import { HeroUIProvider } from "@heroui/system";
import { ToastProvider } from "@heroui/toast";
import type React from "react";

export function HeroUIProviderWrapper({ children }: { children: React.ReactNode }) {
  return (
    <HeroUIProvider className="h-full">
      <ToastProvider
        placement="top-right"
        toastProps={{
          timeout: 4000,
          variant: "flat",
          radius: "md",
        }}
      />
      {children}
    </HeroUIProvider>
  );
}
