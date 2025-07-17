import type { Decorator } from "@storybook/react";
import { I18nProvider } from "../../src/providers/i18n-provider";

export const LocaleDecorator: Decorator = (Story, context) => {
  const locale = context.globals.locale || "en";
  
  return (
    <I18nProvider locale={locale}>
      <Story />
    </I18nProvider>
  );
};
