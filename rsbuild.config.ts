import { defineConfig, mergeRsbuildConfig } from "@rsbuild/core";
import { pluginReact } from "@rsbuild/plugin-react";
import { pluginTypeCheck } from "@rsbuild/plugin-type-check";
import { tanstackRouter } from "@tanstack/router-plugin/rspack";

const baseConfig = defineConfig({
  plugins: [pluginReact(), pluginTypeCheck()],

  html: {
    template: "./index.html",
  },

  resolve: {
    aliasStrategy: "prefer-tsconfig",
  },

  source: {
    entry: {
      index: "./src/index.tsx",
    },
    define: {
      __DEV__: process.env.NODE_ENV === "development",
      __PROD__: process.env.NODE_ENV === "production",
    },
  },

  output: {
    distPath: {
      root: "dist",
    },
  },

  server: {
    port: 5174,
    strictPort: true,
  },

  tools: {
    rspack: {
      plugins: [
        tanstackRouter({
          target: "react",
          autoCodeSplitting: true,
          routesDirectory: "./src/routes",
          generatedRouteTree: "./src/routeTree.gen.ts",
          routeFileIgnorePrefix: "-",
          quoteStyle: "double",
          semicolons: true,
          disableTypes: false,
          addExtensions: false,
          disableLogging: false,
        }),
      ],
      watchOptions: {
        ignored: ["**/src-tauri/**", "**/node_modules/**", "**/.git/**"],
      },
      module: {
        rules: [
          {
            test: /\.(jsx?|tsx?)$/,
            exclude: /node_modules/,
            use: [
              {
                loader: "builtin:swc-loader",
                options: {
                  sourceMap: true,
                  jsc: {
                    parser: {
                      syntax: "typescript",
                      tsx: true,
                    },
                    experimental: {
                      plugins: [["@lingui/swc-plugin", {}]],
                    },
                    transform: {
                      react: {
                        runtime: "automatic",
                      },
                    },
                  },
                },
              },
            ],
          },
        ],
      },
    },
  },
});

const devConfig = defineConfig({
  dev: {
    progressBar: true,
    lazyCompilation: true,
    client: {
      // Preserve authentication context during HMR
      overlay: true,
    },
  },
});

const productionConfig = defineConfig({
  output: {
    minify: true,
  },
  performance: {
    removeConsole: true,
    buildCache: true,
  },
});

export default defineConfig(({ envMode }) => {
  switch (envMode) {
    case "production":
      return mergeRsbuildConfig(baseConfig, productionConfig);
    default:
      return mergeRsbuildConfig(baseConfig, devConfig);
  }
});
