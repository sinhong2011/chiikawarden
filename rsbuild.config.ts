import { defineConfig } from "@rsbuild/core";
import { pluginReact } from "@rsbuild/plugin-react";
import { pluginTypeCheck } from "@rsbuild/plugin-type-check";
import { tanstackRouter } from "@tanstack/router-plugin/rspack";

export default defineConfig({
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

  dev: {
    // Use default HMR configuration
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
