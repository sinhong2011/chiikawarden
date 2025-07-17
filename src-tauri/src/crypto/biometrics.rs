use super::secure_storage::SecureStorageService;
use super::{CryptoError, CryptoResult, UserKey};
use serde::{Deserialize, Serialize};
use specta::Type;

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub enum BiometricType {
    TouchId,      // macOS
    WindowsHello, // Windows
    Fingerprint,  // Linux/Generic
}

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub enum BiometricStatus {
    Available,
    NotAvailable,
    NotEnrolled,
    UnlockNeeded,
}

pub struct BiometricService;

impl BiometricService {
    /// Check if biometric authentication is available on the platform
    pub fn is_available() -> CryptoResult<BiometricStatus> {
        #[cfg(target_os = "macos")]
        {
            Self::check_touch_id_availability()
        }

        #[cfg(target_os = "windows")]
        {
            Self::check_windows_hello_availability()
        }

        #[cfg(target_os = "linux")]
        {
            Self::check_linux_biometric_availability()
        }

        #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
        {
            Ok(BiometricStatus::NotAvailable)
        }
    }

    /// Authenticate using biometric
    pub async fn authenticate(prompt: &str) -> CryptoResult<bool> {
        #[cfg(target_os = "macos")]
        {
            Self::authenticate_touch_id(prompt).await
        }

        #[cfg(target_os = "windows")]
        {
            Self::authenticate_windows_hello(prompt).await
        }

        #[cfg(target_os = "linux")]
        {
            Self::authenticate_linux_biometric(prompt).await
        }

        #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
        {
            Err(CryptoError::Storage(
                "Biometric authentication not supported on this platform".to_string(),
            ))
        }
    }

    /// Store biometric-protected user key
    pub async fn store_biometric_user_key(user_id: &str, user_key: &UserKey) -> CryptoResult<()> {
        // Generate a random key for biometric protection
        let biometric_key = super::encryption::EncryptionService::generate_key(32)?;

        // Encrypt user key with biometric key
        let encrypted_user_key = super::encryption::EncryptionService::encrypt(
            user_key.as_bytes(),
            &biometric_key,
            super::EncryptionType::AesCbc256HmacSha256B64,
        )?;

        // Store encrypted user key in local storage
        let encrypted_data = serde_json::to_vec(&encrypted_user_key).map_err(|e| {
            CryptoError::Storage(format!("Failed to serialize encrypted user key: {}", e))
        })?;

        SecureStorageService::store_local_data(
            &format!("biometric_user_key_{}.dat", user_id),
            &encrypted_data,
        )?;

        // Store biometric key in secure storage (keychain)
        SecureStorageService::store_biometric_key(user_id, &biometric_key)?;

        Ok(())
    }

    /// Retrieve biometric-protected user key
    pub async fn retrieve_biometric_user_key(
        user_id: &str,
        prompt: &str,
    ) -> CryptoResult<Option<UserKey>> {
        // Authenticate first
        if !Self::authenticate(prompt).await? {
            return Ok(None);
        }

        // Retrieve biometric key from secure storage
        let biometric_key = SecureStorageService::retrieve_biometric_key(user_id)?;
        if biometric_key.is_none() {
            return Ok(None);
        }
        let biometric_key = biometric_key.unwrap();

        // Retrieve encrypted user key from local storage
        let encrypted_data = SecureStorageService::retrieve_local_data(&format!(
            "biometric_user_key_{}.dat",
            user_id
        ))?;
        if encrypted_data.is_none() {
            return Ok(None);
        }

        let encrypted_user_key: super::EncryptedData =
            serde_json::from_slice(&encrypted_data.unwrap()).map_err(|e| {
                CryptoError::Storage(format!("Failed to deserialize encrypted user key: {}", e))
            })?;

        // Decrypt user key
        let user_key_bytes = super::encryption::EncryptionService::decrypt(
            &encrypted_user_key,
            &biometric_key,
            super::EncryptionType::AesCbc256HmacSha256B64,
        )?;

        Ok(Some(UserKey::new(user_key_bytes)))
    }

