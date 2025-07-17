// Tauri mocks for Storybook environment

// Define proper types for mock API
interface MockTauriInvokeArgs {
  [key: string]: unknown;
}

type MockEventHandler = (event: unknown) => void;

interface WindowWithTauri extends Window {
  __TAURI__?: typeof mockTauriAPI.tauri;
  __TAURI_METADATA__?: {
    __currentWindow: {
      label: string;
    };
  };
}

export const mockTauriAPI = {
  tauri: {
    invoke: async (cmd: string, args?: MockTauriInvokeArgs) => {
      console.log(`[Mock Tauri] Invoke: ${cmd}`, args);

      // Mock responses for common commands
      switch (cmd) {
        case "get_settings":
          return {
            theme: "light",
            language: "en",
            server_url: "https://vault.bitwarden.com",
          };
        case "auth_login":
          return {
            success: true,
            token: "mock-token",
          };
        case "get_vault_items":
          return [
            {
              id: "1",
              name: "Example Login",
              type: "login",
              login: {
                username: "user@example.com",
                password: "password123",
              },
            },
          ];
        default:
          return Promise.resolve({});
      }
    },
  },
  event: {
    listen: (event: string, _handler: MockEventHandler) => {
      console.log(`[Mock Tauri] Listen: ${event}`);
      return Promise.resolve(() => {});
    },
    emit: (event: string, payload?: unknown) => {
      console.log(`[Mock Tauri] Emit: ${event}`, payload);
      return Promise.resolve();
    },
  },
  path: {
    appDataDir: () => Promise.resolve("/mock/app/data"),
    appConfigDir: () => Promise.resolve("/mock/app/config"),
  },
  fs: {
    readTextFile: (_path: string) => Promise.resolve("mock file content"),
    writeTextFile: (_path: string, _content: string) => Promise.resolve(),
  },
};

// Global mock setup
if (typeof window !== "undefined") {
  const windowWithTauri = window as WindowWithTauri;
  windowWithTauri.__TAURI__ = mockTauriAPI.tauri;
  windowWithTauri.__TAURI_METADATA__ = {
    __currentWindow: {
      label: "main",
    },
  };
}
