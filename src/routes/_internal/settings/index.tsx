import { createFileRoute, Link } from "@tanstack/react-router";
import { Bug, ExternalLink } from "lucide-react";
import { useSettingsQueries } from "@/hooks/queries/use-settings-queries";

export const Route = createFileRoute("/_internal/settings/")({
  component: SettingsIndexComponent,
});

function SettingsIndexComponent() {
  const settingsQueries = useSettingsQueries();

  const handleThemeChange = (theme: string) => {
    settingsQueries.updateTheme.mutate(theme);
  };

  if (settingsQueries.settings.isLoading) {
    return (
      <div className="p-6 ">
        <h1 className="text-2xl font-bold mb-6">Settings</h1>
        <div className="text-center py-8">Loading settings...</div>
      </div>
    );
  }

  if (settingsQueries.settings.error) {
    return (
      <div className="p-6 ">
        <h1 className="text-2xl font-bold mb-6">Settings</h1>
        <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
          Error loading settings: {settingsQueries.settings.error?.message}
        </div>
      </div>
    );
  }

  const settings = settingsQueries.settings.data;

  if (!settings) {
    return (
      <div className="p-6 ">
        <h1 className="text-2xl font-bold mb-6">Settings</h1>
        <div className="text-center py-8">No settings data available.</div>
      </div>
    );
  }

  return (
    <div className="p-6 ">
      <h1 className="text-2xl font-bold mb-6">Settings</h1>

      <div className="space-y-6">
        {/* Theme Settings */}
        <div className="bg-white p-4 rounded-lg shadow">
          <h2 className="text-lg font-semibold mb-4">Appearance</h2>
          <div className="space-y-2">
            <label htmlFor="theme-select" className="block text-sm font-medium text-gray-700">
              Theme
            </label>
            <select
              id="theme-select"
              value={settings.theme}
              onChange={(e) => handleThemeChange(e.target.value)}
              className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500"
              disabled={settingsQueries.updateTheme.isPending}
            >
              <option value="system">System</option>
              <option value="light">Light</option>
              <option value="dark">Dark</option>
            </select>
          </div>
        </div>

        {/* Security Settings */}
        <div className="bg-white p-4 rounded-lg shadow">
          <h2 className="text-lg font-semibold mb-4">Security</h2>
          <div className="space-y-4">
            <div>
              <label htmlFor="vault-timeout" className="block text-sm font-medium text-gray-700">
                Vault Timeout (minutes)
              </label>
              <input
                id="vault-timeout"
                type="number"
                value={
                  typeof settings.vault_timeout === "string" ? "" : settings.vault_timeout.Minutes
                }
                onChange={(e) =>
                  settingsQueries.updateVaultTimeout.mutate(parseInt(e.target.value))
                }
                className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500"
                min="1"
                max="1440"
              />
            </div>
            <div className="flex items-center">
              <input
                type="checkbox"
                id="biometric"
                checked={settings.biometric_unlock}
                onChange={(e) => settingsQueries.updateBiometricUnlock.mutate(e.target.checked)}
                className="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
              />
              <label htmlFor="biometric" className="ml-2 block text-sm text-gray-900">
                Enable biometric unlock
              </label>
            </div>
          </div>
        </div>

        {/* Application Settings */}
        <div className="bg-white p-4 rounded-lg shadow">
          <h2 className="text-lg font-semibold mb-4">Application</h2>
          <div className="space-y-4">
            <div className="flex items-center">
              <input
                type="checkbox"
                id="minimize_to_tray"
                checked={settings.minimize_to_tray}
                onChange={(e) => {
                  const currentSettings = settingsQueries.getCurrentSettings();
                  if (currentSettings) {
                    settingsQueries.updateSettings.mutate({
                      minimize_to_tray: e.target.checked,
                    });
                  }
                }}
                className="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
              />
              <label htmlFor="minimize_to_tray" className="ml-2 block text-sm text-gray-900">
                Minimize to system tray
              </label>
            </div>
            <div className="flex items-center">
              <input
                type="checkbox"
                id="auto_start"
                checked={settings.auto_start}
                onChange={(e) => {
                  const currentSettings = settingsQueries.getCurrentSettings();
                  if (currentSettings) {
                    settingsQueries.updateSettings.mutate({
                      auto_start: e.target.checked,
                    });
                  }
                }}
                className="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
              />
              <label htmlFor="auto_start" className="ml-2 block text-sm text-gray-900">
                Start with system
              </label>
            </div>
          </div>
        </div>

        {/* Diagnostics Section - Only show in development mode */}
        {__DEV__ && (
          <div className="bg-white p-4 rounded-lg shadow">
            <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
              <Bug className="w-5 h-5 text-primary" />
              Diagnostics
            </h2>
            <p className="text-sm text-gray-600 mb-4">
              Advanced diagnostic tools for troubleshooting authentication and keyring issues.
            </p>
            <Link
              to="/settings/diagnostics"
              className="inline-flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-md hover:bg-primary/90 focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 transition-colors"
            >
              <Bug className="w-4 h-4" />
              Open Diagnostics
              <ExternalLink className="w-4 h-4" />
            </Link>
          </div>
        )}

        {/* Reset Settings */}
        <div className="bg-white p-4 rounded-lg shadow">
          <h2 className="text-lg font-semibold mb-4">Reset</h2>
          <button
            type="button"
            onClick={() => settingsQueries.resetSettings.mutate()}
            disabled={settingsQueries.resetSettings.isPending}
            className="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:opacity-50"
          >
            {settingsQueries.resetSettings.isPending ? "Resetting..." : "Reset to Defaults"}
          </button>
        </div>
      </div>
    </div>
  );
}
