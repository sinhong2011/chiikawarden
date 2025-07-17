import { Button } from "@heroui/button";
import { useLingui } from "@lingui/react/macro";
import { Pen, PlusIcon } from "lucide-react";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { Dropdown } from "@/components/ui/dropdown";
import { useServerProviderQueries } from "@/hooks/queries/use-server-provider-queries";
import type { ServerProvider } from "@/lib/tauri-commands";
import EditServerProviderModal from "@/routes/_auth/login/-components/server-provider/edit-server-provider-modal";
import { serverProviderService } from "@/services/server-provider.service";

interface ServerProviderSelectorProps {
  onAddProvider?: () => void;
}

const ServerProviderSelector = React.memo((props: ServerProviderSelectorProps) => {
  const { t } = useLingui();
  const { providerInfo, setCurrentProvider } = useServerProviderQueries();
  const [selectedProviderId, setSelectedProviderId] = useState<string>("");
  const [showEditModal, setShowEditModal] = useState(false);
  const [editingProvider, setEditingProvider] = useState<ServerProvider | null>(null);

  // Initialize selected provider when data loads
  useEffect(() => {
    if (providerInfo.data?.current_provider) {
      setSelectedProviderId(providerInfo.data.current_provider.id);
    }
  }, [providerInfo.data?.current_provider]);

  // Memoized helper functions to prevent recreation on every render
  const getProviderDisplayName = useCallback((provider: ServerProvider) => {
    return `${provider.label}`;
  }, []);

  const getProviderDescription = useCallback((provider: ServerProvider) => {
    if (provider.provider_type === "Preset") {
      // bitwarden.com and bitwarden.eu are the official Bitwarden server URLs
      return provider.region === "US" ? "bitwarden.com" : "bitwarden.eu";
    }
    return serverProviderService.getProviderHostname(provider);
  }, []);

  const getProviderIcon = useCallback((provider: ServerProvider) => {
    if (provider.provider_type === "Preset") {
      return "🌐"; // Globe icon for preset providers
    }
    return "🏠"; // House icon for custom providers
  }, []);

  // Handle provider selection change - Updated for Dropdown component
  const handleProviderChange = useCallback(
    async (providerId: string) => {
      if (!providerId) return;

      // Fix: Validate provider exists
      const providerExists = providerInfo.data?.all_providers?.some(
        (provider) => provider.id === providerId
      );
      if (!providerExists) {
        console.warn(`Provider ${providerId} not found in available providers`);
        return;
      }

      setSelectedProviderId(providerId);

      try {
        await setCurrentProvider.mutateAsync(providerId);
      } catch (error) {
        console.error("Failed to change server provider:", error);
        // Fix: Better error handling without potential loops
        const currentProvider = providerInfo.data?.current_provider;
        if (currentProvider && currentProvider.id !== providerId) {
          setSelectedProviderId(currentProvider.id);
        } else {
          // If current provider is also invalid, clear selection
          setSelectedProviderId("");
        }
      }
    },
    [providerInfo.data?.all_providers, providerInfo.data?.current_provider, setCurrentProvider]
  );

  // Memoized edit handlers
  const handleEditProvider = useCallback((provider: ServerProvider) => {
    setEditingProvider(provider);
    setShowEditModal(true);
  }, []);

  const handleEditModalClose = useCallback(() => {
    setShowEditModal(false);
    setEditingProvider(null);
  }, []);

  const handleEditSuccess = useCallback(() => {
    // Modal will close automatically, just need to refresh data
    console.log("Server provider updated successfully");
  }, []);

  // Memoized provider sections to prevent recreation on every render
  const providerSections = useMemo(() => {
    if (!providerInfo.data) {
      return [];
    }

    const sections = [];

    // Built-in Providers section
    if (providerInfo.data.preset_providers && providerInfo.data.preset_providers.length > 0) {
      sections.push({
        title: t`Built-in Providers` /* 内置提供商 */,
        options: providerInfo.data.preset_providers.map((provider) => ({
          value: provider.id,
          label: `${getProviderIcon(provider)} ${getProviderDisplayName(provider)} - ${getProviderDescription(provider)}`,
          disabled: false,
        })),
        // Will show divider at bottom to separate from next section
      });
    }

    // Custom Providers section
    if (providerInfo.data.custom_providers && providerInfo.data.custom_providers.length > 0) {
      sections.push({
        title: t`Custom Providers` /* 自定义提供商 */,
        options: providerInfo.data.custom_providers.map((provider) => ({
          value: provider.id,
          label: `${getProviderIcon(provider)} ${getProviderDisplayName(provider)} - ${getProviderDescription(provider)}`,
          disabled: false,
          endContent: <Pen size={16} className="text-default-500 hover:text-primary" />,
          onEndContentClick: () => handleEditProvider(provider),
        })),
        // Last section will not have divider at bottom (clean end)
      });
    }

    return sections;
  }, [
    providerInfo.data,
    getProviderIcon,
    getProviderDisplayName,
    getProviderDescription,
    t,
    handleEditProvider,
  ]);

  return (
    <div className="space-y-4">
      <div className="space-y-2">
        {providerInfo.isLoading || !providerInfo.data ? (
          <div className="animate-pulse">
            <div className="flex items-center gap-2">
              <div className="h-10 bg-base-200 rounded flex-1"></div>
              <div className="h-10 w-10 bg-base-200 rounded"></div>
              <div className="h-10 w-10 bg-base-200 rounded"></div>
            </div>
          </div>
        ) : (
          <div className="flex items-center gap-2">
            <Dropdown
              placeholder={t`Select a server provider...` /* 选择服务器提供商... */}
              sections={providerSections}
              value={selectedProviderId}
              onChange={handleProviderChange}
              disabled={setCurrentProvider.isPending}
              variant="bordered"
              size="md"
              className="flex-1"
            />
            <Button
              variant="shadow"
              color="primary"
              isIconOnly
              onPress={props.onAddProvider}
              aria-label={t`Add server provider` /* 添加服务器提供商 */}
              className="size-9"
            >
              <PlusIcon size={16} />
            </Button>
          </div>
        )}

        {setCurrentProvider.isError && (
          <div className="text-danger text-sm">
            {
              t`Failed to change server provider. Please try again.` /* 更改服务器提供商失败。请重试。 */
            }
          </div>
        )}
      </div>

      {/* Edit Provider Modal */}
      <EditServerProviderModal
        isOpen={showEditModal}
        onClose={handleEditModalClose}
        onSuccess={handleEditSuccess}
        provider={editingProvider}
      />
    </div>
  );
});

// Set display name for React DevTools
ServerProviderSelector.displayName = "ServerProviderSelector";

export default ServerProviderSelector;
