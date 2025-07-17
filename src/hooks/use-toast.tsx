import { addToast } from "@heroui/toast";
import { useLingui } from "@lingui/react/macro";
import { AlertTriangle, CheckCircle, Info, XCircle } from "lucide-react";

export interface ToastOptions {
  title?: string;
  description?: string;
  timeout?: number;
}

export function useToast() {
  const { t } = useLingui();

  const showSuccess = (options: ToastOptions) => {
    return addToast({
      color: "success",
      variant: "flat",
      title: options.title || t`Success` /* 成功 */,
      description: options.description,
      timeout: options.timeout || 4000,
      icon: <CheckCircle className="w-5 h-5" />,
    });
  };

  const showError = (options: ToastOptions) => {
    return addToast({
      color: "danger",
      variant: "flat",
      title: options.title || t`Error` /* 错误 */,
      description: options.description,
      timeout: options.timeout || 6000,
      icon: <XCircle className="w-5 h-5" />,
    });
  };

  const showWarning = (options: ToastOptions) => {
    return addToast({
      color: "warning",
      variant: "flat",
      title: options.title || t`Warning` /* 警告 */,
      description: options.description,
      timeout: options.timeout || 5000,
      icon: <AlertTriangle className="w-5 h-5" />,
    });
  };

  const showInfo = (options: ToastOptions) => {
    return addToast({
      color: "primary",
      variant: "flat",
      title: options.title || t`Information` /* 信息 */,
      description: options.description,
      timeout: options.timeout || 4000,
      icon: <Info className="w-5 h-5" />,
    });
  };

  return {
    showSuccess,
    showError,
    showWarning,
    showInfo,
  };
}
