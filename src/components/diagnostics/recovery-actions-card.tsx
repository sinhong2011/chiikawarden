import { Button } from "@heroui/button";
import { Card, CardBody, CardHeader } from "@heroui/card";
import { Input } from "@heroui/input";
import { AlertTriangle, LogOut, RefreshCw, Trash2, UserX } from "lucide-react";
import React, { useState } from "react";
import { Modal } from "@/components/ui/modal";
import { getErrorMessage } from "@/lib/error-utils";
import { commands } from "@/lib/tauri-commands";
import { useAuthStore } from "@/stores/auth.store";

interface RecoveryActionsCardProps {
  className?: string;
}

export function RecoveryActionsCard({ className }: RecoveryActionsCardProps) {
  const authStore = useAuthStore();
  const [customUserId, setCustomUserId] = useState("");
  const [useCustomUserId, setUseCustomUserId] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [showConfirmModal, setShowConfirmModal] = useState(false);
  const [pendingAction, setPendingAction] = useState<{
    type: "clear-user-tokens" | "clear-test-tokens" | "logout";
    title: string;
    description: string;
    action: () => Promise<void>;
  } | null>(null);
  const [actionResult, setActionResult] = useState<{
    success: boolean;
    message: string;
  } | null>(null);

  const getUserId = () => {
    return useCustomUserId ? customUserId : authStore.userId || "";
  };

  const clearUserTokens = async () => {
    const userId = getUserId();
    if (!userId.trim()) {
      setActionResult({
        success: false,
        message: "Please provide a user ID",
      });
      return;
    }

    setIsLoading(true);
    try {
      const result = await commands.clearUserTokens(userId);
      if (result.status === "ok") {
        setActionResult({
          success: true,
          message: `Successfully cleared all tokens for user: ${userId}`,
        });
      } else {
        setActionResult({
          success: false,
          message: getErrorMessage(result.error) || "Failed to clear user tokens",
        });
      }
    } catch (err) {
      setActionResult({
        success: false,
        message: err instanceof Error ? err.message : "Unknown error occurred",
      });
    } finally {
      setIsLoading(false);
    }
  };

  const clearTestTokens = async () => {
    setIsLoading(true);
    try {
      const result = await commands.clearTestTokens("diagnostic_test");
      if (result.status === "ok") {
        setActionResult({
          success: true,
          message: "Successfully cleared all test tokens",
        });
      } else {
        setActionResult({
          success: false,
          message: getErrorMessage(result.error) || "Failed to clear test tokens",
        });
      }
    } catch (err) {
      setActionResult({
        success: false,
        message: err instanceof Error ? err.message : "Unknown error occurred",
      });
    } finally {
      setIsLoading(false);
    }
  };

  const logoutUser = async () => {
    setIsLoading(true);
    try {
      const result = await commands.logout(authStore.userId || "");
      if (result.status === "ok") {
        setActionResult({
          success: true,
          message: "Successfully logged out. Please log in again.",
        });
      } else {
        setActionResult({
          success: false,
          message: getErrorMessage(result.error) || "Failed to logout",
        });
      }
    } catch (err) {
      setActionResult({
        success: false,
        message: err instanceof Error ? err.message : "Unknown error occurred",
      });
    } finally {
      setIsLoading(false);
    }
  };

  const handleActionClick = (actionType: "clear-user-tokens" | "clear-test-tokens" | "logout") => {
    let action: () => Promise<void>;
    let title: string;
    let description: string;

    switch (actionType) {
      case "clear-user-tokens":
        action = clearUserTokens;
        title = "Clear User Tokens";
        description = `This will permanently delete all authentication tokens for user: ${getUserId()}. The user will need to log in again.`;
        break;
      case "clear-test-tokens":
        action = clearTestTokens;
        title = "Clear Test Tokens";
        description =
          "This will delete all test tokens created during diagnostic operations. This is safe and won't affect real user authentication.";
        break;
      case "logout":
        action = logoutUser;
        title = "Logout Current User";
        description =
          "This will log out the current user and clear their session. You will need to log in again.";
        break;
    }

    setPendingAction({ type: actionType, title, description, action });
    setShowConfirmModal(true);
  };

  const executeAction = async () => {
    if (pendingAction) {
      setShowConfirmModal(false);
      await pendingAction.action();
      setPendingAction(null);
    }
  };

  const cancelAction = () => {
    setShowConfirmModal(false);
    setPendingAction(null);
  };

  return (
    <>
      <Card className={className}>
        <CardHeader className="pb-3">
          <div className="flex items-center gap-3">
            <AlertTriangle className="w-5 h-5 text-warning" />
            <div>
              <h3 className="text-lg font-semibold">Recovery Actions</h3>
              <p className="text-sm text-muted-foreground">
                Emergency recovery options for authentication issues
              </p>
            </div>
          </div>
        </CardHeader>

        <CardBody className="pt-0">
          {/* User Selection */}
          <div className="mb-6 space-y-3">
            <h4 className="text-sm font-medium">Target User for Token Operations:</h4>

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
                placeholder="Enter user ID for token operations"
                value={customUserId}
                onValueChange={setCustomUserId}
                size="sm"
                variant="bordered"
              />
            )}
          </div>

          {/* Action Result */}
          {actionResult && (
            <div
              className={`mb-4 p-3 rounded-lg border ${
                actionResult.success
                  ? "bg-success-50 border-success-200"
                  : "bg-danger-50 border-danger-200"
              }`}
            >
              <p
                className={`text-sm ${
                  actionResult.success ? "text-success-700" : "text-danger-700"
                }`}
              >
                {actionResult.message}
              </p>
            </div>
          )}

          {/* Recovery Actions */}
          <div className="space-y-3">
            <div className="grid gap-3">
              {/* Clear User Tokens */}
              <div className="p-3 border border-warning-200 rounded-lg bg-warning-50">
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <h5 className="text-sm font-medium text-warning-800 mb-1">Clear User Tokens</h5>
                    <p className="text-xs text-warning-700 mb-3">
                      Remove all authentication tokens for the selected user. Use this when tokens
                      are corrupted or causing login issues.
                    </p>
                  </div>
                  <Button
                    color="warning"
                    variant="flat"
                    size="sm"
                    startContent={<UserX className="w-4 h-4" />}
                    onPress={() => handleActionClick("clear-user-tokens")}
                    isDisabled={isLoading || !getUserId().trim()}
                  >
                    Clear Tokens
                  </Button>
                </div>
              </div>

              {/* Clear Test Tokens */}
              <div className="p-3 border border-default-200 rounded-lg bg-default-50">
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <h5 className="text-sm font-medium text-default-800 mb-1">Clear Test Tokens</h5>
                    <p className="text-xs text-default-700 mb-3">
                      Remove all test tokens created during diagnostic operations. This is safe and
                      won't affect real authentication.
                    </p>
                  </div>
                  <Button
                    color="default"
                    variant="flat"
                    size="sm"
                    startContent={<Trash2 className="w-4 h-4" />}
                    onPress={() => handleActionClick("clear-test-tokens")}
                    isDisabled={isLoading}
                  >
                    Clear Tests
                  </Button>
                </div>
              </div>

              {/* Logout Current User */}
              <div className="p-3 border border-danger-200 rounded-lg bg-danger-50">
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <h5 className="text-sm font-medium text-danger-800 mb-1">
                      Logout Current User
                    </h5>
                    <p className="text-xs text-danger-700 mb-3">
                      Log out the current user and clear their session. You will need to log in
                      again after this action.
                    </p>
                  </div>
                  <Button
                    color="danger"
                    variant="flat"
                    size="sm"
                    startContent={<LogOut className="w-4 h-4" />}
                    onPress={() => handleActionClick("logout")}
                    isDisabled={isLoading || !authStore.userId}
                  >
                    Logout
                  </Button>
                </div>
              </div>
            </div>
          </div>

          {/* Warning Notice */}
          <div className="mt-4 p-3 bg-warning-50 border border-warning-200 rounded-lg">
            <div className="flex items-start gap-2">
              <AlertTriangle className="w-4 h-4 text-warning-600 mt-0.5 flex-shrink-0" />
              <div>
                <p className="text-sm font-medium text-warning-800">Important:</p>
                <p className="text-xs text-warning-700 mt-1">
                  These actions are irreversible. Make sure you understand the consequences before
                  proceeding. Users will need to re-authenticate after token clearing.
                </p>
              </div>
            </div>
          </div>
        </CardBody>
      </Card>

      {/* Confirmation Modal */}
      <Modal
        open={showConfirmModal}
        onOpenChange={setShowConfirmModal}
        title={pendingAction?.title}
        size="md"
      >
        <div className="space-y-4">
          <p className="text-sm text-default-600">{pendingAction?.description}</p>

          <div className="flex justify-end gap-2">
            <Button variant="flat" onPress={cancelAction} isDisabled={isLoading}>
              Cancel
            </Button>
            <Button
              color="danger"
              onPress={executeAction}
              isLoading={isLoading}
              startContent={!isLoading ? <RefreshCw className="w-4 h-4" /> : undefined}
            >
              {isLoading ? "Processing..." : "Confirm"}
            </Button>
          </div>
        </div>
      </Modal>
    </>
  );
}
