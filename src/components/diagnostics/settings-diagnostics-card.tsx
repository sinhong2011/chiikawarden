import { Accordion, AccordionItem } from "@heroui/accordion";
import { Button } from "@heroui/button";
import { Card, CardBody, CardHeader } from "@heroui/card";
import { Chip } from "@heroui/chip";
import { AlertCircle, CheckCircle, LogOut, RefreshCw, Settings } from "lucide-react";
import React from "react";
import { commands } from "@/lib/tauri-commands";
import { useAuthStore } from "@/stores/auth.store";
import { type DiagnosticResult, SettingsDiagnostics, DiagnosticCategory } from "../../diagnostics/settings-diagnostics";

interface SettingsDiagnosticsCardProps {
  className?: string;
}

export function SettingsDiagnosticsCard({ className }: SettingsDiagnosticsCardProps) {
  const authStore = useAuthStore();
  const [isRunning, setIsRunning] = React.useState(false);
  const [results, setResults] = React.useState<DiagnosticResult[]>([]);
  const [lastRun, setLastRun] = React.useState<Date | null>(null);
  const [isRelogging, setIsRelogging] = React.useState(false);

  const runDiagnostics = async () => {
    if (!authStore.userId) {
      console.error("No user ID available for diagnostics");
      return;
    }

    setIsRunning(true);
    setResults([]);

    try {
      const settingsDiagnostics = new SettingsDiagnostics();
      const diagnosticResults = await settingsDiagnostics.runDiagnostics(authStore.userId);
      setResults(diagnosticResults);
      setLastRun(new Date());
    } catch (error) {
      console.error("Diagnostics process failed:", error);
    } finally {
      setIsRunning(false);
    }
  };

  const handleRelogin = async () => {
    if (!authStore.userId) {
      console.error("No user ID available for re-login");
      return;
    }

    setIsRelogging(true);
    try {
      // Force logout to clear any cached tokens
      await commands.logout(authStore.userId);

      // Clear auth store state
      authStore.logout();

      console.log("🔄 Logged out successfully. Please log in again to refresh access tokens.");

      // Note: The user will need to manually log in again through the UI
      // This ensures fresh tokens are properly stored in the keyring

    } catch (error) {
      console.error("Failed to logout:", error);
    } finally {
      setIsRelogging(false);
    }
  };

  const getStatusIcon = (success: boolean) => {
    return success ? (
      <CheckCircle className="w-4 h-4 text-success" />
    ) : (
      <AlertCircle className="w-4 h-4 text-danger" />
    );
  };

  const getStatusColor = (success: boolean) => {
    return success ? "success" : "danger";
  };

  const getCategoryColor = (category: DiagnosticCategory) => {
    switch (category) {
      case DiagnosticCategory.SETTINGS:
        return "primary";
      case DiagnosticCategory.AUTHENTICATION:
        return "secondary";
      case DiagnosticCategory.DATABASE:
        return "success";
      case DiagnosticCategory.NETWORK:
        return "warning";
      case DiagnosticCategory.SYSTEM:
        return "default";
      case DiagnosticCategory.VAULT:
        return "danger";
      default:
        return "default";
    }
  };

  const successCount = results.filter(r => r.success).length;
  const totalCount = results.length;
  const successRate = totalCount > 0 ? Math.round((successCount / totalCount) * 100) : 0;

  return (
    <Card className={className}>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between w-full">
          <div>
            <h3 className="text-lg font-semibold">Settings Diagnostics</h3>
            <p className="text-sm text-muted-foreground">
              Comprehensive diagnostics for application settings, authentication, and system health
            </p>
          </div>
          <div className="flex gap-2">
            <Button
              color="primary"
              variant="flat"
              startContent={
                isRunning ? (
                  <RefreshCw className="w-4 h-4 animate-spin" />
                ) : (
                  <Settings className="w-4 h-4" />
                )
              }
              onPress={runDiagnostics}
              isDisabled={isRunning || !authStore.userId}
              isLoading={isRunning}
            >
              {isRunning ? "Running..." : "Run Diagnostics"}
            </Button>

            <Button
              color="warning"
              variant="bordered"
              size="sm"
              startContent={
                isRelogging ? (
                  <RefreshCw className="w-4 h-4 animate-spin" />
                ) : (
                  <LogOut className="w-4 h-4" />
                )
              }
              onPress={handleRelogin}
              isDisabled={isRelogging || !authStore.userId}
              isLoading={isRelogging}
            >
              {isRelogging ? "Logging out..." : "Re-login"}
            </Button>
          </div>
        </div>
      </CardHeader>

      <CardBody className="pt-0">
        {!authStore.userId && (
          <div className="text-center py-4">
            <p className="text-muted-foreground">Please log in to run settings diagnostics</p>
          </div>
        )}

        {authStore.userId && results.length === 0 && (
          <div className="mb-4 p-3 bg-blue-50 dark:bg-blue-950/20 rounded-lg border border-blue-200 dark:border-blue-800">
            <p className="text-sm text-blue-700 dark:text-blue-300">
              <strong>💡 Tip:</strong> This diagnostic tool checks settings storage, authentication
              tokens, database health, and system configuration. Use the <strong>Re-login</strong>{" "}
              button if authentication issues are detected.
            </p>
          </div>
        )}

        {lastRun && (
          <div className="mb-4">
            <div className="flex items-center gap-2 mb-2">
              <span className="text-sm font-medium">Last Run:</span>
              <span className="text-sm text-muted-foreground">{lastRun.toLocaleString()}</span>
              <Chip
                size="sm"
                color={successRate === 100 ? "success" : successRate > 50 ? "warning" : "danger"}
                variant="flat"
              >
                {successCount}/{totalCount} ({successRate}%)
              </Chip>
            </div>
          </div>
        )}

        {results.length > 0 && (
          <Accordion variant="splitted" selectionMode="multiple">
            {results.map((result) => (
              <AccordionItem
                key={`${result.step}-${result.timestamp}`}
                aria-label={result.step}
                title={
                  <div className="flex items-center gap-2">
                    {getStatusIcon(result.success)}
                    <span className="font-medium">{result.step}</span>
                    <Chip
                      size="sm"
                      color={getStatusColor(result.success)}
                      variant="flat"
                    >
                      {result.success ? "Success" : "Failed"}
                    </Chip>
                    <Chip
                      size="sm"
                      color={getCategoryColor(result.category)}
                      variant="bordered"
                    >
                      {result.category}
                    </Chip>
                  </div>
                }
                className={`border-l-4 ${
                  result.success ? "border-l-success" : "border-l-danger"
                }`}
              >
                <div className="space-y-3">
                  <div>
                    <span className="text-xs text-muted-foreground">
                      {new Date(result.timestamp).toLocaleTimeString()}
                    </span>
                  </div>

                  {result.error && (
                    <div className="bg-danger/10 border border-danger/20 rounded-lg p-3">
                      <h4 className="text-sm font-medium text-danger mb-1">Error</h4>
                      <p className="text-sm text-danger/80">{result.error}</p>
                    </div>
                  )}

                  {result.data && (
                    <div className="bg-muted/50 border border-border rounded-lg p-3">
                      <h4 className="text-sm font-medium mb-2">Data</h4>
                      <pre className="text-xs overflow-x-auto">
                        {JSON.stringify(result.data, null, 2)}
                      </pre>
                    </div>
                  )}
                </div>
              </AccordionItem>
            ))}
          </Accordion>
        )}

        {results.length === 0 && !isRunning && (
          <div className="text-center py-8">
            <p className="text-muted-foreground">
              Click "Run Diagnostics" to start comprehensive settings diagnostics
            </p>
          </div>
        )}

        {isRunning && (
          <div className="text-center py-8">
            <RefreshCw className="w-8 h-8 animate-spin mx-auto mb-2 text-primary" />
            <p className="text-muted-foreground">Running comprehensive settings diagnostics...</p>
          </div>
        )}
      </CardBody>
    </Card>
  );
}
