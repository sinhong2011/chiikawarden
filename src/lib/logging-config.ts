// Frontend logging configuration and utilities
// Provides environment-aware logging controls and smart filtering

export interface LoggingConfig {
  // Global logging controls
  enableConsoleLogging: boolean;
  enableBackendForwarding: boolean;
  enableRateLimiting: boolean;
  
  // Log level controls
  logLevel: 'debug' | 'info' | 'warn' | 'error';
  
  // Component-specific controls
  componentFilters: {
    authGuard: boolean;
    accountDropdown: boolean;
    networkMonitor: boolean;
    vaultSync: boolean;
    routeNavigation: boolean;
  };
  
  // Rate limiting settings
  rateLimitWindow: number; // milliseconds
  maxLogsPerWindow: number;
  
  // Development settings
  verboseInDev: boolean;
  showStackTraces: boolean;
}

// Default configuration based on environment
const getDefaultConfig = (): LoggingConfig => {
  const isDev = import.meta.env.DEV;
  const isTest = import.meta.env.MODE === 'test';
  
  return {
    enableConsoleLogging: isDev || isTest,
    enableBackendForwarding: !isTest, // Don't forward to backend in tests
    enableRateLimiting: true,
    
    logLevel: isDev ? 'debug' : 'info',
    
    componentFilters: {
      authGuard: isDev, // Only log auth guard in development
      accountDropdown: false, // Disable by default (too noisy)
      networkMonitor: isDev,
      vaultSync: true, // Always log sync operations
      routeNavigation: isDev,
    },
    
    rateLimitWindow: 5000, // 5 seconds
    maxLogsPerWindow: 3,
    
    verboseInDev: isDev,
    showStackTraces: isDev,
  };
};

// Global logging configuration
let currentConfig: LoggingConfig = getDefaultConfig();

// Environment variable overrides
const applyEnvOverrides = (config: LoggingConfig): LoggingConfig => {
  // Check for environment variable overrides
  const envLogLevel = import.meta.env.VITE_LOG_LEVEL;
  if (envLogLevel && ['debug', 'info', 'warn', 'error'].includes(envLogLevel)) {
    config.logLevel = envLogLevel as LoggingConfig['logLevel'];
  }
  
  const envDisableRateLimit = import.meta.env.VITE_DISABLE_LOG_RATE_LIMIT;
  if (envDisableRateLimit === 'true') {
    config.enableRateLimiting = false;
  }
  
  const envVerbose = import.meta.env.VITE_VERBOSE_LOGGING;
  if (envVerbose === 'true') {
    config.verboseInDev = true;
    // Enable all component filters in verbose mode
    Object.keys(config.componentFilters).forEach(key => {
      config.componentFilters[key as keyof typeof config.componentFilters] = true;
    });
  }
  
  return config;
};

// Apply environment overrides
currentConfig = applyEnvOverrides(currentConfig);

/**
 * Get current logging configuration
 */
export const getLoggingConfig = (): LoggingConfig => currentConfig;

/**
 * Update logging configuration
 */
export const updateLoggingConfig = (updates: Partial<LoggingConfig>): void => {
  currentConfig = { ...currentConfig, ...updates };
};

/**
 * Check if logging is enabled for a specific component
 */
export const isComponentLoggingEnabled = (component: keyof LoggingConfig['componentFilters']): boolean => {
  return currentConfig.componentFilters[component] && shouldLog('debug');
};

/**
 * Check if a log level should be logged
 */
export const shouldLog = (level: LoggingConfig['logLevel']): boolean => {
  const levels = ['debug', 'info', 'warn', 'error'];
  const currentLevelIndex = levels.indexOf(currentConfig.logLevel);
  const requestedLevelIndex = levels.indexOf(level);
  
  return requestedLevelIndex >= currentLevelIndex;
};

/**
 * Smart logging utility that respects configuration
 */
export const smartLog = {
  debug: (message: string, data?: unknown, component?: string) => {
    if (!shouldLog('debug')) return;
    if (component && !isComponentLoggingEnabled(component as keyof LoggingConfig['componentFilters'])) return;
    
    if (currentConfig.enableConsoleLogging) {
      console.debug(`[${component || 'app'}] ${message}`, data);
    }
  },
  
  info: (message: string, data?: unknown, component?: string) => {
    if (!shouldLog('info')) return;
    if (component && !isComponentLoggingEnabled(component as keyof LoggingConfig['componentFilters'])) return;
    
    if (currentConfig.enableConsoleLogging) {
      console.info(`[${component || 'app'}] ${message}`, data);
    }
  },
  
  warn: (message: string, data?: unknown, component?: string) => {
    if (!shouldLog('warn')) return;
    
    if (currentConfig.enableConsoleLogging) {
      console.warn(`[${component || 'app'}] ${message}`, data);
    }
  },
  
  error: (message: string, error?: Error | unknown, component?: string) => {
    if (!shouldLog('error')) return;
    
    if (currentConfig.enableConsoleLogging) {
      if (error instanceof Error && currentConfig.showStackTraces) {
        console.error(`[${component || 'app'}] ${message}`, error);
      } else {
        console.error(`[${component || 'app'}] ${message}`, error);
      }
    }
  },
};

/**
 * Performance logging utility
 */
export const perfLog = {
  start: (operation: string): (() => void) => {
    if (!shouldLog('debug')) return () => {};
    
    const startTime = performance.now();
    return () => {
      const duration = performance.now() - startTime;
      smartLog.debug(`${operation} completed in ${duration.toFixed(2)}ms`, undefined, 'performance');
    };
  },
  
  measure: (operation: string, fn: () => void): void => {
    const endPerfLog = perfLog.start(operation);
    fn();
    endPerfLog();
  },
  
  measureAsync: async <T>(operation: string, fn: () => Promise<T>): Promise<T> => {
    const endPerfLog = perfLog.start(operation);
    try {
      return await fn();
    } finally {
      endPerfLog();
    }
  },
};

/**
 * Development-only logging
 */
export const devLog = {
  log: (message: string, data?: unknown, component?: string) => {
    if (import.meta.env.DEV && currentConfig.verboseInDev) {
      smartLog.debug(message, data, component);
    }
  },
  
  warn: (message: string, data?: unknown, component?: string) => {
    if (import.meta.env.DEV) {
      smartLog.warn(message, data, component);
    }
  },
  
  error: (message: string, error?: Error | unknown, component?: string) => {
    if (import.meta.env.DEV) {
      smartLog.error(message, error, component);
    }
  },
};
