import { useLingui } from "@lingui/react/macro";
import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { Link } from "@/components/ui";
import { requireGuest } from "@/lib/router-guards";
import LoginForm from "@/routes/_auth/login/-components/login-form";
import PreLogin from "@/routes/_auth/login/-components/prelogin";
import AddServerProviderModal from "@/routes/_auth/login/-components/server-provider/add-server-provider-modal";
import ServerProviderSelector from "@/routes/_auth/login/-components/server-provider/server-provider-selector";
import type { PreloginResponse } from "@/services/auth.service";

export const Route = createFileRoute("/_auth/login/")({
  component: LoginComponent,
  ...requireGuest(),
});

type LoginStep = "prelogin" | "login";

function LoginComponent() {
  const { t } = useLingui();

  // Login flow state
  const [currentStep, setCurrentStep] = useState<LoginStep>("prelogin");
  const [email, setEmail] = useState("");
  const [kdfSettings, setKdfSettings] = useState<PreloginResponse | null>(null);
  const [rememberMe, setRememberMe] = useState(false);

  // Server provider state
  const [showAddProviderModal, setShowAddProviderModal] = useState(false);

  // Handle prelogin completion
  const handlePreloginFinish = (
    userEmail: string,
    settings: PreloginResponse,
    rememberMeValue: boolean
  ) => {
    console.log("Prelogin finished:", userEmail, settings, "Remember me:", rememberMeValue);

    setEmail(userEmail);
    setKdfSettings(settings);
    setRememberMe(rememberMeValue);
    setCurrentStep("login");
  };

  // Handle back to prelogin
  const handleBackToPrelogin = () => {
    setCurrentStep("prelogin");
    setEmail("");
    setKdfSettings(null);
    setRememberMe(false);
  };

  const handleAddProvider = () => {
    setShowAddProviderModal(true);
  };

  return (
    <div className="h-full flex flex-col gap-20 p-10 items-center">
      <div className="h-fit w-full">
        <h3 className="text-center mb-6">{t`Log in` /* 登录 */}</h3>
      </div>

      <div className="flex-1 flex flex-col items-center justify-start w-full pt-5">
        {currentStep === "login" && kdfSettings ? (
          <LoginForm
            email={email}
            kdfSettings={kdfSettings}
            rememberMe={rememberMe}
            onBack={handleBackToPrelogin}
          />
        ) : (
          <PreLogin onFinish={handlePreloginFinish} />
        )}

        <div className="flex justify-center mt-6 gap-2">
          <p className="text-base text-base-content/70">{
            t`Don't have an account?` /* 没有账户？ */
          }</p>
          <Link href="/signup" className="text-base text-primary hover:text-primary/80 font-medium">
            {t`Sign Up` /* 注册 */}
          </Link>
        </div>
      </div>

      {/* Server Provider Selection at bottom */}
      <div className="w-full max-w-md">
        <ServerProviderSelector onAddProvider={handleAddProvider} />
      </div>

      {/* Add Provider Modal */}
      <AddServerProviderModal
        isOpen={showAddProviderModal}
        onClose={() => setShowAddProviderModal(false)}
      />
    </div>
  );
}
