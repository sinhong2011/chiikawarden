// Mock for Paraglide i18n in Storybook
export const mockMessages = {
  en: {
    nav: {
      home: "Home",
      about: "About",
      dashboard: "Dashboard",
    },
    common: {
      loading: "Loading...",
      error: "Error",
      success: "Success",
      cancel: "Cancel",
      save: "Save",
      delete: "Delete",
      edit: "Edit",
      add: "Add",
      close: "Close",
    },
    form: {
      required: "This field is required",
      invalid_email: "Please enter a valid email",
      password_min_length: "Password must be at least 8 characters",
    },
    auth: {
      login: "Login",
      logout: "Logout",
      email: "Email",
      password: "Password",
      remember_me: "Remember me",
    },
  },
  "zh-CN": {
    nav: {
      home: "首页",
      about: "关于",
      dashboard: "仪表板",
    },
    common: {
      loading: "加载中...",
      error: "错误",
      success: "成功",
      cancel: "取消",
      save: "保存",
      delete: "删除",
      edit: "编辑",
      add: "添加",
      close: "关闭",
    },
    form: {
      required: "此字段为必填项",
      invalid_email: "请输入有效的电子邮件",
      password_min_length: "密码至少需要8个字符",
    },
    auth: {
      login: "登录",
      logout: "登出",
      email: "电子邮件",
      password: "密码",
      remember_me: "记住我",
    },
  },
};

// Current locale state
let currentLocale = "en";

// Mock m function that mimics Paraglide's functionality
export const m = (key: string, params?: Record<string, unknown>): string => {
  const keys = key.split(".");
  let value: unknown = mockMessages[currentLocale as keyof typeof mockMessages];

  for (const k of keys) {
    value = value?.[k];
  }

  if (typeof value !== "string") {
    console.warn(`[Mock i18n] Missing translation for key: ${key} in locale: ${currentLocale}`);
    return key;
  }

  // Simple parameter replacement (for basic {param} syntax)
  if (params) {
    return value.replace(/\{(\w+)\}/g, (match: string, paramKey: string) => {
      return params[paramKey] || match;
    });
  }

  return value;
};

// Mock locale management
export const setLocale = (locale: string) => {
  if (locale in mockMessages) {
    currentLocale = locale;
    console.log(`[Mock i18n] Locale changed to: ${locale}`);
  } else {
    console.warn(`[Mock i18n] Unsupported locale: ${locale}`);
  }
};

export const getLocale = () => currentLocale;

export const availableLocales = Object.keys(mockMessages);

// Define window interface for Storybook globals
interface WindowWithI18n extends Window {
  m?: typeof m;
  __STORYBOOK_I18N__?: {
    m: typeof m;
    setLocale: typeof setLocale;
    getLocale: typeof getLocale;
    availableLocales: typeof availableLocales;
  };
}

// Global setup for Storybook
if (typeof window !== "undefined") {
  const windowWithI18n = window as WindowWithI18n;
  windowWithI18n.m = m;
  windowWithI18n.__STORYBOOK_I18N__ = {
    m,
    setLocale,
    getLocale,
    availableLocales,
  };
}
