import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useCallback, useEffect, useMemo } from "react";
import { VaultItemsList } from "@/components/vault";
import { SyncIndicator, SyncNotification } from "@/components/vault/sync-indicator";
import { useVaultItems } from "@/hooks/queries/use-vault-queries";
import { useVaultSync } from "@/hooks/use-vault-sync";
import { requireUnlocked } from "@/lib/router-guards";
import type { CipherView } from "@/types/vault.types";

export const Route = createFileRoute("/_internal/vault/")({
  component: VaultIndexComponent,
  ...requireUnlocked(), // Require user to be unlocked to access vault
});

function VaultIndexComponent() {
  const navigate = useNavigate();

  // Enhanced vault items fetching with defensive defaults
  const vaultItemsQuery = useVaultItems();
  const { data: rawItems, isLoading, error, refetch } = vaultItemsQuery;

  // Ensure items is always a safe array
  const items = useMemo(() => {
    if (!rawItems) {
      console.warn("VaultIndexComponent: rawItems is null/undefined, using empty array");
      return [];
    }
    if (!Array.isArray(rawItems)) {
      console.warn("VaultIndexComponent: rawItems is not an array, using empty array");
      return [];
    }
    return rawItems;
  }, [rawItems]);

  // Initialize vault sync with optimal configuration
  const { syncState, syncAfterUnlock, syncManual, clearError } = useVaultSync({
    syncThresholdMinutes: 5, // Sync if last sync was more than 5 minutes ago
    enableBackgroundSync: true,
    enablePeriodicSync: true,
    periodicSyncIntervalMinutes: 15, // Auto-sync every 15 minutes
  });

  // Check and perform conditional sync after unlock with enhanced error handling
  useEffect(() => {
    const performUnlockSync = async () => {
      try {
        await syncAfterUnlock();
      } catch (error) {
        console.warn("VaultIndexComponent: Background sync after unlock failed:", error);
        // Don't show error to user for background sync failures
        // The sync notification component will handle displaying sync errors
      }
    };

    // Wrap in try-catch to prevent any synchronous errors from breaking the component
    try {
      performUnlockSync();
    } catch (error) {
      console.error("VaultIndexComponent: Error in performUnlockSync setup:", error);
    }
  }, [syncAfterUnlock]); // Include syncAfterUnlock in dependencies

  const handleViewItem = (item: CipherView) => {
    // Navigate to view route
    navigate({ to: "/vault/view/$id", params: { id: item.id } });
  };

  const handleEditItem = (item: CipherView) => {
    // For now, just log - could navigate to edit route in the future
    console.log("Edit item:", item.name);
    // navigate({ to: "/vault/edit/$id", params: { id: item.id } });
  };

  const handleDeleteItem = (item: CipherView) => {
    // For now, just log - could show confirmation modal in the future
    console.log("Delete item:", item.name);
    // Show confirmation modal and handle deletion
  };

  const handleRetry = () => {
    refetch();
  };

  const handleManualSync = useCallback(async () => {
    try {
      console.log("VaultIndexComponent: Starting manual sync...");
      await syncManual();
      console.log("VaultIndexComponent: Manual sync completed successfully");
    } catch (error) {
      console.error("VaultIndexComponent: Manual sync failed:", error);
      // Error will be shown via sync notification component
      // Don't rethrow to prevent UI breakage
    }
  }, [syncManual]);

  return (
    <div className="w-full h-full flex flex-col gap-4">
      {/* Sync Status and Notifications */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <h1 className="text-2xl font-semibold">Vault</h1>
          <SyncIndicator syncState={syncState} size="sm" />
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={handleManualSync}
            disabled={syncState.isLoading}
            className="p-2 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 disabled:opacity-50"
            title="Sync vault"
            aria-label="Sync vault"
          >
            <svg
              className={`h-4 w-4 ${syncState.isLoading ? "animate-spin" : ""}`}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              aria-hidden="true"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
              />
            </svg>
          </button>
        </div>
      </div>

      {/* Sync Notifications */}
      <SyncNotification syncState={syncState} onDismiss={clearError} />

      {/* Main Vault Content */}
      <div className="flex flex-1">
        <div>
          <VaultItemsList
            items={items}
            isLoading={isLoading}
            error={error?.message || null}
            onRetry={handleRetry}
            onViewItem={handleViewItem}
            onEditItem={handleEditItem}
            onDeleteItem={handleDeleteItem}
          />
        </div>
        <div className="flex-1"></div>
      </div>
    </div>
  );
}
