import { Listbox, ListboxItem } from "@heroui/listbox";
import { useCallback, useMemo } from "react";
import { LoadingState } from "@/components/ui/error-display";
import { cn } from "@/lib/utils";
import type { CipherView } from "@/types/vault.types";
import { VaultItemCard } from "./vault-item-card";

export interface VaultItemsListProps {
  items: CipherView[];
  isLoading: boolean;
  error: string | null;
  onRetry?: () => void;
  onViewItem?: (item: CipherView) => void;
  onEditItem?: (item: CipherView) => void;
  onDeleteItem?: (item: CipherView) => void;
  className?: string;
}

export function VaultItemsList(props: VaultItemsListProps) {
  const { items, isLoading, error, onRetry, onViewItem, onEditItem, onDeleteItem, className } =
    props;

  // Defensive programming: ensure items is always an array
  const safeItems = useMemo(() => {
    if (!items) {
      console.warn("VaultItemsList: items is null/undefined, using empty array");
      return [];
    }
    if (!Array.isArray(items)) {
      console.warn("VaultItemsList: items is not an array, using empty array");
      return [];
    }
    return items;
  }, [items]);

  const handleViewItem = useCallback(
    (item: CipherView) => {
      try {
        if (!item) {
          console.warn("VaultItemsList: Attempted to view null/undefined item");
          return;
        }
        console.log("View item:", item.name);
        onViewItem?.(item);
      } catch (error) {
        console.error("VaultItemsList: Error in handleViewItem:", error);
      }
    },
    [onViewItem]
  );

  const handleEditItem = useCallback(
    (item: CipherView) => {
      try {
        if (!item) {
          console.warn("VaultItemsList: Attempted to edit null/undefined item");
          return;
        }
        console.log("Edit item:", item.name);
        onEditItem?.(item);
      } catch (error) {
        console.error("VaultItemsList: Error in handleEditItem:", error);
      }
    },
    [onEditItem]
  );

  const handleDeleteItem = useCallback(
    (item: CipherView) => {
      try {
        if (!item) {
          console.warn("VaultItemsList: Attempted to delete null/undefined item");
          return;
        }
        console.log("Delete item:", item.name);
        onDeleteItem?.(item);
      } catch (error) {
        console.error("VaultItemsList: Error in handleDeleteItem:", error);
      }
    },
    [onDeleteItem]
  );

  // Show loading or error state
  if (isLoading || error) {
    return (
      <LoadingState
        isLoading={isLoading}
        error={error}
        onRetry={onRetry}
        loadingText="Loading vault items..."
        className="min-h-[200px]"
      />
    );
  }

  // Show empty state
  if (safeItems.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[300px] text-center">
        <div className="w-16 h-16 rounded-full bg-muted flex items-center justify-center mb-4">
          <svg
            className="w-8 h-8 text-muted-foreground"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
            />
          </svg>
        </div>
        <h3 className="text-lg font-medium text-foreground mb-2">No vault items found</h3>
        <p className="text-muted-foreground max-w-sm">
          Your vault is empty. Start by adding your first login, secure note, card, or identity.
        </p>
      </div>
    );
  }

  return (
    <div className={cn("w-full", className)}>
      {/* Header */}
      <div className="mb-6">
        <h2 className="text-2xl font-semibold text-foreground mb-2">Vault Items</h2>
        <p className="text-muted-foreground">
          {safeItems.length} item{safeItems.length !== 1 ? "s" : ""} in your vault
        </p>
      </div>

      {/* Items List */}
      <Listbox
        aria-label="Vault items"
        selectionMode="none"
        className="gap-2"
        itemClasses={{
          base: "p-0 gap-0 rounded-lg data-[hover=true]:bg-transparent data-[selectable=true]:focus:bg-transparent",
        }}
      >
        {safeItems.map((item: CipherView) => {
          // Defensive check for each item
          if (!item || !item.id) {
            console.warn("VaultItemsList: Skipping invalid item:", item);
            return null;
          }

          try {
            return (
              <ListboxItem key={item.id} textValue={item.name || "Unnamed Item"} className="p-0">
                <VaultItemCard
                  item={item}
                  onView={handleViewItem}
                  onEdit={handleEditItem}
                  onDelete={handleDeleteItem}
                  className="w-full"
                />
              </ListboxItem>
            );
          } catch (error) {
            console.error("VaultItemsList: Error rendering item:", item.id, error);
            return null;
          }
        })}
      </Listbox>

      {/* Footer info */}
      <div className="mt-8 pt-4 border-t border-border">
        <p className="text-xs text-muted-foreground text-center">
          Last synced: {new Date().toLocaleString()}
        </p>
      </div>
    </div>
  );
}
