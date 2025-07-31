import type { Decorator } from "@storybook/react";
import { HeroUIProviderWrapper } from "@/providers/heroui-provider";
import "@/assets/styles/global.css";

/**
 * Theme decorator for Storybook stories
 * 
 * Provides HeroUI theme context and global styles to all stories
 */
export const ThemeDecorator: Decorator = (Story) => {
  return (
    <HeroUIProviderWrapper>
      <div className="min-h-screen bg-background text-foreground">
        <Story />
      </div>
    </HeroUIProviderWrapper>
  );
};
