import { Button } from "@heroui/button";
import { AlertCircle, CheckCircle, Loader2, RefreshCw } from "lucide-react";
import type React from "react";
import { cn } from "@/lib/utils";
import type { SyncState } from "@/types/sync.types";

interface SyncIndicatorProps {
  syncState: SyncState;
  className?: string;
  showText?: boolean;
  size?: "sm" | "md" | "lg";
}

export const SyncIndicator: React.FC<SyncIndicatorProps> = ({
  syncState,
  className,
  showText = true,
  size = "md",
}) => {
  const { isLoading, error, success, syncMode, lastSyncTime } = syncState;

  // Size configurations
  const sizeConfig = {
    sm: {
      icon: "h-3 w-3",
      text: "text-xs",
      container: "gap-1",
    },
    md: {
      icon: "h-4 w-4",
      text: "text-sm",
      container: "gap-2",
    },
    lg: {
      icon: "h-5 w-5",
      text: "text-base",
      container: "gap-2",
    },
  };

  const config = sizeConfig[size];

  // Determine icon and styling based on state
  const getIndicatorContent = () => {
    if (isLoading) {
      return {
        icon: <Loader2 className={cn(config.icon, "animate-spin")} />,
        text: getSyncingText(syncMode),
        className: "text-blue-600 dark:text-blue-400",
      };
    }

    if (error) {
      return {
        icon: <AlertCircle className={config.icon} />,
        text: "Sync failed",
        className: "text-red-600 dark:text-red-400",
      };
    }

    if (success && lastSyncTime) {
      return {
        icon: <CheckCircle className={config.icon} />,
        text: `Synced ${getRelativeTime(lastSyncTime)}`,
        className: "text-green-600 dark:text-green-400",
      };
    }

    return {
      icon: <RefreshCw className={config.icon} />,
      text: "Not synced",
      className: "text-gray-500 dark:text-gray-400",
    };
  };

  const getSyncingText = (mode: string) => {
    switch (mode) {
      case "login":
        return "Syncing vault...";
      case "background":
        return "Updating...";
      case "manual":
        return "Syncing...";
      case "periodic":
        return "Auto-syncing...";
      default:
        return "Syncing...";
    }
  };

  const getRelativeTime = (date: Date) => {
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMinutes = Math.floor(diffMs / (1000 * 60));
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffMinutes < 1) return "just now";
    if (diffMinutes < 60) return `${diffMinutes}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  };

  const content = getIndicatorContent();

  return (
    <div
      className={cn("flex items-center", config.container, content.className, className)}
      title={
        error || (lastSyncTime ? `Last synced: ${lastSyncTime.toLocaleString()}` : "No sync data")
      }
    >
      {content.icon}
      {showText && <span className={cn(config.text, "font-medium")}>{content.text}</span>}
    </div>
  );
};

interface SyncBadgeProps {
  syncState: SyncState;
  className?: string;
}

export const SyncBadge: React.FC<SyncBadgeProps> = ({ syncState, className }) => {
  const { isLoading, error, hasChanges } = syncState;

  if (!isLoading && !error && !hasChanges) return null;

  return (
    <div
      className={cn(
        "inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium",
        {
          "bg-blue-100 text-blue-700 dark:bg-blue-900/20 dark:text-blue-300": isLoading,
          "bg-red-100 text-red-700 dark:bg-red-900/20 dark:text-red-300": error,
          "bg-green-100 text-green-700 dark:bg-green-900/20 dark:text-green-300":
            hasChanges && !isLoading && !error,
        },
        className
      )}
    >
      {isLoading && <Loader2 className="h-3 w-3 animate-spin" />}
      {error && <AlertCircle className="h-3 w-3" />}
      {hasChanges && !isLoading && !error && <CheckCircle className="h-3 w-3" />}

      <span>
        {isLoading && "Syncing"}
        {error && "Sync Error"}
        {hasChanges && !isLoading && !error && "Updated"}
      </span>
    </div>
  );
};

interface SyncNotificationProps {
  syncState: SyncState;
  onDismiss?: () => void;
  className?: string;
}

export const SyncNotification: React.FC<SyncNotificationProps> = ({
  syncState,
  onDismiss,
  className,
}) => {
  const { hasChanges, itemsUpdated, error } = syncState;

  if (!hasChanges && !error) return null;

  return (
    <div
      className={cn(
        "flex items-center justify-between p-3 rounded-lg border",
        {
          "bg-green-50 border-green-200 text-green-800 dark:bg-green-900/20 dark:border-green-800 dark:text-green-200":
            hasChanges && !error,
          "bg-red-50 border-red-200 text-red-800 dark:bg-red-900/20 dark:border-red-800 dark:text-red-200":
            error,
        },
        className
      )}
    >
      <div className="flex items-center gap-2">
        {hasChanges && !error && <CheckCircle className="h-4 w-4" />}
        {error && <AlertCircle className="h-4 w-4" />}

        <span className="text-sm font-medium">
          {hasChanges && !error && `Vault updated with ${itemsUpdated} items`}
          {error && "Sync failed"}
        </span>
      </div>

      {onDismiss && (
        <Button
          isIconOnly
          size="sm"
          variant="light"
          onPress={onDismiss}
          className="text-current hover:opacity-70 transition-opacity"
          aria-label="Dismiss notification"
        >
          ×
        </Button>
      )}
    </div>
  );
};
