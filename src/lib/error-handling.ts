// src/lib/error-handling.ts
// Comprehensive error handling utilities for authentication and other operations

import { i18n } from "@/lib/i18n";

export interface AppError {
  code: string;
  message: string;
  details?: string;
  retryable?: boolean;
  userMessage?: string;
}

// Error codes for different types of authentication errors
export const AUTH_ERROR_CODES = {
  // Network and connectivity errors
  NETWORK_ERROR: "NETWORK_ERROR",
  TIMEOUT_ERROR: "TIMEOUT_ERROR",
  CONNECTION_FAILED: "CONNECTION_FAILED",

  // Authentication errors
  INVALID_CREDENTIALS: "INVALID_CREDENTIALS",
  ACCOUNT_LOCKED: "ACCOUNT_LOCKED",
  ACCOUNT_NOT_FOUND: "ACCOUNT_NOT_FOUND",
  EMAIL_NOT_VERIFIED: "EMAIL_NOT_VERIFIED",

  // Two-factor authentication errors
  TWO_FACTOR_REQUIRED: "TWO_FACTOR_REQUIRED",
  INVALID_TWO_FACTOR: "INVALID_TWO_FACTOR",
  TWO_FACTOR_EXPIRED: "TWO_FACTOR_EXPIRED",

  // Session and token errors
  SESSION_EXPIRED: "SESSION_EXPIRED",
  INVALID_TOKEN: "INVALID_TOKEN",
  TOKEN_REFRESH_FAILED: "TOKEN_REFRESH_FAILED",

  // Vault and encryption errors
  VAULT_LOCKED: "VAULT_LOCKED",
  DECRYPTION_FAILED: "DECRYPTION_FAILED",
  MASTER_KEY_INVALID: "MASTER_KEY_INVALID",

  // Biometric errors
  BIOMETRIC_NOT_AVAILABLE: "BIOMETRIC_NOT_AVAILABLE",
  BIOMETRIC_NOT_ENROLLED: "BIOMETRIC_NOT_ENROLLED",
  BIOMETRIC_FAILED: "BIOMETRIC_FAILED",

  // Server and API errors
  SERVER_ERROR: "SERVER_ERROR",
  API_ERROR: "API_ERROR",
  RATE_LIMITED: "RATE_LIMITED",
  MAINTENANCE_MODE: "MAINTENANCE_MODE",

  // Client-side errors
  VALIDATION_ERROR: "VALIDATION_ERROR",
  UNKNOWN_ERROR: "UNKNOWN_ERROR",
} as const;

// User-friendly error messages with i18n support
export const ERROR_MESSAGES: Record<string, { messageKey: string; retryable: boolean }> = {
  [AUTH_ERROR_CODES.NETWORK_ERROR]: {
    messageKey: "error.network_error",
    retryable: true,
  },
  [AUTH_ERROR_CODES.TIMEOUT_ERROR]: {
    messageKey: "error.timeout_error",
    retryable: true,
  },
  [AUTH_ERROR_CODES.CONNECTION_FAILED]: {
    messageKey: "error.connection_failed",
    retryable: true,
  },
  [AUTH_ERROR_CODES.INVALID_CREDENTIALS]: {
    messageKey: "error.invalid_credentials",
    retryable: false,
  },
  [AUTH_ERROR_CODES.ACCOUNT_LOCKED]: {
    messageKey: "error.account_locked",
    retryable: false,
  },
  [AUTH_ERROR_CODES.ACCOUNT_NOT_FOUND]: {
    messageKey: "error.account_not_found",
    retryable: false,
  },
  [AUTH_ERROR_CODES.EMAIL_NOT_VERIFIED]: {
    messageKey: "error.email_not_verified",
    retryable: false,
  },
  [AUTH_ERROR_CODES.TWO_FACTOR_REQUIRED]: {
    messageKey: "error.two_factor_required",
    retryable: false,
  },
  [AUTH_ERROR_CODES.INVALID_TWO_FACTOR]: {
    messageKey: "error.invalid_two_factor",
    retryable: true,
  },
  [AUTH_ERROR_CODES.TWO_FACTOR_EXPIRED]: {
    messageKey: "error.two_factor_expired",
    retryable: true,
  },
  [AUTH_ERROR_CODES.SESSION_EXPIRED]: {
    messageKey: "error.session_expired",
    retryable: false,
  },
  [AUTH_ERROR_CODES.INVALID_TOKEN]: {
    messageKey: "error.invalid_token",
    retryable: false,
  },
  [AUTH_ERROR_CODES.TOKEN_REFRESH_FAILED]: {
    messageKey: "error.token_refresh_failed",
    retryable: false,
  },
  [AUTH_ERROR_CODES.VAULT_LOCKED]: {
    messageKey: "error.vault_locked",
    retryable: false,
  },
  [AUTH_ERROR_CODES.DECRYPTION_FAILED]: {
    messageKey: "error.decryption_failed",
    retryable: true,
  },
  [AUTH_ERROR_CODES.MASTER_KEY_INVALID]: {
    messageKey: "error.master_key_invalid",
    retryable: true,
  },
  [AUTH_ERROR_CODES.BIOMETRIC_NOT_AVAILABLE]: {
    messageKey: "error.biometric_not_available",
    retryable: false,
  },
  [AUTH_ERROR_CODES.BIOMETRIC_NOT_ENROLLED]: {
    messageKey: "error.biometric_not_enrolled",
    retryable: false,
  },
  [AUTH_ERROR_CODES.BIOMETRIC_FAILED]: {
    messageKey: "error.biometric_failed",
    retryable: true,
  },
  [AUTH_ERROR_CODES.SERVER_ERROR]: {
    messageKey: "error.server_error",
    retryable: true,
  },
  [AUTH_ERROR_CODES.API_ERROR]: {
    messageKey: "error.api_error",
    retryable: true,
  },
  [AUTH_ERROR_CODES.RATE_LIMITED]: {
    messageKey: "error.rate_limited",
    retryable: true,
  },
  [AUTH_ERROR_CODES.MAINTENANCE_MODE]: {
    messageKey: "error.maintenance_mode",
    retryable: true,
  },
  [AUTH_ERROR_CODES.VALIDATION_ERROR]: {
    messageKey: "error.validation_error",
    retryable: false,
  },
  [AUTH_ERROR_CODES.UNKNOWN_ERROR]: {
    messageKey: "error.unknown_error",
    retryable: true,
  },
};

