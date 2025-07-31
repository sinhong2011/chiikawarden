import type { AppError } from "@/lib/tauri-commands";

/**
 * Helper function to extract error message from AppError union type
 */
export const getErrorMessage = (error: AppError | undefined): string | undefined => {
  if (!error) return undefined;
  
  if ('AuthenticationError' in error) return error.AuthenticationError.message;
  if ('CryptographyError' in error) return error.CryptographyError.operation;
  if ('DatabaseError' in error) return error.DatabaseError.message;
  if ('NetworkError' in error) return error.NetworkError.message;
  if ('StorageError' in error) return error.StorageError.message;
  if ('ValidationError' in error) return error.ValidationError.message;
  if ('ConfigurationError' in error) return error.ConfigurationError.message;
  if ('BiometricError' in error) return error.BiometricError.message;
  if ('SyncError' in error) return error.SyncError.message;
  if ('InternalError' in error) return error.InternalError.message;
  
  return "Unknown error";
};
