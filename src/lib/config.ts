// Development configuration for authentication behavior
export const authConfig = {
  // Allow state restoration in development for better DX
  allowDevStateRestoration: __DEV__,
  
  // Maximum age for development state restoration (24 hours)
  devStateMaxAge: __DEV__ ? 24 * 60 * 60 * 1000 : 0,
  
  // Log authentication state changes in development
  debugAuth: __DEV__,
  
  // Development session settings
  dev: {
    preserveUserContext: true,
    maxRestorationAge: 24 * 60 * 60 * 1000, // 24 hours
    allowStateRestoration: true,
  },
  
  // Production session settings
  prod: {
    preserveUserContext: false,
    maxRestorationAge: 0,
    allowStateRestoration: false,
  },
} as const;

export const getAuthConfig = () => __DEV__ ? authConfig.dev : authConfig.prod;