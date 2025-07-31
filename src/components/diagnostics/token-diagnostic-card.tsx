import { Button } from "@heroui/button";
import { Card, CardBody, CardHeader } from "@heroui/card";
import { Chip } from "@heroui/chip";
import { Input } from "@heroui/input";
import { AlertCircle, CheckCircle, Key, RefreshCw, User } from "lucide-react";
import React, { useState } from "react";
import { getErrorMessage } from "@/lib/error-utils";
import type { TokenDiagnosticResult } from "@/lib/tauri-commands";
import { commands } from "@/lib/tauri-commands";
import { useAuthStore } from "@/stores/auth.store";

interface TokenDiagnosticCardProps {
  className?: string;
}

export function TokenDiagnosticCard({ className }: TokenDiagnosticCardProps) {
  const authStore = useAuthStore();
  const [customUserId, setCustomUserId] = useState("");
  const [useCustomUserId, setUseCustomUserId] = useState(false);
  const [diagnostic, setDiagnostic] = useState<TokenDiagnosticResult | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const getUserId = () => {
    return useCustomUserId ? customUserId : authStore.userId || "";
  };

  const runDiagnostic = async () => {
    const userId = getUserId();
    if (!userId.trim()) {
      setError("Please provide a user ID");
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const result = await commands.diagnoseTokenStatus(userId);
      if (result.status === "ok") {
        setDiagnostic(result.data);
      } else {
        setError(getErrorMessage(result.error) || "Failed to diagnose token status");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error occurred");
    } finally {
      setIsLoading(false);
    }
  };

  const getOverallStatus = () => {
    if (!diagnostic)
      return {
        icon: <Key className="w-5 h-5 text-default-400" />,
        color: "default" as const,
        text: "Not checked",
      };

    const hasIssues =
      !diagnostic.access_token_present ||
      !diagnostic.refresh_token_present ||
      diagnostic.access_token_expired === true;

    if (hasIssues) {
      return {
        icon: <AlertCircle className="w-5 h-5 text-danger" />,
        color: "danger" as const,
        text: "Issues found",
      };
    } else {
      return {
        icon: <CheckCircle className="w-5 h-5 text-success" />,
        color: "success" as const,
        text: "Healthy",
      };
    }
  };

  const status = getOverallStatus();

  return (
    <Card className={className}>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between w-full">
          <div className="flex items-center gap-3">
            {status.icon}
            <div>
              <h3 className="text-lg font-semibold">Token Diagnostic</h3>
              <p className="text-sm text-muted-foreground">
                Check authentication token status and health
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
              startContent={
                isLoading ? (
                  <RefreshCw className="w-4 h-4 animate-spin" />
                ) : (
                  <RefreshCw className="w-4 h-4" />
                )
              }
              onPress={runDiagnostic}
              isDisabled={isLoading || !getUserId().trim()}
            >
              {isLoading ? "Checking..." : "Run Diagnostic"}
            </Button>
          </div>
        </div>
      </CardHeader>

      <CardBody className="pt-0">
        {/* User ID Input Section */}
        <div className="mb-4 space-y-3">
          <div className="flex items-center gap-2">
            <User className="w-4 h-4 text-default-500" />
            <span className="text-sm font-medium">Target User:</span>
          </div>

          <div className="flex items-center gap-2">
            <Button
              size="sm"
              variant={!useCustomUserId ? "solid" : "flat"}
              color={!useCustomUserId ? "primary" : "default"}
              onPress={() => setUseCustomUserId(false)}
              isDisabled={!authStore.userId}
            >
              Current User
            </Button>
            <Button
              size="sm"
              variant={useCustomUserId ? "solid" : "flat"}
              color={useCustomUserId ? "primary" : "default"}
              onPress={() => setUseCustomUserId(true)}
            >
              Custom User ID
            </Button>
          </div>

          {!useCustomUserId && authStore.userId && (
            <div className="p-2 bg-default-100 rounded-lg">
              <p className="text-sm text-default-600 font-mono">{authStore.userId}</p>
            </div>
          )}

          {useCustomUserId && (
            <Input
              placeholder="Enter user ID to diagnose"
              value={customUserId}
              onValueChange={setCustomUserId}
              size="sm"
              variant="bordered"
            />
          )}
        </div>

        {error && (
          <div className="mb-4 p-3 bg-danger-50 border border-danger-200 rounded-lg">
            <div className="flex items-center gap-2">
              <AlertCircle className="w-4 h-4 text-danger" />
              <span className="text-sm text-danger-700">{error}</span>
            </div>
          </div>
        )}

        {diagnostic && (
          <div className="space-y-4">
            {/* Token Status Grid */}
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">Access Token:</span>
                  <Chip
                    color={diagnostic.access_token_present ? "success" : "danger"}
                    variant="flat"
                    size="sm"
                  >
                    {diagnostic.access_token_present ? "✅ Present" : "❌ Missing"}
                  </Chip>
                </div>

                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">Refresh Token:</span>
                  <Chip
                    color={diagnostic.refresh_token_present ? "success" : "danger"}
                    variant="flat"
                    size="sm"
                  >
                    {diagnostic.refresh_token_present ? "✅ Present" : "❌ Missing"}
                  </Chip>
                </div>
              </div>

              <div className="space-y-3">
                {diagnostic.access_token_expired !== null && (
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium">Token Expired:</span>
                    <Chip
                      color={diagnostic.access_token_expired ? "danger" : "success"}
                      variant="flat"
                      size="sm"
                    >
                      {diagnostic.access_token_expired ? "❌ Yes" : "✅ No"}
                    </Chip>
                  </div>
                )}

                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">Last Checked:</span>
                  <span className="text-xs text-muted-foreground">
                    {new Date(diagnostic.timestamp).toLocaleTimeString()}
                  </span>
                </div>
              </div>
            </div>

            {/* Recommendations */}
            {diagnostic.recommendations.length > 0 && (
              <div className="mt-4 p-3 bg-warning-50 border border-warning-200 rounded-lg">
                <div className="flex items-start gap-2">
                  <AlertCircle className="w-4 h-4 text-warning-600 mt-0.5 flex-shrink-0" />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-warning-800 mb-2">Recommendations:</p>
                    <ul className="space-y-1">
                      {diagnostic.recommendations.map((recommendation, index) => (
                        <li key={index} className="text-sm text-warning-700">
                          • {recommendation}
                        </li>
                      ))}
                    </ul>
                  </div>
                </div>
              </div>
            )}

            {/* User ID Display */}
            <div className="mt-4 p-2 bg-default-50 rounded-lg">
              <p className="text-xs text-default-600">
                <span className="font-medium">Diagnosed User:</span> {diagnostic.user_id}
              </p>
            </div>
          </div>
        )}

        {!diagnostic && !error && (
          <div className="text-center py-8 text-muted-foreground">
            <Key className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="text-sm">
              Select a user and click "Run Diagnostic" to check token status
            </p>
          </div>
        )}
      </CardBody>
    </Card>
  );
}
