import { Button } from "@heroui/button";
import { Input } from "@heroui/input";
import { Modal, ModalBody, ModalContent, ModalFooter, ModalHeader } from "@heroui/modal";
import { Switch } from "@heroui/switch";
import { useLingui } from "@lingui/react/macro";
import { Settings } from "lucide-react";
import { useState } from "react";
import { z } from "zod";
import { AnimatedCollapse } from "@/components/ui/animated-collapse";
import { HeroForm } from "@/components/ui/form";
import { useServerProviderQueries } from "@/hooks/queries/use-server-provider-queries";
import { serverProviderService } from "@/services/server-provider.service";

type AddServerProviderModalProps = {
  isOpen: boolean;
  onClose: () => void;
};

export default function AddServerProviderModal(props: AddServerProviderModalProps) {
  const { t } = useLingui();

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
  const { addCustomProvider, addCustomProviderWithUrls, setCurrentProvider } =
    useServerProviderQueries();

  const [error, setError] = useState("");

  // State for advanced mode switch
  const [advancedMode, setAdvancedMode] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const onSubmit = async (values: ServerProviderForm) => {
    try {
      setError("");
      setIsSubmitting(true);

      let newProviderId: string;

      if (advancedMode) {
        // Use advanced submission with individual URLs
        newProviderId = await addCustomProviderWithUrls.mutateAsync({
          label: values.label,
          urls: {
            base: values.base_url || undefined,
            api: values.api || undefined,
            identity: values.identity || undefined,
            web_vault: values.web_vault || undefined,
            icons: values.icons || undefined,
            notifications: values.notifications || undefined,
            events: values.events || undefined,
          },
        });
      } else {
        // Use basic submission with base URL only
        newProviderId = await addCustomProvider.mutateAsync({
          label: values.label,
          baseUrl: serverProviderService.formatBaseUrl(values.base_url),
        });
      }

      // Automatically set the newly created provider as the active provider
      await setCurrentProvider.mutateAsync(newProviderId);

      props.onClose();
      handleReset();
    } catch (error) {
      console.error("Failed to add server provider:", error);
      setError(error instanceof Error ? error.message : "Failed to add server provider");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleReset = () => {
    setAdvancedMode(false);
    setError("");
  };

  const handleClose = () => {
    handleReset();
    props.onClose();
  };

  const isLoading =
    addCustomProvider.isPending ||
    addCustomProviderWithUrls.isPending ||
    setCurrentProvider.isPending;

  return (
    <Modal isOpen={props.isOpen} onOpenChange={(open) => !open && handleClose()} size="lg">
      <ModalContent>
        <ModalHeader>
          <h2>{t`Add Custom Server` /* 添加自定义服务器 */}</h2>
        </ModalHeader>
        <ModalBody>
          <HeroForm
            id="server-provider-form"
            schema={serverProviderFormSchema}
            defaultValues={{
              label: "",
              base_url: "",
              api: "",
              identity: "",
              web_vault: "",
              icons: "",
              notifications: "",
              events: "",
              advanced_mode: false,
            }}
            onSubmit={onSubmit}
            className="space-y-6"
          >
            {/* Required Fields Section */}
            <div className="space-y-4 w-full">
              <Input
                name="label"
                label={t`Server Label` /* 服务器标签 */}
                placeholder={t`My Company Server` /* 我的公司服务器 */}
                required
              />

              <Input
                name="base_url"
                label={t`Server URL` /* 服务器URL */}
                placeholder="https://bitwarden.example.com"
                required
              />
            </div>

            {/* Advanced Configuration Section */}
            <div className="py-2 w-full">
              <Switch isSelected={advancedMode} onValueChange={setAdvancedMode}>
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

                  <Input name="api" label="API URL" placeholder="https://api.example.com" />

                  <Input
                    name="identity"
                    label="Identity URL"
                    placeholder="https://identity.example.com"
                  />

                  <Input
                    name="web_vault"
                    label="Web Vault URL"
                    placeholder="https://vault.example.com"
                  />

                  <Input name="icons" label="Icons URL" placeholder="https://icons.example.com" />

                  <Input
                    name="notifications"
                    label="Notifications URL"
                    placeholder="https://notifications.example.com"
                  />

                  <Input
                    name="events"
                    label="Events URL"
                    placeholder="https://events.example.com"
                  />
                </div>
              </AnimatedCollapse>
            </div>

            {error && <div className="text-red-500 text-sm">{error}</div>}
          </HeroForm>
        </ModalBody>
        <ModalFooter>
          <Button variant="light" onPress={handleClose} isDisabled={isLoading}>
            Cancel
          </Button>
          <Button
            color="primary"
            type="submit"
            form="server-provider-form"
            isLoading={isLoading || isSubmitting}
          >
            {isLoading ? "Adding..." : "Add Server"}
          </Button>
        </ModalFooter>
      </ModalContent>
    </Modal>
  );
}
