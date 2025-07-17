import type { Preview } from "@storybook/react";
import "../src/assets/styles/global.css";
import "../src/assets/styles/fonts.css";
import "./mocks/tauri";
import "./mocks/i18n";
import { LocaleDecorator } from "./decorators/locale-decorator";
import { ThemeDecorator } from "./decorators/theme-decorator";

const preview: Preview = {
  decorators: [ThemeDecorator, LocaleDecorator],
  parameters: {
    actions: { argTypesRegex: "^on[A-Z].*" },
    controls: {
      matchers: {
        color: /(background|color)$/i,
        date: /Date$/,
      },
    },
    docs: {
      toc: true,
    },
    viewport: {
      viewports: {
        mobile: {
          name: "Mobile",
          styles: {
            width: "375px",
            height: "667px",
          },
        },
        tablet: {
          name: "Tablet",
          styles: {
            width: "768px",
            height: "1024px",
          },
        },
        desktop: {
          name: "Desktop",
          styles: {
            width: "1024px",
            height: "768px",
          },
        },
        large: {
          name: "Large Desktop",
          styles: {
            width: "1440px",
            height: "900px",
          },
        },
      },
    },
  },
  globalTypes: {
    theme: {
      description: "Global theme for components",
      defaultValue: "light",
      toolbar: {
        title: "Theme",
        icon: "paintbrush",
        items: ["light", "dark"],
        dynamicTitle: true,
      },
    },
    locale: {
      description: "Internationalization locale",
      defaultValue: "en",
      toolbar: {
        title: "Locale",
        icon: "globe",
        items: [
          { value: "en", title: "English" },
          { value: "zh-CN", title: "简体中文" },
          { value: "zh-HK", title: "繁體中文 (香港)" },
          { value: "zh-TW", title: "繁體中文 (台灣)" },
        ],
        dynamicTitle: true,
      },
    },
  },
};

export default preview;
