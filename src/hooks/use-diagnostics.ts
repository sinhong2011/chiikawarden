import { useCallback, useState } from "react";
import { getErrorMessage } from "@/lib/error-utils";
import type { KeyringBackendStatus, TokenDiagnosticResult } from "@/lib/tauri-commands";
import { commands } from "@/lib/tauri-commands";

interface DiagnosticState<T> {
  data: T | null;
  isLoading: boolean;
  error: string | null;
}

interface TestResult {
  operation: string;
  success: boolean;
  details?: string;
  timestamp: string;
}

interface RecoveryActionResult {
  success: boolean;
  message: string;
}

export function useDiagnostics() {
  // Keyring status state
  const [keyringStatus, setKeyringStatus] = useState<DiagnosticState<KeyringBackendStatus>>({
    data: null,
    isLoading: false,
    error: null,
  });

  // Token diagnostic state
  const [tokenDiagnostic, setTokenDiagnostic] = useState<DiagnosticState<TokenDiagnosticResult>>({
    data: null,
    isLoading: false,
    error: null,
  });

  // Test operations state
  const [testResults, setTestResults] = useState<TestResult[]>([]);
  const [isRunningTests, setIsRunningTests] = useState(false);
  const [testError, setTestError] = useState<string | null>(null);

  // Recovery actions state
  const [recoveryResult, setRecoveryResult] = useState<RecoveryActionResult | null>(null);
  const [isPerformingRecovery, setIsPerformingRecovery] = useState(false);

  // Check keyring backend status
  const checkKeyringStatus = useCallback(async () => {
    setKeyringStatus((prev) => ({ ...prev, isLoading: true, error: null }));

    try {
      const result = await commands.checkKeyringBackend();
      if (result.status === "ok") {
        setKeyringStatus({
          data: result.data,
          isLoading: false,
          error: null,
        });
      } else {
        setKeyringStatus({
          data: null,
          isLoading: false,
          error: getErrorMessage(result.error) || "Failed to check keyring status",
        });
      }
    } catch (err) {
      setKeyringStatus({
        data: null,
        isLoading: false,
        error: err instanceof Error ? err.message : "Unknown error occurred",
      });
    }
  }, []);

  // Run token diagnostic
  const runTokenDiagnostic = useCallback(async (userId: string) => {
    if (!userId.trim()) {
      setTokenDiagnostic({
        data: null,
        isLoading: false,
        error: "Please provide a user ID",
      });
      return;
    }

    setTokenDiagnostic((prev) => ({ ...prev, isLoading: true, error: null }));

    try {
      const result = await commands.diagnoseTokenStatus(userId);
      if (result.status === "ok") {
        setTokenDiagnostic({
          data: result.data,
          isLoading: false,
          error: null,
        });
      } else {
        setTokenDiagnostic({
          data: null,
          isLoading: false,
          error: getErrorMessage(result.error) || "Failed to diagnose token status",
        });
      }
    } catch (err) {
      setTokenDiagnostic({
        data: null,
        isLoading: false,
        error: err instanceof Error ? err.message : "Unknown error occurred",
      });
    }
  }, []);

  // Run test operations
  const runTestOperations = useCallback(async () => {
    setIsRunningTests(true);
    setTestError(null);
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
      setTestError(err instanceof Error ? err.message : "Unknown error occurred");
    } finally {
      setIsRunningTests(false);
    }
  }, []);

  // Clear test results
  const clearTestResults = useCallback(() => {
    setTestResults([]);
    setTestError(null);
  }, []);

  // Recovery actions
  const clearUserTokens = useCallback(async (userId: string) => {
    if (!userId.trim()) {
      setRecoveryResult({
        success: false,
        message: "Please provide a user ID",
      });
      return;
    }

    setIsPerformingRecovery(true);
    try {
      const result = await commands.clearUserTokens(userId);
      if (result.status === "ok") {
        setRecoveryResult({
          success: true,
          message: `Successfully cleared all tokens for user: ${userId}`,
        });
      } else {
        setRecoveryResult({
          success: false,
          message: getErrorMessage(result.error) || "Failed to clear user tokens",
        });
      }
    } catch (err) {
      setRecoveryResult({
        success: false,
        message: err instanceof Error ? err.message : "Unknown error occurred",
      });
    } finally {
      setIsPerformingRecovery(false);
    }
  }, []);

  const clearTestTokens = useCallback(async () => {
    setIsPerformingRecovery(true);
    try {
      const result = await commands.clearTestTokens("diagnostic_test");
      if (result.status === "ok") {
        setRecoveryResult({
          success: true,
          message: "Successfully cleared all test tokens",
        });
      } else {
        setRecoveryResult({
          success: false,
          message: getErrorMessage(result.error) || "Failed to clear test tokens",
        });
      }
    } catch (err) {
      setRecoveryResult({
        success: false,
        message: err instanceof Error ? err.message : "Unknown error occurred",
      });
    } finally {
      setIsPerformingRecovery(false);
    }
  }, []);

  const logoutUser = useCallback(async () => {
    setIsPerformingRecovery(true);
    try {
      const result = await commands.logout("current_user");
      if (result.status === "ok") {
        setRecoveryResult({
          success: true,
          message: "Successfully logged out. Please log in again.",
        });
      } else {
        setRecoveryResult({
          success: false,
          message: getErrorMessage(result.error) || "Failed to logout",
        });
      }
    } catch (err) {
      setRecoveryResult({
        success: false,
        message: err instanceof Error ? err.message : "Unknown error occurred",
      });
    } finally {
      setIsPerformingRecovery(false);
    }
  }, []);

  // Clear recovery result
  const clearRecoveryResult = useCallback(() => {
    setRecoveryResult(null);
  }, []);

  return {
    // Keyring status
    keyringStatus,
    checkKeyringStatus,

    // Token diagnostic
    tokenDiagnostic,
    runTokenDiagnostic,

    // Test operations
    testResults,
    isRunningTests,
    testError,
    runTestOperations,
    clearTestResults,

    // Recovery actions
    recoveryResult,
    isPerformingRecovery,
    clearUserTokens,
    clearTestTokens,
    logoutUser,
    clearRecoveryResult,
  };
}
