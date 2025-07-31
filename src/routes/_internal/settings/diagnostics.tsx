import { createFileRoute } from "@tanstack/react-router";
import { AlertTriangle, Bug, Info } from "lucide-react";
import { CipherDebug } from "@/components/debug/cipher-debug";
import {
  KeyringStatusCard,
  RecoveryActionsCard,
  SettingsDiagnosticsCard,
  TestOperationsCard,
  TokenDiagnosticCard,
} from "@/components/diagnostics";

export const Route = createFileRoute("/_internal/settings/diagnostics")({
  component: SettingsDiagnosticsComponent,
});

function SettingsDiagnosticsComponent() {
  return (
    <div className="p-6 max-w-6xl mx-auto">
      {/* Header */}
      <div className="mb-8">
        <div className="flex items-center gap-3 mb-4">
          <Bug className="w-6 h-6 text-primary" />
          <h1 className="text-2xl font-bold">Application Diagnostics</h1>
        </div>
        <p className="text-muted-foreground">
          Comprehensive diagnostic tools for troubleshooting application settings, authentication,
          database health, and system configuration. Use these tools to identify and resolve issues
          across all application components.
        </p>
      </div>

      {/* Development Mode Notice */}
      {__DEV__ && (
        <div className="mb-6 p-4 bg-info-50 border border-info-200 rounded-lg">
          <div className="flex items-start gap-3">
            <Info className="w-5 h-5 text-info-600 mt-0.5 flex-shrink-0" />
            <div>
              <p className="text-sm font-medium text-info-800">Development Mode</p>
              <p className="text-sm text-info-700 mt-1">
                You're running in development mode. All diagnostic features are available. In
                production, some features may be limited for security.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Warning Notice */}
      <div className="mb-6 p-4 bg-warning-50 border border-warning-200 rounded-lg">
        <div className="flex items-start gap-3">
          <AlertTriangle className="w-5 h-5 text-warning-600 mt-0.5 flex-shrink-0" />
          <div>
            <p className="text-sm font-medium text-warning-800">Important Notice</p>
            <p className="text-sm text-warning-700 mt-1">
              These diagnostic tools are designed for troubleshooting authentication issues. Some
              operations may require re-authentication. Always ensure you have your credentials
              available before performing recovery actions.
            </p>
          </div>
        </div>
      </div>

      {/* Diagnostic Cards Grid */}
      <div className="space-y-6">
        {/* Row 1: Comprehensive Settings Diagnostics */}
        <div className="grid grid-cols-1 gap-6">
          <SettingsDiagnosticsCard />
        </div>

        {/* Row 2: System Status */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <KeyringStatusCard />
          <TokenDiagnosticCard />
        </div>

        {/* Row 3: Operations and Recovery */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <TestOperationsCard />
          <RecoveryActionsCard />
        </div>

        {/* Row 4: Cipher Debug */}
        <div className="grid grid-cols-1 gap-6">
          <CipherDebug />
        </div>
      </div>

      {/* Help Section */}
      <div className="mt-8 p-4 bg-default-50 rounded-lg">
        <h3 className="text-lg font-semibold mb-3">Diagnostic Workflow</h3>
        <div className="space-y-3 text-sm text-default-600">
          <div className="flex items-start gap-3">
            <span className="flex-shrink-0 w-6 h-6 bg-primary text-white rounded-full flex items-center justify-center text-xs font-medium">
              1
            </span>
            <div>
              <p className="font-medium">Run Comprehensive Diagnostics</p>
              <p>
                Start with the Settings Diagnostics card to get a complete overview of all
                application components including settings, authentication, database, network, and
                vault status.
              </p>
            </div>
          </div>

          <div className="flex items-start gap-3">
            <span className="flex-shrink-0 w-6 h-6 bg-primary text-white rounded-full flex items-center justify-center text-xs font-medium">
              2
            </span>
            <div>
              <p className="font-medium">Check Specific Components</p>
              <p>
                Use individual diagnostic cards below for detailed analysis of keyring status, token
                diagnostics, and specific operations testing.
              </p>
            </div>
          </div>

          <div className="flex items-start gap-3">
            <span className="flex-shrink-0 w-6 h-6 bg-primary text-white rounded-full flex items-center justify-center text-xs font-medium">
              3
            </span>
            <div>
              <p className="font-medium">Test Operations</p>
              <p>
                Verify that critical operations like token storage, settings persistence, and
                database operations work correctly.
              </p>
            </div>
          </div>

          <div className="flex items-start gap-3">
            <span className="flex-shrink-0 w-6 h-6 bg-primary text-white rounded-full flex items-center justify-center text-xs font-medium">
              4
            </span>
            <div>
              <p className="font-medium">Recovery Actions</p>
              <p>
                If issues are found, use recovery actions to clear problematic data, reset
                authentication state, or restore default settings.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Common Issues Section */}
      <div className="mt-6 p-4 bg-default-50 rounded-lg">
        <h3 className="text-lg font-semibold mb-3">Common Issues & Solutions</h3>
        <div className="space-y-3 text-sm text-default-600">
          <div>
            <p className="font-medium text-danger-600">❌ Mock Keyring Backend Detected</p>
            <p>
              Your system is using a mock keyring which cannot securely store credentials. This
              typically happens in development environments or when system keyring is not available.
            </p>
            <p className="text-xs mt-1 text-default-500">
              <strong>Solution:</strong> Ensure your system has a proper keyring service installed
              (Windows Credential Manager, macOS Keychain, or Linux Secret Service).
            </p>
          </div>

          <div>
            <p className="font-medium text-danger-600">❌ Missing Refresh Token</p>
            <p>
              The refresh token is missing, which prevents automatic token renewal and will cause
              sync failures.
            </p>
            <p className="text-xs mt-1 text-default-500">
              <strong>Solution:</strong> Use the "Clear User Tokens" recovery action and log in
              again to refresh all authentication tokens.
            </p>
          </div>

          <div>
            <p className="font-medium text-warning-600">⚠️ Expired Access Token</p>
            <p>
              The access token has expired but should be automatically renewed if a valid refresh
              token is present.
            </p>
            <p className="text-xs mt-1 text-default-500">
              <strong>Solution:</strong> Try logging out and logging back in. If the issue persists,
              clear user tokens.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