// Error parsing and classification
export function parseError(error: unknown): AppError {
  // Handle string errors
  if (typeof error === "string") {
    return createError(AUTH_ERROR_CODES.UNKNOWN_ERROR, error);
  }

  // Handle Error objects
  if (error instanceof Error) {
    return classifyError(error);
  }

  // Handle Tauri invoke errors
  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message: string }).message;
    return classifyError(new Error(message));
  }

  // Fallback for unknown error types
  return createError(AUTH_ERROR_CODES.UNKNOWN_ERROR, i18n._("error.unknown_error"));
}

function classifyError(error: Error): AppError {
  const message = error.message.toLowerCase();

  // Network and connectivity errors
  if (message.includes("network") || message.includes("connection")) {
    return createError(AUTH_ERROR_CODES.NETWORK_ERROR, error.message);
  }

  if (message.includes("timeout")) {
    return createError(AUTH_ERROR_CODES.TIMEOUT_ERROR, error.message);
  }

  // Authentication errors
  if (
    message.includes("invalid") &&
    (message.includes("password") || message.includes("credentials"))
  ) {
    return createError(AUTH_ERROR_CODES.INVALID_CREDENTIALS, error.message);
  }

  if (message.includes("account") && message.includes("locked")) {
    return createError(AUTH_ERROR_CODES.ACCOUNT_LOCKED, error.message);
  }

  if (message.includes("not found") || (message.includes("user") && message.includes("not"))) {
    return createError(AUTH_ERROR_CODES.ACCOUNT_NOT_FOUND, error.message);
  }

  // Session errors
  if (message.includes("session") && message.includes("expired")) {
    return createError(AUTH_ERROR_CODES.SESSION_EXPIRED, error.message);
  }

  if (message.includes("token") && message.includes("invalid")) {
    return createError(AUTH_ERROR_CODES.INVALID_TOKEN, error.message);
  }

  // Vault errors
  if (message.includes("vault") && message.includes("locked")) {
    return createError(AUTH_ERROR_CODES.VAULT_LOCKED, error.message);
  }

  if (message.includes("decrypt") || message.includes("decryption")) {
    return createError(AUTH_ERROR_CODES.DECRYPTION_FAILED, error.message);
  }

  // Biometric errors
  if (message.includes("biometric")) {
    if (message.includes("not available")) {
      return createError(AUTH_ERROR_CODES.BIOMETRIC_NOT_AVAILABLE, error.message);
    }
    if (message.includes("not enrolled")) {
      return createError(AUTH_ERROR_CODES.BIOMETRIC_NOT_ENROLLED, error.message);
    }
    return createError(AUTH_ERROR_CODES.BIOMETRIC_FAILED, error.message);
  }

  // Server errors
  if (message.includes("server") || message.includes("500")) {
    return createError(AUTH_ERROR_CODES.SERVER_ERROR, error.message);
  }

  if (message.includes("rate limit") || message.includes("too many")) {
    return createError(AUTH_ERROR_CODES.RATE_LIMITED, error.message);
  }

  // Default to unknown error
  return createError(AUTH_ERROR_CODES.UNKNOWN_ERROR, error.message);
}

function createError(code: string, details: string): AppError {
  const errorInfo = ERROR_MESSAGES[code] || ERROR_MESSAGES[AUTH_ERROR_CODES.UNKNOWN_ERROR];

  return {
    code,
    message: details,
    userMessage: i18n._(errorInfo.messageKey),
    retryable: errorInfo.retryable,
    details,
  };
}

export function getUserMessage(error: AppError): string {
  return error.userMessage || error.message || i18n._("error.unknown_error");
}

export function isRetryable(error: AppError): boolean {
  return error.retryable ?? false;
}

export function reportError(error: Error, context?: Record<string, unknown>): void {
  // Log error to console in development
  if (import.meta.env.DEV) {
    console.error("Error reported:", error, context);
  }

  // In production, you would send this to your error tracking service
  // Example: Sentry, LogRocket, etc.
  // Sentry.captureException(error, { extra: context });
}

// Retry mechanism for retryable operations
export async function withRetry<T>(
  operation: () => Promise<T>,
  maxRetries = 3,
  delayMs = 1000,
  backoffMultiplier = 2
): Promise<T> {
  let lastError: AppError | undefined;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = parseError(error);

      // Don't retry if error is not retryable or this is the last attempt
      if (!isRetryable(lastError) || attempt === maxRetries) {
        throw lastError;
      }

      // Wait before retrying with exponential backoff
      const delay = delayMs * backoffMultiplier ** attempt;
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  throw lastError || new Error(i18n._("error.retry_failed"));
}