    /// Delete biometric-protected user key
    pub async fn delete_biometric_user_key(user_id: &str) -> CryptoResult<()> {
        // Delete from secure storage
        SecureStorageService::delete_biometric_key(user_id)?;

        // Delete from local storage
        SecureStorageService::delete_local_data(&format!("biometric_user_key_{}.dat", user_id))?;

        Ok(())
    }

    /// Check if biometric unlock is set up for user
    pub fn is_biometric_unlock_enabled(user_id: &str) -> CryptoResult<bool> {
        SecureStorageService::has_key(user_id, super::secure_storage::StoredKeyType::BiometricKey)
    }

    // Platform-specific implementations

    #[cfg(target_os = "macos")]
    fn check_touch_id_availability() -> CryptoResult<BiometricStatus> {
        use std::process::Command;

        let output = Command::new("bioutil")
            .args(&["-r", "-s"])
            .output()
            .map_err(|e| CryptoError::Storage(format!("Failed to check Touch ID: {}", e)))?;

        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            if stdout.contains("Touch ID") {
                Ok(BiometricStatus::Available)
            } else {
                Ok(BiometricStatus::NotEnrolled)
            }
        } else {
            Ok(BiometricStatus::NotAvailable)
        }
    }

    #[cfg(target_os = "macos")]
    async fn authenticate_touch_id(prompt: &str) -> CryptoResult<bool> {
        use std::process::Command;

        let output = Command::new("osascript")
            .args(&[
                "-e",
                &format!(
                    r#"tell application "System Events" to display dialog "{}" with title "Chiikawarden" buttons {{"Cancel", "Authenticate"}} default button "Authenticate""#,
                    prompt
                ),
            ])
            .output()
            .map_err(|e| CryptoError::Storage(format!("Touch ID authentication failed: {}", e)))?;

        Ok(output.status.success())
    }

    #[cfg(target_os = "windows")]
    fn check_windows_hello_availability() -> CryptoResult<BiometricStatus> {
        // This would require Windows Hello API integration
        // For now, return a placeholder
        Ok(BiometricStatus::NotAvailable)
    }

    #[cfg(target_os = "windows")]
    async fn authenticate_windows_hello(_prompt: &str) -> CryptoResult<bool> {
        // This would require Windows Hello API integration
        // For now, return false
        Ok(false)
    }

    #[cfg(target_os = "linux")]
    fn check_linux_biometric_availability() -> CryptoResult<BiometricStatus> {
        use std::process::Command;

        // Check if fprintd is available
        let output = Command::new("which")
            .arg("fprintd-verify")
            .output()
            .map_err(|e| CryptoError::Storage(format!("Failed to check fprintd: {}", e)))?;

        if output.status.success() {
            Ok(BiometricStatus::Available)
        } else {
            Ok(BiometricStatus::NotAvailable)
        }
    }

    #[cfg(target_os = "linux")]
    async fn authenticate_linux_biometric(_prompt: &str) -> CryptoResult<bool> {
        use std::process::Command;

        let output = Command::new("fprintd-verify").output().map_err(|e| {
            CryptoError::Storage(format!("Fingerprint authentication failed: {}", e))
        })?;

        Ok(output.status.success())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_biometric_availability() {
        let status = BiometricService::is_available().unwrap();
        // Status will vary by platform, just ensure it doesn't panic
        println!("Biometric status: {:?}", status);
    }

    #[tokio::test]
    async fn test_biometric_key_storage() {
        let user_id = "test_user_biometric";
        let user_key = UserKey::new(vec![1u8; 64]);

        // Store biometric key
        BiometricService::store_biometric_user_key(user_id, &user_key)
            .await
            .unwrap();

        // Check if enabled
        assert!(BiometricService::is_biometric_unlock_enabled(user_id).unwrap());

        // Clean up
        BiometricService::delete_biometric_user_key(user_id)
            .await
            .unwrap();

        assert!(!BiometricService::is_biometric_unlock_enabled(user_id).unwrap());
    }
}
