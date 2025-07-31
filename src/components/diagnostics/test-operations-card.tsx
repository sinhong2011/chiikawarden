import { Button } from "@heroui/button";
import { Card, CardBody, CardHeader } from "@heroui/card";
import { Chip } from "@heroui/chip";
import { Code } from "@heroui/code";
import { AlertCircle, CheckCircle, Play, TestTube, Trash2 } from "lucide-react";
import React, { useState } from "react";
import { commands } from "@/lib/tauri-commands";

interface TestResult {
  operation: string;
  success: boolean;
  details?: string;
  timestamp: string;
}

interface TestOperationsCardProps {
  className?: string;
}

export function TestOperationsCard({ className }: TestOperationsCardProps) {
  const [testResults, setTestResults] = useState<TestResult[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const runTokenTests = async () => {
    setIsRunning(true);
    setError(null);
    setTestResults([]);

    const results: TestResult[] = [];
    const testUserId = `diagnostic_test_${Date.now()}`;
    const testToken = `test_refresh_token_${Date.now()}`;

    try {
      // Test 1: Store test token
      try {
        await commands.storeTestRefreshToken(testUserId, testToken);
        results.push({
          operation: "Store Test Token",
          success: true,
          details: "Successfully stored test refresh token",
          timestamp: new Date().toISOString(),
        });
      } catch (err) {
        results.push({
          operation: "Store Test Token",
          success: false,
          details: err instanceof Error ? err.message : "Unknown error",
          timestamp: new Date().toISOString(),
        });
      }

      // Test 2: Retrieve test token
      try {
        const result = await commands.retrieveTestRefreshToken(testUserId);
        if (result.status === "ok" && result.data === testToken) {
          results.push({
            operation: "Retrieve Test Token",
            success: true,
            details: "Successfully retrieved and verified test token",
            timestamp: new Date().toISOString(),
          });
        } else {
          results.push({
            operation: "Retrieve Test Token",
            success: false,
            details: "Token mismatch or retrieval failed",
            timestamp: new Date().toISOString(),
          });
        }
      } catch (err) {
        results.push({
          operation: "Retrieve Test Token",
          success: false,
          details: err instanceof Error ? err.message : "Unknown error",
          timestamp: new Date().toISOString(),
        });
      }

      // Test 3: Clean up test tokens
      try {
        await commands.clearTestTokens(testUserId);
        results.push({
          operation: "Clear Test Tokens",
          success: true,
          details: "Successfully cleared test tokens",
          timestamp: new Date().toISOString(),
        });
      } catch (err) {
        results.push({
          operation: "Clear Test Tokens",
          success: false,
          details: err instanceof Error ? err.message : "Unknown error",
          timestamp: new Date().toISOString(),
        });
      }

      setTestResults(results);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error occurred");
    } finally {
      setIsRunning(false);
    }
  };

  const clearResults = () => {
    setTestResults([]);
    setError(null);
  };

  const getOverallStatus = () => {
    if (testResults.length === 0) return { color: "default" as const, text: "Not tested" };

    const allPassed = testResults.every((result) => result.success);
    const anyFailed = testResults.some((result) => !result.success);

    if (allPassed) {
      return { color: "success" as const, text: "All tests passed" };
    } else if (anyFailed) {
      return { color: "danger" as const, text: "Some tests failed" };
    } else {
      return { color: "warning" as const, text: "Mixed results" };
    }
  };

  const status = getOverallStatus();

  return (
    <Card className={className}>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between w-full">
          <div className="flex items-center gap-3">
            <TestTube className="w-5 h-5 text-primary" />
            <div>
              <h3 className="text-lg font-semibold">Test Operations</h3>
              <p className="text-sm text-muted-foreground">
                Test keyring storage and retrieval operations
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Chip color={status.color} variant="flat" size="sm">
              {status.text}
            </Chip>
            <Button
              color="primary"
              variant="flat"
              size="sm"
              startContent={<Play className="w-4 h-4" />}
              onPress={runTokenTests}
              isDisabled={isRunning}
              isLoading={isRunning}
            >
              {isRunning ? "Running Tests..." : "Run Tests"}
            </Button>
            {testResults.length > 0 && (
              <Button
                color="default"
                variant="flat"
                size="sm"
                startContent={<Trash2 className="w-4 h-4" />}
                onPress={clearResults}
                isDisabled={isRunning}
              >
                Clear
              </Button>
            )}
          </div>
        </div>
      </CardHeader>

      <CardBody className="pt-0">
        {error && (
          <div className="mb-4 p-3 bg-danger-50 border border-danger-200 rounded-lg">
            <div className="flex items-center gap-2">
              <AlertCircle className="w-4 h-4 text-danger" />
              <span className="text-sm text-danger-700">{error}</span>
            </div>
          </div>
        )}

        {testResults.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium">Test Results</h4>
              <span className="text-xs text-muted-foreground">
                {testResults.filter((r) => r.success).length} / {testResults.length} passed
              </span>
            </div>

            {testResults.map((result, index) => (
              <div
                key={index}
                className={`p-3 rounded-lg border ${
                  result.success
                    ? "bg-success-50 border-success-200"
                    : "bg-danger-50 border-danger-200"
                }`}
              >
                <div className="flex items-start gap-3">
                  {result.success ? (
                    <CheckCircle className="w-4 h-4 text-success-600 mt-0.5 flex-shrink-0" />
                  ) : (
                    <AlertCircle className="w-4 h-4 text-danger-600 mt-0.5 flex-shrink-0" />
                  )}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between mb-1">
                      <p
                        className={`text-sm font-medium ${
                          result.success ? "text-success-800" : "text-danger-800"
                        }`}
                      >
                        {result.operation}
                      </p>
                      <Chip color={result.success ? "success" : "danger"} variant="flat" size="sm">
                        {result.success ? "PASS" : "FAIL"}
                      </Chip>
                    </div>
                    <p
                      className={`text-sm ${
                        result.success ? "text-success-700" : "text-danger-700"
                      }`}
                    >
                      {result.details}
                    </p>
                    <p className="text-xs text-muted-foreground mt-1">
                      {new Date(result.timestamp).toLocaleTimeString()}
                    </p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        {testResults.length === 0 && !error && !isRunning && (
          <div className="text-center py-8 text-muted-foreground">
            <TestTube className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="text-sm mb-2">Test keyring operations</p>
            <p className="text-xs">This will test storing, retrieving, and clearing test tokens</p>
          </div>
        )}

        {isRunning && (
          <div className="text-center py-8">
            <div className="animate-spin w-8 h-8 border-2 border-primary border-t-transparent rounded-full mx-auto mb-3" />
            <p className="text-sm text-muted-foreground">Running keyring tests...</p>
          </div>
        )}

        {/* Test Information */}
        <div className="mt-4 p-3 bg-default-50 rounded-lg">
          <p className="text-xs text-default-600 mb-2">
            <span className="font-medium">Test Operations:</span>
          </p>
          <ul className="text-xs text-default-600 space-y-1">
            <li>• Store a test refresh token in the keyring</li>
            <li>• Retrieve the test token and verify it matches</li>
            <li>• Clean up test data from the keyring</li>
          </ul>
        </div>
      </CardBody>
    </Card>
  );
}
