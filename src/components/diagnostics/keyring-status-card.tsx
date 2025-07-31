import { Button } from "@heroui/button";
import { Card, CardBody, CardHeader } from "@heroui/card";
import { Chip } from "@heroui/chip";
import { AlertCircle, CheckCircle, RefreshCw, Shield } from "lucide-react";
import React, { useState } from "react";
import { getErrorMessage } from "@/lib/error-utils";
import type { KeyringBackendStatus } from "@/lib/tauri-commands";
import { commands } from "@/lib/tauri-commands";

interface KeyringStatusCardProps {
  className?: string;
}

export function KeyringStatusCard({ className }: KeyringStatusCardProps) {
  const [status, setStatus] = useState<KeyringBackendStatus | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const checkKeyringStatus = async () => {
    setIsLoading(true);
    setError(null);

    try {
      const result = await commands.checkKeyringBackend();
      if (result.status === "ok") {
        setStatus(result.data);
      } else {
        setError(getErrorMessage(result.error) || "Failed to check keyring status");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error occurred");
    } finally {
      setIsLoading(false);
    }
  };

  const getStatusIcon = () => {
    if (!status) return <Shield className="w-5 h-5 text-default-400" />;

    if (status.backend_available && status.can_store_retrieve) {
      return <CheckCircle className="w-5 h-5 text-success" />;
    } else {
      return <AlertCircle className="w-5 h-5 text-danger" />;
    }
  };

  const getStatusColor = () => {
    if (!status) return "default";

    if (status.backend_available && status.can_store_retrieve) {
      return "success";
    } else {
      return "danger";
    }
  };

  const getStatusText = () => {
    if (!status) return "Not checked";

    if (status.backend_available && status.can_store_retrieve) {
      return "Healthy";
    } else {
      return "Issues detected";
    }
  };

  return (
    <Card className={className}>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between w-full">
          <div className="flex items-center gap-3">
            {getStatusIcon()}
            <div>
              <h3 className="text-lg font-semibold">Keyring Backend Status</h3>
              <p className="text-sm text-muted-foreground">
                System keyring integration health check
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Chip color={getStatusColor()} variant="flat" size="sm">
              {getStatusText()}
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
              onPress={checkKeyringStatus}
              isDisabled={isLoading}
            >
              {isLoading ? "Checking..." : "Check Status"}
            </Button>
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

        {status && (
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">Backend Available:</span>
                  <Chip
                    color={status.backend_available ? "success" : "danger"}
                    variant="flat"
                    size="sm"
                  >
                    {status.backend_available ? "✅ YES" : "❌ NO"}
                  </Chip>
                </div>

                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">Can Store/Retrieve:</span>
                  <Chip
                    color={status.can_store_retrieve ? "success" : "danger"}
                    variant="flat"
                    size="sm"
                  >
                    {status.can_store_retrieve ? "✅ YES" : "❌ NO"}
                  </Chip>
                </div>
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">Backend Type:</span>
                  <Chip
                    color={status.backend_type === "mock" ? "warning" : "primary"}
                    variant="flat"
                    size="sm"
                  >
                    {status.backend_type}
                  </Chip>
                </div>

                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">Last Checked:</span>
                  <span className="text-xs text-muted-foreground">
                    {new Date(status.timestamp).toLocaleTimeString()}
                  </span>
                </div>
              </div>
            </div>

            {status.error_message && (
              <div className="mt-4 p-3 bg-warning-50 border border-warning-200 rounded-lg">
                <div className="flex items-start gap-2">
                  <AlertCircle className="w-4 h-4 text-warning-600 mt-0.5 flex-shrink-0" />
                  <div>
                    <p className="text-sm font-medium text-warning-800">Backend Error:</p>
                    <p className="text-sm text-warning-700 mt-1">{status.error_message}</p>
                  </div>
                </div>
              </div>
            )}

            {status.backend_type === "mock" && (
              <div className="mt-4 p-3 bg-danger-50 border border-danger-200 rounded-lg">
                <div className="flex items-start gap-2">
                  <AlertCircle className="w-4 h-4 text-danger-600 mt-0.5 flex-shrink-0" />
                  <div>
                    <p className="text-sm font-medium text-danger-800">Mock Backend Detected!</p>
                    <p className="text-sm text-danger-700 mt-1">
                      Your keyring is using a mock backend which cannot securely store credentials.
                      This will cause authentication token issues.
                    </p>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}

        {!status && !error && (
          <div className="text-center py-8 text-muted-foreground">
            <Shield className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="text-sm">Click "Check Status" to verify keyring backend health</p>
          </div>
        )}
      </CardBody>
    </Card>
  );
}
