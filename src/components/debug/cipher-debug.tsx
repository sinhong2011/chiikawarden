import { Accordion, AccordionItem } from "@heroui/accordion";
import { Button } from "@heroui/button";
import { Card, CardBody, CardHeader } from "@heroui/card";
import { Chip } from "@heroui/chip";
import { Code } from "@heroui/code";
import { Input } from "@heroui/input";
import { AlertCircle, Bug, CheckCircle, Key, RefreshCw, Search } from "lucide-react";
import { useState } from "react";
import { commands } from "@/lib/tauri-commands";
import { useAuthStore } from "@/stores/auth.store";

interface CipherDebugProps {
  className?: string;
}

interface DebugResult {
  timestamp: string;
  userId: string;
  cipherId?: string;
  success: boolean;
  output: string;
  error?: string;
}

export function CipherDebug({ className }: CipherDebugProps) {
  const authStore = useAuthStore();
  const [isRunning, setIsRunning] = useState(false);
  const [results, setResults] = useState<DebugResult[]>([]);
  const [customUserId, setCustomUserId] = useState("");
  const [customCipherId, setCustomCipherId] = useState("90a3b799-9194-4468-b75b-d9f7c3a267cf");

  // Default problematic cipher ID
  const PROBLEMATIC_CIPHER_ID = "90a3b799-9194-4468-b75b-d9f7c3a267cf";
  const PROBLEMATIC_USER_ID = "a7d33ad5-a83e-40a2-84ff-78c85ea64c4b";

  const runCipherDebug = async (
    userId?: string,
    cipherId?: string,
    debugType: "database" | "api" | "raw" | "pipeline" | "decryption" = "database"
  ) => {
    const targetUserId = userId || customUserId || authStore.userId || PROBLEMATIC_USER_ID;
    const targetCipherId = cipherId || customCipherId || PROBLEMATIC_CIPHER_ID;

    if (!targetUserId) {
      console.error("No user ID available for cipher debug");
      return;
    }

    setIsRunning(true);

    try {
      console.log(
        `[CipherDebug] Running ${debugType} debug for user: ${targetUserId}, cipher: ${targetCipherId}`
      );

      // Choose debug type
      let result: { status: "ok"; data: string } | { status: "error"; error: unknown };
      switch (debugType) {
        case "api":
          result = await commands.debugFetchCiphersFromApi(targetUserId);
          break;
        case "raw":
          result = await commands.debugCipherFieldInspection(targetUserId, targetCipherId);
          break;
        case "decryption":
          result = await commands.debugCipherDecryptionSteps(targetUserId, targetCipherId);
          break;
        case "pipeline":
          result = await commands.debugCipherParsingPipeline(targetUserId, targetCipherId);
          break;
        default:
          result = await commands.debugCipherDecryption(targetUserId);
          break;
      }

      const debugResult: DebugResult = {
        timestamp: new Date().toISOString(),
        userId: targetUserId,
        cipherId: targetCipherId,
        success: result.status === "ok",
        output: result.status === "ok" ? result.data : "",
        error: result.status === "error" ? String(result.error) : undefined,
      };

      setResults((prev) => [debugResult, ...prev]);

      if (result.status === "ok") {
        console.log(`[CipherDebug] ${debugType} debug completed successfully:`, result.data);
      } else {
        console.error(`[CipherDebug] ${debugType} debug failed:`, result.error);
      }
    } catch (error) {
      console.error("[CipherDebug] Debug process failed:", error);

      const debugResult: DebugResult = {
        timestamp: new Date().toISOString(),
        userId: targetUserId,
        cipherId: targetCipherId,
        success: false,
        output: "",
        error: error instanceof Error ? error.message : String(error),
      };

      setResults((prev) => [debugResult, ...prev]);
    } finally {
      setIsRunning(false);
    }
  };

  const runQuickDebug = () => {
    runCipherDebug(PROBLEMATIC_USER_ID, PROBLEMATIC_CIPHER_ID, "database");
  };

  const runQuickApiDebug = () => {
    runCipherDebug(PROBLEMATIC_USER_ID, PROBLEMATIC_CIPHER_ID, "api");
  };

  const runQuickRawDebug = () => {
    runCipherDebug(PROBLEMATIC_USER_ID, PROBLEMATIC_CIPHER_ID, "raw");
  };

  const runQuickPipelineDebug = () => {
    runCipherDebug(PROBLEMATIC_USER_ID, PROBLEMATIC_CIPHER_ID, "pipeline");
  };

  const runFieldInspection = async () => {
    const targetUserId = customUserId || authStore.userId || PROBLEMATIC_USER_ID;
    const targetCipherId = customCipherId || PROBLEMATIC_CIPHER_ID;

    if (!targetUserId) {
      console.error("No user ID available for field inspection");
      return;
    }

    setIsRunning(true);
    try {
      const response = await commands.debugCipherFieldInspection(targetUserId, targetCipherId);

      const result: DebugResult = {
        timestamp: new Date().toISOString(),
        userId: targetUserId,
        cipherId: targetCipherId,
        success: response.status === "ok",
        output: response.status === "ok" ? response.data : "",
        error: response.status === "error" ? response.error : undefined,
      };

      setResults((prev) => [result, ...prev]);
    } catch (error) {
      const result: DebugResult = {
        timestamp: new Date().toISOString(),
        userId: targetUserId,
        cipherId: targetCipherId,
        success: false,
        output: "",
        error: error instanceof Error ? error.message : String(error),
      };

      setResults((prev) => [result, ...prev]);
    } finally {
      setIsRunning(false);
    }
  };

  const runCustomDebug = () => {
    runCipherDebug(customUserId, customCipherId, "database");
  };

  const runCustomApiDebug = () => {
    runCipherDebug(customUserId, customCipherId, "api");
  };

  const runCustomRawDebug = () => {
    runCipherDebug(customUserId, customCipherId, "raw");
  };

  const runCustomPipelineDebug = () => {
    runCipherDebug(customUserId, customCipherId, "pipeline");
  };

  const runDecryptionSteps = () => {
    runCipherDebug(customUserId, customCipherId, "decryption");
  };

  const clearResults = () => {
    setResults([]);
  };

  const formatTimestamp = (timestamp: string) => {
    return new Date(timestamp).toLocaleString();
  };

  return (
    <Card className={className}>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between w-full">
          <div>
            <h3 className="text-lg font-semibold flex items-center gap-2">
              <Bug className="w-5 h-5" />
              Cipher Decryption Debug
            </h3>
            <p className="text-sm text-muted-foreground">
              Debug cipher decryption issues by testing API vs database data sources, view raw API
              responses, or test the new two-step parsing pipeline
            </p>
          </div>
          <div className="flex gap-2">
            <Button
              color="danger"
              variant="flat"
              size="sm"
              onPress={clearResults}
              isDisabled={results.length === 0}
            >
              Clear
            </Button>
            <Button
              color="primary"
              variant="flat"
              startContent={
                isRunning ? (
                  <RefreshCw className="w-4 h-4 animate-spin" />
                ) : (
                  <Bug className="w-4 h-4" />
                )
              }
              onPress={runQuickDebug}
              isDisabled={isRunning}
              isLoading={isRunning}
            >
              {isRunning ? "Running..." : "Database Debug"}
            </Button>
            <Button
              color="secondary"
              variant="flat"
              startContent={
                isRunning ? (
                  <RefreshCw className="w-4 h-4 animate-spin" />
                ) : (
                  <Search className="w-4 h-4" />
                )
              }
              onPress={runQuickApiDebug}
              isDisabled={isRunning}
              isLoading={isRunning}
            >
              {isRunning ? "Running..." : "API Debug"}
            </Button>
            <Button
              color="warning"
              variant="flat"
              startContent={
                isRunning ? (
                  <RefreshCw className="w-4 h-4 animate-spin" />
                ) : (
                  <AlertCircle className="w-4 h-4" />
                )
              }
              onPress={runQuickRawDebug}
              isDisabled={isRunning}
              isLoading={isRunning}
            >
              {isRunning ? "Running..." : "Raw Response"}
            </Button>
            <Button
              color="success"
              variant="flat"
              startContent={
                isRunning ? (
                  <RefreshCw className="w-4 h-4 animate-spin" />
                ) : (
                  <CheckCircle className="w-4 h-4" />
                )
              }
              onPress={runQuickPipelineDebug}
              isDisabled={isRunning}
              isLoading={isRunning}
            >
              {isRunning ? "Running..." : "New Pipeline"}
            </Button>
          </div>
        </div>
      </CardHeader>

      <CardBody className="pt-0 space-y-4">
        {/* Quick Debug Section */}
        <div className="p-3 bg-orange-50 dark:bg-orange-950/20 rounded-lg border border-orange-200 dark:border-orange-800">
          <div className="flex items-start gap-3">
            <AlertCircle className="w-5 h-5 text-orange-600 dark:text-orange-400 mt-0.5 flex-shrink-0" />
            <div className="flex-1">
              <h4 className="font-medium text-orange-800 dark:text-orange-200 mb-1">
                Known Issue Debug
              </h4>
              <p className="text-sm text-orange-700 dark:text-orange-300 mb-2">
                Debug the known cipher decryption issue where cipher ID{" "}
                <Code size="sm" className="text-xs">
                  {PROBLEMATIC_CIPHER_ID}
                </Code>{" "}
                shows "" instead of proper encrypted data.
              </p>
              <p className="text-xs text-orange-600 dark:text-orange-400">
                Use "Database Debug" to test local data, "API Debug" to fetch from server, "Raw
                Response" to see unprocessed API data, or "New Pipeline" to test the improved
                two-step parsing with fallback handling.
              </p>
            </div>
          </div>
        </div>

        {/* Custom Debug Section */}
        <div className="space-y-3">
          <h4 className="font-medium">Custom Debug</h4>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <Input
              label="User ID"
              placeholder={authStore.userId || PROBLEMATIC_USER_ID}
              value={customUserId}
              onValueChange={setCustomUserId}
              size="sm"
              description="Leave empty to use current user"
            />
            <Input
              label="Cipher ID"
              placeholder={PROBLEMATIC_CIPHER_ID}
              value={customCipherId}
              onValueChange={setCustomCipherId}
              size="sm"
              description="Specific cipher to debug"
            />
          </div>
          <div className="flex gap-2">
            <Button
              color="secondary"
              variant="flat"
              startContent={<Search className="w-4 h-4" />}
              onPress={runCustomDebug}
              isDisabled={isRunning}
              size="sm"
            >
              Database Debug
            </Button>
            <Button
              color="primary"
              variant="flat"
              startContent={<RefreshCw className="w-4 h-4" />}
              onPress={runCustomApiDebug}
              isDisabled={isRunning}
              size="sm"
            >
              API Debug
            </Button>
            <Button
              color="warning"
              variant="flat"
              startContent={<AlertCircle className="w-4 h-4" />}
              onPress={runCustomRawDebug}
              isDisabled={isRunning}
              size="sm"
            >
              Raw Response
            </Button>
            <Button
              color="success"
              variant="flat"
              startContent={<CheckCircle className="w-4 h-4" />}
              onPress={runCustomPipelineDebug}
              isDisabled={isRunning}
              size="sm"
            >
              New Pipeline
            </Button>
            <Button
              color="warning"
              variant="flat"
              startContent={<AlertCircle className="w-4 h-4" />}
              onPress={runFieldInspection}
              isDisabled={isRunning}
              size="sm"
            >
              Field Inspection
            </Button>
            <Button
              color="danger"
              variant="flat"
              startContent={<Key className="w-4 h-4" />}
              onPress={runDecryptionSteps}
              isDisabled={isRunning}
              size="sm"
            >
              Decryption Steps
            </Button>
          </div>
        </div>

        {/* Results Section */}
        {results.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h4 className="font-medium">Debug Results</h4>
              <Chip size="sm" variant="flat">
                {results.length} result{results.length !== 1 ? "s" : ""}
              </Chip>
            </div>

            <Accordion variant="splitted" selectionMode="multiple">
              {results.map((result, index) => (
                <AccordionItem
                  key={`${result.timestamp}-${result.userId}`}
                  title={
                    <div className="flex items-center justify-between w-full">
                      <div className="flex items-center gap-2">
                        {result.success ? (
                          <CheckCircle className="w-4 h-4 text-success" />
                        ) : (
                          <AlertCircle className="w-4 h-4 text-danger" />
                        )}
                        <span className="font-medium">Debug #{results.length - index}</span>
                      </div>
                      <div className="flex items-center gap-2 text-sm text-muted-foreground">
                        <span>{formatTimestamp(result.timestamp)}</span>
                        <Chip
                          size="sm"
                          color={result.success ? "success" : "danger"}
                          variant="flat"
                        >
                          {result.success ? "Success" : "Failed"}
                        </Chip>
                      </div>
                    </div>
                  }
                >
                  <div className="space-y-3">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                      <div>
                        <span className="font-medium">User ID:</span>
                        <Code size="sm" className="ml-2">
                          {result.userId}
                        </Code>
                      </div>
                      {result.cipherId && (
                        <div>
                          <span className="font-medium">Cipher ID:</span>
                          <Code size="sm" className="ml-2">
                            {result.cipherId}
                          </Code>
                        </div>
                      )}
                    </div>

                    {result.error && (
                      <div>
                        <span className="font-medium text-danger">Error:</span>
                        <Code color="danger" className="mt-1 block">
                          {result.error}
                        </Code>
                      </div>
                    )}

                    {result.output && (
                      <div>
                        <span className="font-medium">Debug Output:</span>
                        <div className="mt-2 bg-muted/50 border border-border rounded-lg p-3">
                          <pre className="text-xs font-mono overflow-x-auto whitespace-pre-wrap max-h-96 overflow-y-auto">
                            {result.output}
                          </pre>
                        </div>
                      </div>
                    )}
                  </div>
                </AccordionItem>
              ))}
            </Accordion>
          </div>
        )}

        {/* Empty State */}
        {results.length === 0 && !isRunning && (
          <div className="text-center py-8">
            <Bug className="w-12 h-12 mx-auto mb-3 text-muted-foreground/50" />
            <p className="text-muted-foreground mb-4">
              No debug results yet. Run a debug session to analyze cipher decryption issues.
            </p>
            <p className="text-sm text-muted-foreground">
              Use "Database Debug" to test local data, "API Debug" to fetch from server, "Raw
              Response" to see unprocessed API data, or "Custom Debug" to test specific cases.
            </p>
          </div>
        )}

        {/* Loading State */}
        {isRunning && (
          <div className="text-center py-8">
            <RefreshCw className="w-8 h-8 animate-spin mx-auto mb-2 text-primary" />
            <p className="text-muted-foreground">Running cipher decryption debug...</p>
            <p className="text-sm text-muted-foreground mt-1">
              This may take a few moments to analyze data sources and compare results.
            </p>
          </div>
        )}
      </CardBody>
    </Card>
  );
}
