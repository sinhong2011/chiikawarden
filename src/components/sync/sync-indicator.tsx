// src/components/sync/sync-indicator.tsx

import { Button } from "@heroui/button";
import { Tooltip } from "@heroui/tooltip";
import { useLingui } from "@lingui/react/macro";
import { RefreshCw, CheckCircle, AlertCircle, Clock, Wifi, WifiOff } from "lucide-react";
import React from "react";
import { AnimatedSpinner } from "@/components/ui/icon/spinner";
import { useSyncStatus, useSyncVault } from "@/hooks/queries/use-sync-queries";
import { useAuthStore } from "@/stores/auth.store";
import { cn } from "@/lib/utils";

export interface SyncIndicatorProps {
  className?: string;
  size?: "sm" | "md" | "lg";
  showTooltip?: boolean;
}

export function SyncIndicator({ className, size = "md", showTooltip = true }: SyncIndicatorProps) {
  const { t } = useLingui();
  const { userId } = useAuthStore();
  
  const { data: syncStatus, isLoading, error } = useSyncStatus(userId);
  const syncMutation = useSyncVault();

  const handleSync = async () => {
    if (!userId) return;
    
    try {
      await syncMutation.mutateAsync(userId);
    } catch (error) {
      console.error("Manual sync failed:", error);
    }
  };

  const getIconSize = () => {
    switch (size) {
      case "sm": return 14;
      case "lg": return 20;
      default: return 16;
    }
  };

  const getButtonSize = () => {
    switch (size) {
      case "sm": return "sm";
      case "lg": return "md";
      default: return "sm";
    }
  };

  const getSyncIcon = () => {
    const iconSize = getIconSize();
    const isCurrentlySync = syncMutation.isPending;
    
    if (isCurrentlySync) {
      return <AnimatedSpinner />;
    }

    if (error || syncMutation.isError) {
      return <WifiOff size={iconSize} className="text-danger" />;
    }

    if (syncStatus?.last_sync) {
      return <CheckCircle size={iconSize} className="text-success" />;
    }

    return <Clock size={iconSize} className="text-warning" />;
  };

  const getTooltipContent = () => {
    const isCurrentlySync = syncMutation.isPending;
    
    if (isCurrentlySync) {
      return t`Syncing vault...` /* 正在同步保险库... */;
    }

    if (error || syncMutation.isError) {
      return t`Sync failed - Click to retry` /* 同步失败 - 点击重试 */;
    }

    if (syncStatus?.last_sync) {
      try {
        const lastSync = new Date(syncStatus.last_sync);
        const now = new Date();
        const diffMs = now.getTime() - lastSync.getTime();
        const diffMinutes = Math.floor(diffMs / (1000 * 60));
        
        if (diffMinutes < 1) {
          return t`Synced just now - Click to sync again` /* 刚刚同步 - 点击再次同步 */;
        } else if (diffMinutes < 60) {
          return t`Synced ${diffMinutes} minutes ago - Click to sync again` /* ${diffMinutes} 分钟前同步 - 点击再次同步 */;
        } else {
          return t`Last synced: ${lastSync.toLocaleString()} - Click to sync again` /* 上次同步：${lastSync.toLocaleString()} - 点击再次同步 */;
        }
      } catch {
        return t`Synced - Click to sync again` /* 已同步 - 点击再次同步 */;
      }
    }

    return t`Not synced - Click to sync` /* 未同步 - 点击同步 */;
  };

  const getButtonColor = () => {
    const isCurrentlySync = syncMutation.isPending;
    
    if (isCurrentlySync) {
      return "primary";
    }

    if (error || syncMutation.isError) {
      return "danger";
    }

    if (syncStatus?.last_sync) {
      return "success";
    }

    return "warning";
  };

  const button = (
    <Button
      isIconOnly
      size={getButtonSize()}
      variant="light"
      color={getButtonColor()}
      onPress={handleSync}
      isLoading={syncMutation.isPending}
      isDisabled={!userId || isLoading}
      className={cn(
        "transition-colors duration-200",
        size === "sm" && "min-w-unit-6 w-unit-6 h-unit-6",
        size === "md" && "min-w-unit-8 w-unit-8 h-unit-8",
        size === "lg" && "min-w-unit-10 w-unit-10 h-unit-10",
        className
      )}
    >
      {getSyncIcon()}
    </Button>
  );

  if (!showTooltip) {
    return button;
  }

  return (
    <Tooltip
      content={getTooltipContent()}
      placement="bottom"
      delay={500}
      closeDelay={0}
      classNames={{
        content: "text-xs max-w-xs",
      }}
    >
      {button}
    </Tooltip>
  );
}

// Compact text version for use in status bars
export interface SyncStatusTextProps {
  className?: string;
}

export function SyncStatusText({ className }: SyncStatusTextProps) {
  const { t } = useLingui();
  const { userId } = useAuthStore();
  
  const { data: syncStatus, isLoading } = useSyncStatus(userId);
  const syncMutation = useSyncVault();

  if (isLoading) {
    return (
      <span className={cn("text-xs text-default-400", className)}>
        {t`Loading...` /* 加载中... */}
      </span>
    );
  }

  const isCurrentlySync = syncMutation.isPending;
  
  if (isCurrentlySync) {
    return (
      <span className={cn("text-xs text-primary flex items-center gap-1", className)}>
        <AnimatedSpinner />
        {t`Syncing` /* 同步中 */}
      </span>
    );
  }

  if (syncStatus?.last_sync) {
    try {
      const lastSync = new Date(syncStatus.last_sync);
      const now = new Date();
      const diffMs = now.getTime() - lastSync.getTime();
      const diffMinutes = Math.floor(diffMs / (1000 * 60));
      
      if (diffMinutes < 1) {
        return (
          <span className={cn("text-xs text-success", className)}>
            {t`Synced` /* 已同步 */}
          </span>
        );
      } else if (diffMinutes < 60) {
        return (
          <span className={cn("text-xs text-default-500", className)}>
            {t`${diffMinutes}m ago` /* ${diffMinutes}分钟前 */}
          </span>
        );
      } else {
        const diffHours = Math.floor(diffMinutes / 60);
        return (
          <span className={cn("text-xs text-default-500", className)}>
            {t`${diffHours}h ago` /* ${diffHours}小时前 */}
          </span>
        );
      }
    } catch {
      return (
        <span className={cn("text-xs text-success", className)}>
          {t`Synced` /* 已同步 */}
        </span>
      );
    }
  }

  return (
    <span className={cn("text-xs text-warning", className)}>
      {t`Not synced` /* 未同步 */}
    </span>
  );
}
