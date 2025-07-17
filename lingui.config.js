/** @type {import('@lingui/conf').LinguiConfig} */
module.exports = {
  locales: ["en", "zh-HK", "zh-CN", "zh-TW"],
  sourceLocale: "en",
  catalogs: [
    {
      path: "src/locales/{locale}/messages",
      include: ["src"],
      exclude: ["**/node_modules/**"],
    },
  ],
  format: "po",
  formatOptions: {
    lineNumbers: false,
  },
  orderBy: "messageId",
  pseudoLocale: "pseudo",
  fallbackLocales: {
    default: "en",
  },
  runtimeConfigModule: ["@lingui/core", "i18n"],
};
