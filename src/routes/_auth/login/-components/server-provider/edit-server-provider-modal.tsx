import { Button } from "@heroui/button";
import { Input } from "@heroui/input";
import { Modal, ModalBody, ModalContent, ModalFooter, ModalHeader } from "@heroui/modal";
import { Switch } from "@heroui/switch";
import { zodResolver } from "@hookform/resolvers/zod";
import { useLingui } from "@lingui/react/macro";
import { Settings, Trash2 } from "lucide-react";
import { useEffect } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";
import { AnimatedCollapse } from "@/components/ui/animated-collapse";
import { ConfirmPopover } from "@/components/ui/popover";
import { useServerProviderQueries } from "@/hooks/queries/use-server-provider-queries";
import { useConfirmPopover } from "@/hooks/use-modal";
import { useToast } from "@/hooks/use-toast";
import type { ServerProvider } from "@/lib/tauri-commands";
import type { ServerProviderUrls } from "@/types/server-provider.types";

type EditServerProviderModalProps = {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
  provider: ServerProvider | null;
};

export default function EditServerProviderModal(props: EditServerProviderModalProps) {
  const { t } = useLingui();
  const { showSuccess, showError } = useToast();

  // Zod schema for form validation (moved inside component to access t function)
  const serverProviderFormSchema = z.object({
    label: z.string().min(1, t`validation.server_label_required`),
    base_url: z.url({ error: t`validation.url_invalid` }).min(1, t`validation.server_url_required`),
    api: z.union([z.url({ error: t`validation.url_invalid` }), z.literal("")]),
    identity: z.union([z.url({ error: t`validation.url_invalid` }), z.literal("")]),
    web_vault: z.union([z.url({ error: t`validation.url_invalid` }), z.literal("")]),
    icons: z.union([z.url({ error: t`validation.url_invalid` }), z.literal("")]),
    notifications: z.union([z.url({ error: t`validation.url_invalid` }), z.literal("")]),
    events: z.union([z.url({ error: t`validation.url_invalid` }), z.literal("")]),
    advanced_mode: z.boolean(),
  });

  type ServerProviderForm = z.infer<typeof serverProviderFormSchema>;
  const { updateProvider, removeProvider, currentProvider, allProviders, setCurrentProvider } =
    useServerProviderQueries();

  // React Hook Form setup
  const {
    register,
    handleSubmit,
    watch,
    reset,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm<ServerProviderForm>({
    resolver: zodResolver(serverProviderFormSchema),
    defaultValues: {
      label: "",
      base_url: "",
      api: "",
      identity: "",
      web_vault: "",
      icons: "",
      notifications: "",
      events: "",
      advanced_mode: false,
    },
  });

  const advancedMode = watch("advanced_mode");

  // Initialize form values when provider changes
  useEffect(() => {
    if (props.provider) {
      const provider = props.provider;

      // Set form values - always start with basic configuration (advanced_mode: false)
      // Only pre-populate advanced URL fields if they were previously configured
      reset({
        label: provider.label,
        base_url: provider.urls.base || "",
        api: provider.urls.api || "", // Only populate if previously configured
        identity: provider.urls.identity || "", // Only populate if previously configured
        web_vault: provider.urls.web_vault || "", // Only populate if previously configured
        icons: provider.urls.icons || "", // Only populate if previously configured
        notifications: provider.urls.notifications || "", // Only populate if previously configured
        events: provider.urls.events || "", // Only populate if previously configured
        advanced_mode: false, // Always start with basic configuration
      });
    }
  }, [props.provider, reset]);

  const onSubmit = async (values: ServerProviderForm) => {
    if (!props.provider) return;

    try {
      let urls: ServerProviderUrls;

      if (values.advanced_mode) {
        // Use individual URLs when in advanced mode
        urls = {
          api: values.api || undefined,
          identity: values.identity || undefined,
          web_vault: values.web_vault || undefined,
          icons: values.icons || undefined,
          notifications: values.notifications || undefined,
          events: values.events || undefined,
        };
      } else {
        // Use base URL only when in basic mode
        urls = {
          base: values.base_url,
        };
      }

      await updateProvider.mutateAsync({
        provider_id: props.provider.id,
        label: values.label,
        urls,
      });

      // Show success toast
      showSuccess({
        title: t`Server Provider Updated` /* 服务器提供商已更新 */,
        description: t`"${values.label}" has been successfully updated.` /* "${values.label}"已成功更新。 */,
      });

      props.onSuccess?.();
      props.onClose();
    } catch (error) {
      console.error("Failed to update server provider:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Failed to update server provider";

      // Show error toast
      showError({
        title: t`Failed to Update Server Provider` /* 更新服务器提供商失败 */,
        description: errorMessage,
      });
    }
  };

  const handleDelete = async () => {
    if (!props.provider) return;

    try {
      // Check if we're deleting the current active provider
      const isCurrentProvider = currentProvider.data?.id === props.provider.id;

      // Remove the provider
      await removeProvider.mutateAsync(props.provider.id);

      // If we deleted the current provider, switch to the first available provider
      if (
        isCurrentProvider &&
        allProviders.data &&
        allProviders.data.length > 0 &&
        props.provider
      ) {
        // Find the first provider that's not the one we just deleted
        const remainingProvider = allProviders.data.find((p) => p.id !== props.provider?.id);
        if (remainingProvider) {
          await setCurrentProvider.mutateAsync(remainingProvider.id);
        }
      }

      // Show success toast
      showSuccess({
        title: t`Server Provider Deleted` /* 服务器提供商已删除 */,
        description: t`"${props.provider.label}" has been successfully removed.` /* "${props.provider.label}"已成功删除。 */,
      });

      props.onSuccess?.();
      props.onClose();
    } catch (error) {
      console.error("Failed to delete server provider:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Failed to delete server provider";

      // Show error toast
      showError({
        title: t`Failed to Delete Server Provider` /* 删除服务器提供商失败 */,
        description: errorMessage,
      });
    }
  };

  // Confirmation popover for delete action
  const deleteConfirmPopover = useConfirmPopover({
    title: t`Delete Server Provider` /* 删除服务器提供商 */,
    message: props.provider
      ? t`Are you sure you want to delete "${props.provider.label}"? This action cannot be undone.` /* 您确定要删除"${props.provider.label}"吗？此操作无法撤销。 */
      : t`Are you sure you want to delete this server provider? This action cannot be undone.` /* 您确定要删除此服务器提供商吗？此操作无法撤销。 */,
    confirmText: t`Delete` /* 删除 */,
    cancelText: t`Cancel` /* 取消 */,
    variant: "destructive",
    placement: "top-end",
    icon: <Trash2 className="w-4 h-4" />,
    onConfirm: handleDelete,
  });

  const handleClose = () => {
    reset();
    props.onClose();
  };

  const isLoading =
    updateProvider.isPending || removeProvider.isPending || setCurrentProvider.isPending;

  return (
    <Modal
      isOpen={props.isOpen}
      onOpenChange={(open) => !open && handleClose()}
      size="2xl"
      classNames={{
        wrapper: "z-[9999]",
        backdrop: "z-[9998]",
      }}
    >
      <ModalContent>
        <ModalHeader>
          <h2>{t`Edit Custom Server` /* 编辑自定义服务器 */}</h2>
        </ModalHeader>
        <ModalBody>
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
            {/* Required Fields Section */}
            <div className="space-y-4">
              <Input
                {...register("label")}
                label={t`Server Label` /* 服务器标签 */}
                placeholder={t`My Company Server` /* 我的公司服务器 */}
                errorMessage={errors.label?.message}
                isInvalid={!!errors.label}
                isRequired
              />

              <Input
                {...register("base_url")}
                label={t`Server URL` /* 服务器URL */}
                placeholder="https://bitwarden.example.com"
                errorMessage={errors.base_url?.message}
                isInvalid={!!errors.base_url}
                isRequired
              />
            </div>

            {/* Advanced Configuration Section */}
            <div className="py-2">
              <Switch
                isSelected={advancedMode}
                onValueChange={(checked) => setValue("advanced_mode", checked)}
              >
                <div className="flex flex-col">
                  <span>{t`Advanced configuration` /* 高级配置 */}</span>
                  <span className="text-sm text-gray-500">
                    {t`Configure individual service URLs (optional)` /* 配置各个服务URL（可选） */}
                  </span>
                </div>
              </Switch>

              {/* Animated Collapsible Advanced Fields */}
              <AnimatedCollapse isOpen={advancedMode}>
                <div className="mt-4 p-4 rounded-lg border-primary/50 border-2 space-y-4">
                  <div className="flex items-center gap-2 text-sm font-medium mb-3">
                    <Settings size={16} />
                    <span>Service URLs</span>
                    <span className="text-xs text-gray-500">(All optional)</span>
                  </div>

                  <Input
                    {...register("api")}
                    label="API URL"
                    placeholder="https://api.example.com"
                    errorMessage={errors.api?.message}
                    isInvalid={!!errors.api}
                  />

                  <Input
                    {...register("identity")}
                    label="Identity URL"
                    placeholder="https://identity.example.com"
                    errorMessage={errors.identity?.message}
                    isInvalid={!!errors.identity}
                  />

                  <Input
                    {...register("web_vault")}
                    label="Web Vault URL"
                    placeholder="https://vault.example.com"
                    errorMessage={errors.web_vault?.message}
                    isInvalid={!!errors.web_vault}
                  />

                  <Input
                    {...register("icons")}
                    label="Icons URL"
                    placeholder="https://icons.example.com"
                    errorMessage={errors.icons?.message}
                    isInvalid={!!errors.icons}
                  />

                  <Input
                    {...register("notifications")}
                    label="Notifications URL"
                    placeholder="https://notifications.example.com"
                    errorMessage={errors.notifications?.message}
                    isInvalid={!!errors.notifications}
                  />

                  <Input
                    {...register("events")}
                    label="Events URL"
                    placeholder="https://events.example.com"
                    errorMessage={errors.events?.message}
                    isInvalid={!!errors.events}
                  />
                </div>
              </AnimatedCollapse>
            </div>
          </form>
        </ModalBody>
        <ModalFooter>
          <div className="flex justify-between items-center w-full">
            <ConfirmPopover
              {...deleteConfirmPopover.popoverProps}
              trigger={
                <Button
                  variant="light"
                  color="danger"
                  startContent={<Trash2 size={16} />}
                  onPress={deleteConfirmPopover.open}
                  isDisabled={isLoading}
                >
                  {t`Remove Server` /* 删除服务器 */}
                </Button>
              }
            />
            <div className="flex gap-2">
              <Button variant="light" onPress={handleClose} isDisabled={isLoading}>
                {t`Cancel` /* 取消 */}
              </Button>
              <Button
                color="primary"
                onPress={() => handleSubmit(onSubmit)()}
                isLoading={isLoading || isSubmitting}
              >
                {isLoading ? t`Updating...` /* 更新中... */ : t`Update Server` /* 更新服务器 */}
              </Button>
            </div>
          </div>
        </ModalFooter>
      </ModalContent>
    </Modal>
  );
}
