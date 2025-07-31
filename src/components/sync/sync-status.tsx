// src/components/sync/sync-status.tsx

import { Button } from "@heroui/button";
import { Chip } from "@heroui/chip";
import { useLingui } from "@lingui/react/macro";
import { AlertCircle, CheckCircle, Clock, RefreshCw } from "lucide-react";
import React from "react";
import { ErrorDisplay } from "@/components/ui/error-display";
import { AnimatedSpinner } from "@/components/ui/icon/spinner";
import { useSyncStatus, useSyncVault } from "@/hooks/queries/use-sync-queries";
import { cn } from "@/lib/utils";
import { useAuthStore } from "@/stores/auth.store";

export interface SyncStatusProps {
  className?: string;
  showButton?: boolean;
  compact?: boolean;
}

export function SyncStatus({ className, showButton = true, compact = false }: SyncStatusProps) {
  const { t } = useLingui();
  const { userId } = useAuthStore();

  const { data: syncStatus, isLoading, error, refetch } = useSyncStatus(userId);
  const syncMutation = useSyncVault();

  const handleSync = async () => {
    if (!userId) return;

    try {
      await syncMutation.mutateAsync(userId);
    } catch (error) {
      console.error("Manual sync failed:", error);
    }
  };

  const formatLastSync = (lastSyncString?: string) => {
    if (!lastSyncString) return null;

    try {
      const lastSync = new Date(lastSyncString);
      const now = new Date();
      const diffMs = now.getTime() - lastSync.getTime();
      const diffMinutes = Math.floor(diffMs / (1000 * 60));
      const diffHours = Math.floor(diffMinutes / 60);
      const diffDays = Math.floor(diffHours / 24);

      if (diffMinutes < 1) {
        return t`Just now` /* 刚刚 */;
      } else if (diffMinutes < 60) {
        return t`${diffMinutes} minutes ago` /* ${diffMinutes} 分钟前 */;
      } else if (diffHours < 24) {
        return t`${diffHours} hours ago` /* ${diffHours} 小时前 */;
      } else if (diffDays < 7) {
        return t`${diffDays} days ago` /* ${diffDays} 天前 */;
      } else {
        return lastSync.toLocaleDateString();
      }
    } catch {
      return lastSyncString;
    }
  };

  const getSyncStatusChip = () => {
    const isCurrentlySync = syncMutation.isPending;

    if (isCurrentlySync) {
      return (
        <Chip
          color="primary"
          variant="flat"
          startContent={<AnimatedSpinner />}
          size={compact ? "sm" : "md"}
        >
          {t`Syncing...` /* 同步中... */}
        </Chip>
      );
    }

    if (syncMutation.isError) {
      return (
        <Chip
          color="danger"
          variant="flat"
          startContent={<AlertCircle size={16} />}
          size={compact ? "sm" : "md"}
        >
          {t`Sync failed` /* 同步失败 */}
        </Chip>
      );
    }

    if (syncStatus?.last_sync) {
      return (
        <Chip
          color="success"
          variant="flat"
          startContent={<CheckCircle size={16} />}
          size={compact ? "sm" : "md"}
        >
          {t`Synced` /* 已同步 */}
        </Chip>
      );
    }

    return (
      <Chip
        color="warning"
        variant="flat"
        startContent={<Clock size={16} />}
        size={compact ? "sm" : "md"}
      >
        {t`Not synced` /* 未同步 */}
      </Chip>
    );
  };

  if (isLoading) {
    return (
      <div className={cn("flex items-center gap-2", className)}>
        <AnimatedSpinner />
        <span className="text-sm text-default-500">
          {t`Loading sync status...` /* 加载同步状态... */}
        </span>
      </div>
    );
  }

  if (error) {
    return (
      <div className={cn("space-y-2", className)}>
        <ErrorDisplay
          error={error instanceof Error ? error.message : String(error)}
          onRetry={refetch}
          variant="compact"
          className="text-sm"
        />
      </div>
    );
  }

  if (compact) {
    return (
      <div className={cn("flex items-center gap-2", className)}>
        {getSyncStatusChip()}
        {syncStatus?.last_sync && (
          <span className="text-xs text-default-400">{formatLastSync(syncStatus.last_sync)}</span>
        )}
        {showButton && (
          <Button
            isIconOnly
            size="sm"
            variant="light"
            onPress={handleSync}
            isLoading={syncMutation.isPending}
            isDisabled={!userId}
            className="min-w-unit-8 w-unit-8 h-unit-8"
          >
            <RefreshCw size={14} />
          </Button>
        )}
      </div>
    );
  }

  return (
    <div className={cn("space-y-3", className)}>
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          {getSyncStatusChip()}
          {syncStatus?.last_sync && (
            <span className="text-sm text-default-500">{formatLastSync(syncStatus.last_sync)}</span>
          )}
        </div>

        {showButton && (
          <Button
            size="sm"
            variant="flat"
            startContent={<RefreshCw size={16} />}
            onPress={handleSync}
            isLoading={syncMutation.isPending}
            isDisabled={!userId}
          >
            {t`Sync now` /* 立即同步 */}
          </Button>
        )}
      </div>

      {/* Error display for sync failures */}
      {syncMutation.isError && (
        <ErrorDisplay
          error={
            syncMutation.error instanceof Error
              ? syncMutation.error.message
              : String(syncMutation.error)
          }
          onRetry={handleSync}
          variant="compact"
          className="text-sm"
        />
      )}

      {/* Success message for recent sync */}
      {syncMutation.isSuccess && !syncMutation.isPending && (
        <div className="text-sm text-success flex items-center gap-2">
          <CheckCircle size={16} />
          {t`Vault synchronized successfully` /* 保险库同步成功 */}
        </div>
      )}
    </div>
  );
}
