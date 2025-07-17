import { useLingui } from "@lingui/react/macro";
import { Dropdown } from "@/components/ui/dropdown";
import {
  getCurrentLocale,
  getLocaleName,
  getSupportedLocales,
  type SupportedLocale,
  setLocale,
} from "@/lib/i18n";

export function LanguageSwitcher() {
  const { t } = useLingui();
  const currentLang = getCurrentLocale();
  const supportedLocales = getSupportedLocales();

  const languageOptions = supportedLocales.map((locale) => ({
    value: locale,
    label: getLocaleName(locale),
  }));

  const handleLocaleChange = async (value: string) => {
    try {
      await setLocale(value as SupportedLocale);
    } catch (error) {
      console.error(t`common.failed_change_locale`, error);
    }
  };

  return (
    <Dropdown
      options={languageOptions}
      value={currentLang}
      onChange={handleLocaleChange}
      placeholder={t`common.select_language`}
      variant="solid"
      size="sm"
      className="min-w-[160px]"
    />
  );
}
