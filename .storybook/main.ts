import type { StorybookConfig } from "storybook-react-rsbuild";

const config: StorybookConfig = {
  stories: ["../src/**/*.stories.@(js|jsx|ts|tsx|mdx)"],
  addons: [
    "@storybook/addon-onboarding",
    "@storybook/addon-docs",
    "@storybook/addon-a11y",
    "@storybook/addon-links",
    "@storybook/addon-vitest",
  ],
  framework: {
    name: "storybook-react-rsbuild",
    options: {
      builder: {
        // Enable lazy compilation for faster development builds
        lazyCompilation: true,
        // Enable filesystem cache for faster rebuilds
        fsCache: true,
        // Use the existing rsbuild config as base
        rsbuildConfigPath: "./rsbuild.config.ts",
      },
    },
  },
  typescript: {
    check: false,
  },
  rsbuildFinal: async (config, { configType }) => {
    // Configure resolve aliases (inherits from main rsbuild config)
    config.resolve = config.resolve || {};
    config.resolve.alias = {
      ...config.resolve.alias,
      "@": "./src",
    };

    // Configure source defines
    config.source = config.source || {};
    config.source.define = {
      ...config.source.define,
      global: "globalThis",
      __DEV__: configType === "DEVELOPMENT",
      __PROD__: configType === "PRODUCTION",
    };

    // Ensure proper CSS handling for TailwindCSS v4
    config.tools = config.tools || {};
    config.tools.postcss = null;

    // Performance optimizations for development
    if (configType === "DEVELOPMENT") {
      config.dev = config.dev || {};
      config.dev.hmr = true;

      // Optimize source maps for development
      config.output = config.output || {};
      config.output.sourceMap = {
        js: "cheap-module-source-map",
        css: true,
      };
    }

    // Production optimizations
    if (configType === "PRODUCTION") {
      config.output = config.output || {};
      config.output.minify = true;

      // Enable tree shaking
      config.optimization = config.optimization || {};
      config.optimization.sideEffects = false;
    }

    return config;
  },
};

export default config;
