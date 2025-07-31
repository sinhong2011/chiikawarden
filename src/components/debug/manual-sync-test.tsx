import { Button } from "@heroui/button";
import { Card, CardBody, CardHeader } from "@heroui/card";
import { Chip } from "@heroui/chip";
import { RefreshCw, Database, Server, Eye } from "lucide-react";
import React from "react";
import { useAuthStore } from "@/stores/auth.store";
import { syncService } from "@/services/sync.service";
import { vaultService } from "@/services/vault.service";
import { commands } from "@/lib/tauri-commands";

interface ManualSyncTestProps {
  className?: string;
}

interface TestResult {
  step: string;
  success: boolean;
  data?: any;
  error?: string;
  timestamp: Date;
}

export function ManualSyncTest({ className }: ManualSyncTestProps) {
  const authStore = useAuthStore();
  const [isRunning, setIsRunning] = React.useState(false);
  const [results, setResults] = React.useState<TestResult[]>([]);

  const formatError = (error: any): string => {
    if (typeof error === 'string') {
      return error;
    }
    if (error instanceof Error) {
      return `${error.name}: ${error.message}`;
    }
    if (error && typeof error === 'object') {
      if (error.message) {
        return error.message;
      }
      return JSON.stringify(error, null, 2);
    }
    return String(error);
  };

  const addResult = (step: string, success: boolean, data?: any, error?: string) => {
    const result: TestResult = {
      step,
      success,
      data,
      error,
      timestamp: new Date(),
    };
    setResults(prev => [...prev, result]);
    console.log(`[MANUAL SYNC TEST] ${step}:`, success ? "✅" : "❌", data || error);
  };

  const runManualTest = async () => {
    if (!authStore.userId) {
      console.error("No user ID available");
      return;
    }

    setIsRunning(true);
    setResults([]);

    try {
      // Step 1: Check current vault state
      console.log("🔍 Checking current vault state...");
      try {
        const currentCiphers = await vaultService.getAllCiphers(authStore.userId);
        addResult("Current Vault State", true, {
          cipherCount: currentCiphers.length,
          cipherNames: currentCiphers.map(c => c.name)
        });
      } catch (error) {
        addResult("Current Vault State", false, null, `Error: ${error}`);
      }

      // Step 2: Check sync status
      console.log("📊 Checking sync status...");
      try {
        const syncStatus = await syncService.getSyncStatus(authStore.userId);
        addResult("Sync Status", true, syncStatus);
      } catch (error) {
        addResult("Sync Status", false, null, `Error: ${formatError(error)}`);
      }

      // Step 3: Force vault sync
      console.log("🔄 Forcing vault sync...");
      try {
        const syncResult = await syncService.syncVault(authStore.userId);
        addResult("Force Sync", true, syncResult);
      } catch (error) {
        addResult("Force Sync", false, null, `Error: ${formatError(error)}`);
      }

      // Step 4: Wait and check vault state again
      console.log("⏳ Waiting 2 seconds then checking vault state...");
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      try {
        const newCiphers = await vaultService.getAllCiphers(authStore.userId);
        addResult("Post-Sync Vault State", true, {
          cipherCount: newCiphers.length,
          cipherNames: newCiphers.map(c => c.name),
          cipherDetails: newCiphers.map(c => ({
            id: c.id,
            name: c.name,
            type: c.cipher_type,
            hasLogin: !!c.login,
            hasNotes: !!c.notes
          }))
        });
      } catch (error) {
        addResult("Post-Sync Vault State", false, null, `Error: ${error}`);
      }

      // Step 5: Check database health
      console.log("🏥 Checking database health...");
      try {
        const dbHealth = await commands.getDatabaseHealth();
        if (dbHealth.status === "ok") {
          addResult("Database Health", true, dbHealth.data);
        } else {
          addResult("Database Health", false, null, typeof dbHealth.error === 'string' ? dbHealth.error : JSON.stringify(dbHealth.error));
        }
      } catch (error) {
        addResult("Database Health", false, null, `Error: ${error}`);
      }

    } catch (error) {
      addResult("Manual Test", false, null, `Unexpected error: ${error}`);
    } finally {
      setIsRunning(false);
    }
  };

  const clearResults = () => {
    setResults([]);
  };

  return (
    <Card className={className}>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between w-full">
          <div>
            <h3 className="text-lg font-semibold">Manual Sync Test</h3>
            <p className="text-sm text-muted-foreground">
              Manually test vault synchronization step by step
            </p>
          </div>
          <div className="flex gap-2">
            <Button
              size="sm"
              variant="flat"
              onPress={clearResults}
              isDisabled={results.length === 0}
            >
              Clear
            </Button>
            <Button
              color="primary"
              variant="flat"
              startContent={isRunning ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Eye className="w-4 h-4" />}
              onPress={runManualTest}
              isDisabled={isRunning || !authStore.userId}
              isLoading={isRunning}
            >
              {isRunning ? "Testing..." : "Run Test"}
            </Button>
          </div>
        </div>
      </CardHeader>

      <CardBody className="pt-0">
        {!authStore.userId && (
          <div className="text-center py-4">
            <p className="text-muted-foreground">Please log in to run manual sync test</p>
          </div>
        )}

        {results.length > 0 && (
          <div className="space-y-3">
            {results.map((result, index) => (
              <div
                key={index}
                className={`p-3 rounded-lg border-l-4 ${
                  result.success ? "border-l-success bg-success/5" : "border-l-danger bg-danger/5"
                }`}
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{result.step}</span>
                    <Chip
                      size="sm"
                      color={result.success ? "success" : "danger"}
                      variant="flat"
                    >
                      {result.success ? "Success" : "Failed"}
                    </Chip>
                  </div>
                  <span className="text-xs text-muted-foreground">
                    {result.timestamp.toLocaleTimeString()}
                  </span>
                </div>

                {result.error && (
                  <div className="text-sm text-danger mb-2">
                    <strong>Error:</strong> {result.error}
                  </div>
                )}

                {result.data && (
                  <details className="text-sm">
                    <summary className="cursor-pointer text-muted-foreground hover:text-foreground">
                      View Data
                    </summary>
                    <pre className="mt-2 p-2 bg-muted/50 rounded text-xs overflow-x-auto">
                      {JSON.stringify(result.data, null, 2)}
                    </pre>
                  </details>
                )}
              </div>
            ))}
          </div>
        )}

        {results.length === 0 && !isRunning && (
          <div className="text-center py-8">
            <p className="text-muted-foreground">Click "Run Test" to start manual sync testing</p>
          </div>
        )}

        {isRunning && (
          <div className="text-center py-8">
            <RefreshCw className="w-8 h-8 animate-spin mx-auto mb-2 text-primary" />
            <p className="text-muted-foreground">Running manual sync test...</p>
          </div>
        )}
      </CardBody>
    </Card>
  );
}
