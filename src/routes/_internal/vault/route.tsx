import { Button } from "@heroui/button";
import { Input } from "@heroui/input";
import { Listbox, ListboxItem } from "@heroui/listbox";
import { useLingui } from "@lingui/react/macro";
import { createFileRoute, Link, Outlet, useNavigate } from "@tanstack/react-router";
import {
  ArchiveIcon,
  FolderIcon,
  FolderPlusIcon,
  HeartIcon,
  PlusIcon,
  SearchIcon,
  TrashIcon,
} from "lucide-react";
import { useMemo, useState } from "react";
import { useVaultQueries } from "@/hooks/queries/use-vault-queries";
import type { Folder } from "@/types/vault.types";

export const Route = createFileRoute("/_internal/vault")({
  component: VaultRouteComponent,
});

/**
 * Vault Route Component
 *
 * Provides a comprehensive layout for vault pages following auth layout patterns:
 * - Left sidebar with vault-specific navigation (folders, favorites, search)
 * - Main content area with proper overflow handling
 * - Consistent styling with the application's design system
 * - TypeScript typing and proper error handling
 * - Authentication state integration
 */
function VaultRouteComponent() {
  const { t } = useLingui();
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState("");

  // Fetch vault data
  const { data: folders = [], isLoading: foldersLoading } = useVaultQueries().folders;

  // Vault navigation items configuration
  const vaultNavItems = useMemo(
    () => [
      {
        key: "all-items",
        label: t`All Items` /* 所有项目 */,
        icon: ArchiveIcon,
        path: "/vault",
        count: null,
      },
      {
        key: "favorites",
        label: t`Favorites` /* 收藏夹 */,
        icon: HeartIcon,
        path: "/vault/favorites",
        count: null,
      },
      {
        key: "trash",
        label: t`Trash` /* 回收站 */,
        icon: TrashIcon,
        path: "/vault/trash",
        count: null,
      },
    ],
    [t]
  );

  const handleSearchSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (searchQuery.trim()) {
      navigate({
        to: "/vault/search",
        search: { q: searchQuery.trim() },
      });
    }
  };

  const handleFolderClick = (folderId: string) => {
    navigate({
      to: "/vault",
      search: { folder: folderId },
    });
  };

  const handleAddFolder = () => {
    navigate({ to: "/vault/folder/add" });
  };

  return (
    <div className="w-full h-full flex bg-background">
      {/* Vault Sidebar */}
      <aside className="w-60 h-full border-r border-border bg-card flex flex-col">
        {/* Search Section */}
        <div className="p-3 border-b border-border">
          <form onSubmit={handleSearchSubmit} className="relative">
            <Input
              type="search"
              placeholder={t`Search vault...` /* 搜索保险库... */}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              startContent={<SearchIcon className="w-4 h-4 text-default-400" />}
              classNames={{
                base: "w-full",
                input: "text-sm",
                inputWrapper: "h-9 min-h-9",
              }}
              aria-label={t`Search vault items` /* 搜索保险库项目 */}
            />
          </form>
        </div>

        {/* Navigation Items */}
        <div className="flex-1 overflow-auto">
          <div className="p-3">
            {/* Quick Actions */}
            <div className="mb-4">
              <Button
                as={Link}
                to="/vault/add"
                color="primary"
                size="sm"
                startContent={<PlusIcon className="w-4 h-4" />}
                className="w-full justify-start"
              >
                {t`Add Item` /* 添加项目 */}
              </Button>
            </div>

            {/* Main Navigation */}
            <div className="mb-6">
              <Listbox
                aria-label={t`Vault navigation` /* 保险库导航 */}
                selectionMode="none"
                className="gap-1"
                itemClasses={{
                  base: "px-3 py-2 rounded-lg data-[hover=true]:bg-default-100 data-[selectable=true]:focus:bg-default-100",
                  title: "text-sm font-medium",
                }}
              >
                {vaultNavItems.map((item) => {
                  const IconComponent = item.icon;
                  return (
                    <ListboxItem
                      key={item.key}
                      textValue={item.label}
                      className="cursor-pointer"
                      onClick={() => navigate({ to: item.path })}
                    >
                      <div className="flex items-center gap-3 w-full">
                        <IconComponent className="w-4 h-4 text-default-500 flex-shrink-0" />
                        <span className="flex-1 text-left">{item.label}</span>
                        {item.count !== null && (
                          <span className="text-xs text-default-400 bg-default-100 px-2 py-1 rounded-full">
                            {item.count}
                          </span>
                        )}
                      </div>
                    </ListboxItem>
                  );
                })}
              </Listbox>
            </div>

            {/* Folders Section */}
            <div>
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-sm font-semibold text-foreground">{t`Folders` /* 文件夹 */}</h3>
                <Button
                  isIconOnly
                  size="sm"
                  variant="light"
                  onPress={handleAddFolder}
                  aria-label={t`Add folder` /* 添加文件夹 */}
                >
                  <FolderPlusIcon className="w-4 h-4" />
                </Button>
              </div>

              {foldersLoading ? (
                <div className="text-sm text-default-400 px-3 py-2">
                  {t`Loading folders...` /* 加载文件夹中... */}
                </div>
              ) : folders.length === 0 ? (
                <div className="text-sm text-default-400 px-3 py-2">
                  {t`No folders` /* 无文件夹 */}
                </div>
              ) : (
                <Listbox
                  aria-label={t`Vault folders` /* 保险库文件夹 */}
                  selectionMode="none"
                  className="gap-1"
                  itemClasses={{
                    base: "px-3 py-2 rounded-lg data-[hover=true]:bg-default-100 data-[selectable=true]:focus:bg-default-100",
                    title: "text-sm",
                  }}
                >
                  {folders.map((folder: Folder) => (
                    <ListboxItem
                      key={folder.id}
                      textValue={folder.name}
                      className="cursor-pointer"
                      onClick={() => handleFolderClick(folder.id)}
                    >
                      <div className="flex items-center gap-3 w-full">
                        <FolderIcon className="w-4 h-4 text-default-500 flex-shrink-0" />
                        <span className="flex-1 text-left truncate">{folder.name}</span>
                      </div>
                    </ListboxItem>
                  ))}
                </Listbox>
              )}
            </div>
          </div>
        </div>
      </aside>

      {/* Main Content Area */}
      <main className="flex-1 h-full overflow-hidden">
        <div className="h-full overflow-auto">
          <Outlet />
        </div>
      </main>
    </div>
  );
}
