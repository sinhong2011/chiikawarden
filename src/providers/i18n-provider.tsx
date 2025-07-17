import { I18nProvider as LinguiI18nProvider } from "@lingui/react";
import { useEffect, useState } from "react";
import { activateLocale, getDefaultLocale, i18n } from "@/lib/i18n";

interface I18nProviderProps {
  children: React.ReactNode;
}

export function I18nProvider({ children }: I18nProviderProps) {
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    async function initializeI18n() {
      try {
        const defaultLocale = getDefaultLocale();
        await activateLocale(defaultLocale);
      } catch (error) {
        console.error("Failed to initialize i18n:", error);
        // Fallback to English if initialization fails
        try {
          await activateLocale("en");
        } catch (fallbackError) {
          console.error("Failed to load fallback locale:", fallbackError);
        }
      } finally {
        setIsLoading(false);
      }
    }

    initializeI18n();
  }, []);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <div className="text-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary  mb-2"></div>
          <p className="text-sm text-default-500">Loading...</p>
        </div>
      </div>
    );
  }

  return <LinguiI18nProvider i18n={i18n}>{children}</LinguiI18nProvider>;
}
