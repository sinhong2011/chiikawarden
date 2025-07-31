use super::{CryptoError, CryptoResult};
use crate::debug_config::CorrelationId;
use crate::debug_token_op;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tauri::{AppHandle, Manager};
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredKeyData {
    pub key_data: Vec<u8>,
    pub created_at: u64,
    pub key_type: StoredKeyType,
    pub expires_at: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum StoredKeyType {
    BiometricKey,
    UserKey,
    MasterKeyHash,
    EncryptedUserKey,
    AccessToken,
    RefreshToken,
}

/// In-memory access token with expiry information
#[derive(Debug, Clone)]
pub struct AccessTokenData {
    pub token: String,
    pub expires_at: u64,
    pub created_at: u64,
}

impl AccessTokenData {
    pub fn new(token: String, expires_in_seconds: u64) -> Self {
        let current_time = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        // Apply 5-minute safety margin
        let safety_margin_seconds = 5 * 60;
        let expires_at = current_time + expires_in_seconds.saturating_sub(safety_margin_seconds);

        Self {
            token,
            expires_at,
            created_at: current_time,
        }
    }

    pub fn is_expired(&self) -> bool {
        let current_time = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        current_time >= self.expires_at
    }

    pub fn expires_in_seconds(&self) -> u64 {
        let current_time = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        if current_time >= self.expires_at {
            0
        } else {
            self.expires_at - current_time
        }
    }
}

/// Secure token manager that implements the new token storage architecture:
/// - Refresh tokens: Stored persistently in Tauri Stronghold (long-lived, 7-30 days)
/// - Access tokens: Stored in memory only (short-lived, 5-30 minutes)
/// - Automatic token refresh when access tokens expire
pub struct TokenManager {
    app_handle: AppHandle,
    access_tokens: Arc<RwLock<HashMap<String, AccessTokenData>>>,
    auth_service: Option<Arc<crate::api::services::auth_service::ApiAuthService>>,
    stronghold_client_name: String,
}

impl TokenManager {
    pub fn new(app_handle: AppHandle) -> Self {
        Self {
            app_handle,
            access_tokens: Arc::new(RwLock::new(HashMap::new())),
            auth_service: None,
            stronghold_client_name: "chiikawarden_tokens".to_string(),
        }
    }

    /// Get app data directory for file storage
    pub fn get_app_data_dir(&self) -> CryptoResult<std::path::PathBuf> {
        let app_data_dir = self
            .app_handle
            .path()
            .app_data_dir()
            .map_err(|e| CryptoError::Storage(format!("Failed to get app data dir: {}", e)))?;

        if !app_data_dir.exists() {
            std::fs::create_dir_all(&app_data_dir).map_err(|e| {
                CryptoError::Storage(format!("Failed to create app data directory: {}", e))
            })?;
        }

        Ok(app_data_dir)
    }

    /// Generate storage key name
    fn get_key_name(user_id: &str, key_type: &StoredKeyType) -> String {
        let prefix = match key_type {
            StoredKeyType::BiometricKey => "biometric_key",
            StoredKeyType::UserKey => "user_key",
            StoredKeyType::MasterKeyHash => "master_key_hash",
            StoredKeyType::EncryptedUserKey => "encrypted_user_key",
            StoredKeyType::AccessToken => "access_token",
            StoredKeyType::RefreshToken => "refresh_token",
        };
        format!("{}_{}.json", prefix, user_id)
    }

    /// Get current timestamp
    fn current_timestamp() -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
    }

    /// Retrieve a key from file
    async fn retrieve_key(
        &self,
        user_id: &str,
        key_type: StoredKeyType,
    ) -> CryptoResult<Option<Vec<u8>>> {
        let filename = Self::get_key_name(user_id, &key_type);
        let mut path = self.get_app_data_dir()?;
        path.push(&filename);

        let data = match tokio::fs::read(&path).await {
            Ok(data) => data,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                // Try fallback with old .key extension for backward compatibility
                let mut fallback_path = self.get_app_data_dir()?;
                fallback_path.push(format!("{}.key", filename));

                match tokio::fs::read(&fallback_path).await {
                    Ok(data) => {
                        debug!(
                            user_id = user_id,
                            key_type = ?key_type,
                            filename = format!("{}.key", filename),
                            "[token_manager] Key file found with old .key extension, migrating to new format"
                        );

                        // Migrate to new format by writing to the correct path
                        if let Err(write_err) = tokio::fs::write(&path, &data).await {
                            warn!(
                                user_id = user_id,
                                key_type = ?key_type,
                                error = %write_err,
                                "[token_manager] Failed to migrate key file to new format"
                            );
                        } else {
                            // Remove old file after successful migration
                            let _ = tokio::fs::remove_file(&fallback_path).await;
                            debug!(
                                user_id = user_id,
                                key_type = ?key_type,
                                "[token_manager] Successfully migrated key file to new format"
                            );
                        }

                        data
                    }
                    Err(_) => {
                        debug!(
                            user_id = user_id,
                            key_type = ?key_type,
                            filename = filename,
                            "[token_manager] Key file not found"
                        );
                        return Ok(None);
                    }
                }
            }
            Err(e) => {
                return Err(CryptoError::Storage(format!(
                    "Failed to read key file: {}",
                    e
                )));
            }
        };

        let stored_data: StoredKeyData = serde_json::from_slice(&data).map_err(|e| {
            CryptoError::Storage(format!("Failed to deserialize stored data: {}", e))
        })?;

        // Check if token is expired
        if let Some(expires_at) = stored_data.expires_at {
            let current_time = Self::current_timestamp();
            if current_time >= expires_at {
                debug!(
                    user_id = user_id,
                    key_type = ?key_type,
                    current_time = current_time,
                    expires_at = expires_at,
                    "[token_manager] Token expired, removing file"
                );

                // Remove expired token file
                let _ = tokio::fs::remove_file(&path).await;
                return Ok(None);
            }
        }

        debug!(
            user_id = user_id,
            key_type = ?key_type,
            filename = filename,
            data_size = stored_data.key_data.len(),
            "[token_manager] Successfully retrieved key from file"
        );

        Ok(Some(stored_data.key_data))
    }

    /// Delete a key file
    async fn delete_key(&self, user_id: &str, key_type: StoredKeyType) -> CryptoResult<()> {
        let filename = Self::get_key_name(user_id, &key_type);
        let mut path = self.get_app_data_dir()?;
        path.push(&filename);

        match tokio::fs::remove_file(&path).await {
            Ok(()) => {
                debug!(
                    user_id = user_id,
                    key_type = ?key_type,
                    filename = filename,
                    "[token_manager] Successfully deleted key file"
                );
                Ok(())
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                debug!(
                    user_id = user_id,
                    key_type = ?key_type,
                    filename = filename,
                    "[token_manager] Key file not found (already deleted)"
                );
                Ok(())
            }
            Err(e) => Err(CryptoError::Storage(format!(
                "Failed to delete key file: {}",
                e
            ))),
        }
    }

    /// Set the auth service for automatic token refresh
    pub fn set_auth_service(
        &mut self,
        auth_service: Arc<crate::api::services::auth_service::ApiAuthService>,
    ) {
        self.auth_service = Some(auth_service);
    }

    // File-based storage methods (fallback approach)
    // Note: Using file-based storage as stronghold plugin API is complex to integrate directly

    /// Store a key using file-based storage
    async fn store_key(
        &self,
        user_id: &str,
        key_type: StoredKeyType,
        key_data: &[u8],
        expires_at: Option<u64>,
    ) -> CryptoResult<()> {
        let key_name = Self::get_key_name(user_id, &key_type);

        let stored_data = StoredKeyData {
            key_data: key_data.to_vec(),
            created_at: Self::current_timestamp(),
            key_type: key_type.clone(),
            expires_at,
        };

        let serialized_data = serde_json::to_vec(&stored_data)
            .map_err(|e| CryptoError::Storage(format!("Failed to serialize key data: {}", e)))?;

        // Store in app data directory
        let mut path = self.get_app_data_dir()?;
        path.push(&key_name);

        tokio::fs::write(&path, &serialized_data)
            .await
            .map_err(|e| CryptoError::Storage(format!("Failed to write key file: {}", e)))?;

        debug!(
            user_id = user_id,
            key_type = ?key_type,
            key_name = key_name,
            "[token_manager] Key stored successfully"
        );

        Ok(())
    }

    /// Store refresh token persistently in stronghold
    pub async fn store_refresh_token(&self, user_id: &str, token: &str) -> CryptoResult<()> {
        self.store_refresh_token_with_correlation(user_id, token, None)
            .await
    }

    /// Store encrypted user key for session restoration
    pub async fn store_encrypted_user_key(
        &self,
        user_id: &str,
        encrypted_user_key: &[u8],
    ) -> CryptoResult<()> {
        let correlation_id = CorrelationId::new();

        debug_token_op!(
            user_id = user_id,
            operation = "store_encrypted_user_key",
            correlation_id = %correlation_id,
            data_length = encrypted_user_key.len(),
            "[token_manager] Storing encrypted user key for session restoration"
        );

        // Use file-based storage for encrypted user key
        let key = format!("encrypted_user_key_{}", user_id);
        let mut file_path = self.get_app_data_dir()?;
        file_path.push(&key);

        // Ensure directory exists
        if let Some(parent) = file_path.parent() {
            tokio::fs::create_dir_all(parent).await.map_err(|e| {
                CryptoError::Storage(format!("Failed to create storage directory: {}", e))
            })?;
        }

        tokio::fs::write(&file_path, encrypted_user_key)
            .await
            .map_err(|e| {
                CryptoError::Storage(format!("Failed to store encrypted user key: {}", e))
            })?;

        debug_token_op!(
            user_id = user_id,
            operation = "store_encrypted_user_key",
            correlation_id = %correlation_id,
            "[token_manager] Encrypted user key stored successfully"
        );

        Ok(())
    }

    /// Store refresh token persistently in stronghold with correlation ID
    pub async fn store_refresh_token_with_correlation(
        &self,
        user_id: &str,
        token: &str,
        correlation_id: Option<&CorrelationId>,
    ) -> CryptoResult<()> {
        let correlation_id = correlation_id.cloned().unwrap_or_else(CorrelationId::new);

        debug_token_op!(
            user_id = user_id,
            operation = "store_refresh_token",
            correlation_id = %correlation_id,
            token_length = token.len(),
            "[token_manager] Storing refresh token in stronghold (persistent)"
        );

        self.store_key(user_id, StoredKeyType::RefreshToken, token.as_bytes(), None)
            .await
    }

    /// Retrieve refresh token from stronghold
    pub async fn retrieve_refresh_token(&self, user_id: &str) -> CryptoResult<Option<String>> {
        self.retrieve_refresh_token_with_correlation(user_id, None)
            .await
    }

    /// Retrieve encrypted user key for session restoration
    pub async fn retrieve_encrypted_user_key(
        &self,
        user_id: &str,
    ) -> CryptoResult<Option<Vec<u8>>> {
        let correlation_id = CorrelationId::new();

        debug_token_op!(
            user_id = user_id,
            operation = "retrieve_encrypted_user_key",
            correlation_id = %correlation_id,
            "[token_manager] Attempting to retrieve encrypted user key for session restoration"
        );

        let key = format!("encrypted_user_key_{}", user_id);
        let mut file_path = self.get_app_data_dir()?;
        file_path.push(&key);

        match tokio::fs::read(&file_path).await {
            Ok(data) => {
                debug_token_op!(
                    user_id = user_id,
                    operation = "retrieve_encrypted_user_key",
                    correlation_id = %correlation_id,
                    data_length = data.len(),
                    "[token_manager] Successfully retrieved encrypted user key"
                );
                Ok(Some(data))
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                debug_token_op!(
                    user_id = user_id,
                    operation = "retrieve_encrypted_user_key",
                    correlation_id = %correlation_id,
                    "[token_manager] No encrypted user key found for user"
                );
                Ok(None)
            }
            Err(e) => {
                error!(
                    user_id = user_id,
                    operation = "retrieve_encrypted_user_key",
                    correlation_id = %correlation_id,
                    error = %e,
                    "[token_manager] Failed to retrieve encrypted user key"
                );
                Err(CryptoError::Storage(format!(
                    "Failed to retrieve encrypted user key: {}",
                    e
                )))
            }
        }
    }

    /// Retrieve refresh token from stronghold with correlation ID
    pub async fn retrieve_refresh_token_with_correlation(
        &self,
        user_id: &str,
        correlation_id: Option<&CorrelationId>,
    ) -> CryptoResult<Option<String>> {
        let correlation_id = correlation_id.cloned().unwrap_or_else(CorrelationId::new);

        info!(
            user_id = user_id,
            operation = "retrieve_refresh_token",
            correlation_id = %correlation_id,
            "[token_manager] Attempting to retrieve refresh token from stronghold - this is CRITICAL for API access"
        );

        match self
            .retrieve_key(user_id, StoredKeyType::RefreshToken)
            .await?
        {
            Some(token_bytes) => match String::from_utf8(token_bytes) {
                Ok(token) => {
                    info!(
                        user_id = user_id,
                        operation = "retrieve_refresh_token",
                        correlation_id = %correlation_id,
                        token_length = token.len(),
                        token_preview = &token[..std::cmp::min(20, token.len())],
                        "[token_manager] Successfully retrieved refresh token - API calls should work"
                    );
                    Ok(Some(token))
                }
                Err(e) => {
                    error!(
                        user_id = user_id,
                        operation = "retrieve_refresh_token",
                        correlation_id = %correlation_id,
                        error = %e,
                        "[token_manager] CRITICAL: Stored refresh token is corrupted (invalid UTF-8) - API calls will fail"
                    );
                    Err(CryptoError::Storage(format!(
                        "Invalid UTF-8 in stored token: {}",
                        e
                    )))
                }
            },
            None => {
                error!(
                    user_id = user_id,
                    operation = "retrieve_refresh_token",
                    correlation_id = %correlation_id,
                    "[token_manager] CRITICAL: No refresh token found in stronghold - user needs to login again"
                );
                Ok(None)
            }
        }
    }

    /// Store access token in memory only (ephemeral)
    pub async fn store_access_token(
        &self,
        user_id: &str,
        token: &str,
        expires_in_seconds: u64,
    ) -> CryptoResult<()> {
        self.store_access_token_with_correlation(user_id, token, expires_in_seconds, None)
            .await
    }

    /// Store access token in memory only with correlation ID
    pub async fn store_access_token_with_correlation(
        &self,
        user_id: &str,
        token: &str,
        expires_in_seconds: u64,
        correlation_id: Option<&CorrelationId>,
    ) -> CryptoResult<()> {
        let correlation_id = correlation_id.cloned().unwrap_or_else(CorrelationId::new);

        debug_token_op!(
            user_id = user_id,
            operation = "store_access_token",
            correlation_id = %correlation_id,
            expires_in_seconds = expires_in_seconds,
            token_length = token.len(),
            "[token_manager] Storing access token in memory (ephemeral)"
        );

        let token_data = AccessTokenData::new(token.to_string(), expires_in_seconds);
        let mut access_tokens = self.access_tokens.write().await;
        access_tokens.insert(user_id.to_string(), token_data);

        debug_token_op!(
            user_id = user_id,
            operation = "store_access_token",
            correlation_id = %correlation_id,
            expires_at = access_tokens.get(user_id).unwrap().expires_at,
            "[token_manager] Access token stored in memory successfully"
        );

        Ok(())
    }

    /// Retrieve access token from memory, with automatic refresh if expired
    pub async fn retrieve_access_token(&self, user_id: &str) -> CryptoResult<Option<String>> {
        self.retrieve_access_token_with_correlation(user_id, None)
            .await
    }

    /// Retrieve access token from memory with correlation ID, with automatic refresh if expired
    pub async fn retrieve_access_token_with_correlation(
        &self,
        user_id: &str,
        correlation_id: Option<&CorrelationId>,
    ) -> CryptoResult<Option<String>> {
        let correlation_id = correlation_id.cloned().unwrap_or_else(CorrelationId::new);

        debug_token_op!(
            user_id = user_id,
            operation = "retrieve_access_token",
            correlation_id = %correlation_id,
            "[token_manager] Retrieving access token from memory"
        );

        // Check if we have a valid access token in memory
        {
            let access_tokens = self.access_tokens.read().await;
            if let Some(token_data) = access_tokens.get(user_id) {
                if !token_data.is_expired() {
                    debug_token_op!(
                        user_id = user_id,
                        operation = "retrieve_access_token",
                        correlation_id = %correlation_id,
                        expires_in = token_data.expires_in_seconds(),
                        "[token_manager] Valid access token found in memory"
                    );
                    return Ok(Some(token_data.token.clone()));
                } else {
                    debug_token_op!(
                        user_id = user_id,
                        operation = "retrieve_access_token",
                        correlation_id = %correlation_id,
                        "[token_manager] Access token expired, attempting automatic refresh"
                    );
                }
            } else {
                debug_token_op!(
                    user_id = user_id,
                    operation = "retrieve_access_token",
                    correlation_id = %correlation_id,
                    "[token_manager] No access token in memory, attempting automatic refresh"
                );
            }
        }

        // Try to refresh the token automatically
        match self
            .refresh_access_token_with_correlation(user_id, Some(&correlation_id))
            .await
        {
            Ok(()) => {
                // Try to get the refreshed token
                let access_tokens = self.access_tokens.read().await;
                if let Some(token_data) = access_tokens.get(user_id) {
                    debug_token_op!(
                        user_id = user_id,
                        operation = "retrieve_access_token",
                        correlation_id = %correlation_id,
                        "[token_manager] Successfully refreshed and retrieved access token"
                    );
                    Ok(Some(token_data.token.clone()))
                } else {
                    warn!(
                        user_id = user_id,
                        operation = "retrieve_access_token",
                        correlation_id = %correlation_id,
                        "[token_manager] Token refresh succeeded but no token found in memory"
                    );
                    Ok(None)
                }
            }
            Err(e) => {
                warn!(
                    user_id = user_id,
                    operation = "retrieve_access_token",
                    correlation_id = %correlation_id,
                    error = %e,
                    "[token_manager] Automatic token refresh failed: {}", e
                );
                Ok(None)
            }
        }
    }

    /// Check if access token is expired
    pub async fn is_access_token_expired(&self, user_id: &str) -> CryptoResult<bool> {
        let access_tokens = self.access_tokens.read().await;
        match access_tokens.get(user_id) {
            Some(token_data) => Ok(token_data.is_expired()),
            None => Ok(true), // No token means expired
        }
    }

    /// Refresh access token using stored refresh token
    pub async fn refresh_access_token(&self, user_id: &str) -> CryptoResult<()> {
        self.refresh_access_token_with_correlation(user_id, None)
            .await
    }

    /// Refresh access token using stored refresh token with correlation ID
    pub async fn refresh_access_token_with_correlation(
        &self,
        user_id: &str,
        correlation_id: Option<&CorrelationId>,
    ) -> CryptoResult<()> {
        let correlation_id = correlation_id.cloned().unwrap_or_else(CorrelationId::new);

        info!(
            user_id = user_id,
            operation = "refresh_access_token",
            correlation_id = %correlation_id,
            "[token_manager] Starting automatic token refresh - this is CRITICAL for API access"
        );

        // Get auth service
        let auth_service = self.auth_service.as_ref()
            .ok_or_else(|| {
                error!(
                    user_id = user_id,
                    operation = "refresh_access_token",
                    correlation_id = %correlation_id,
                    "[token_manager] CRITICAL: Auth service not available for token refresh - API calls will fail"
                );
                CryptoError::Storage("Auth service not available for token refresh".to_string())
            })?;

        // Get refresh token from stronghold
        info!(
            user_id = user_id,
            operation = "refresh_access_token",
            correlation_id = %correlation_id,
            "[token_manager] Retrieving stored refresh token for API refresh"
        );

        let refresh_token = self.retrieve_refresh_token_with_correlation(user_id, Some(&correlation_id)).await?
            .ok_or_else(|| {
                error!(
                    user_id = user_id,
                    operation = "refresh_access_token",
                    correlation_id = %correlation_id,
                    "[token_manager] CRITICAL: No refresh token found for automatic refresh - user must login again"
                );
                CryptoError::Storage("No refresh token found for automatic refresh".to_string())
            })?;

        info!(
            user_id = user_id,
            operation = "refresh_access_token",
            correlation_id = %correlation_id,
            refresh_token_length = refresh_token.len(),
            "[token_manager] Found refresh token, calling API to get new access token"
        );

        // Call API to refresh token
        let response = auth_service.refresh_token(&refresh_token).await
            .map_err(|e| {
                error!(
                    user_id = user_id,
                    operation = "refresh_access_token",
                    correlation_id = %correlation_id,
                    error = %e,
                    "[token_manager] CRITICAL: API token refresh failed - all API calls will fail: {}", e
                );
                CryptoError::Storage(format!("Token refresh API call failed: {}", e))
            })?;

        info!(
            user_id = user_id,
            operation = "refresh_access_token",
            correlation_id = %correlation_id,
            expires_in = response.expires_in,
            access_token_length = response.access_token.len(),
            has_new_refresh_token = !response.refresh_token.is_empty(),
            new_refresh_token_length = if !response.refresh_token.is_empty() { response.refresh_token.len() } else { 0 },
            "[token_manager] Token refresh API call successful - updating stored tokens"
        );

        // Store new access token in memory
        self.store_access_token_with_correlation(
            user_id,
            &response.access_token,
            response.expires_in,
            Some(&correlation_id),
        )
        .await?;

        // Store new refresh token if provided
        if !response.refresh_token.is_empty() {
            self.store_refresh_token_with_correlation(
                user_id,
                &response.refresh_token,
                Some(&correlation_id),
            )
            .await?;
        }

        // Attempt to restore user key for cipher decryption
        self.restore_user_key_if_needed(user_id, &correlation_id)
            .await;

        info!(
            user_id = user_id,
            operation = "refresh_access_token",
            correlation_id = %correlation_id,
            "[token_manager] Automatic token refresh completed successfully"
        );

        Ok(())
    }

    /// Restore user key for cipher decryption if needed and possible
    async fn restore_user_key_if_needed(&self, user_id: &str, correlation_id: &CorrelationId) {
        use crate::crypto::cache::CRYPTO_CACHE;

        // Check if user key is already cached
        match CRYPTO_CACHE.get_user_key(user_id) {
            Ok(Some(_)) => {
                debug_token_op!(
                    user_id = user_id,
                    operation = "restore_user_key",
                    correlation_id = %correlation_id,
                    "[token_manager] User key already cached, no restoration needed"
                );
                return;
            }
            Ok(None) => {
                info!(
                    user_id = user_id,
                    operation = "restore_user_key",
                    correlation_id = %correlation_id,
                    "[token_manager] User key not cached, attempting restoration for cipher decryption"
                );
            }
            Err(e) => {
                warn!(
                    user_id = user_id,
                    operation = "restore_user_key",
                    correlation_id = %correlation_id,
                    error = %e,
                    "[token_manager] Failed to check user key cache status"
                );
                return;
            }
        }

        // Try to retrieve stored encrypted user key
        let encrypted_user_key_data = match self.retrieve_encrypted_user_key(user_id).await {
            Ok(Some(data)) => data,
            Ok(None) => {
                warn!(
                    user_id = user_id,
                    operation = "restore_user_key",
                    correlation_id = %correlation_id,
                    "[token_manager] No stored encrypted user key found - user needs to login again for cipher decryption"
                );
                return;
            }
            Err(e) => {
                error!(
                    user_id = user_id,
                    operation = "restore_user_key",
                    correlation_id = %correlation_id,
                    error = %e,
                    "[token_manager] Failed to retrieve encrypted user key"
                );
                return;
            }
        };

        // Try to retrieve stored master key from secure storage
        let master_key = {
            use tauri::Manager;
            let app_state: tauri::State<crate::app_state::AppState> = self.app_handle.state();
            let secure_storage = app_state.secure_storage();

            match secure_storage.get_master_key(user_id).await {
                Ok(key_bytes) => {
                    debug_token_op!(
                        user_id = user_id,
                        operation = "restore_user_key",
                        correlation_id = %correlation_id,
                        "[token_manager] Found stored master key, attempting user key restoration"
                    );
                    crate::crypto::MasterKey::new(key_bytes)
                }
                Err(e) => {
                    warn!(
                        user_id = user_id,
                        operation = "restore_user_key",
                        correlation_id = %correlation_id,
                        error = %e,
                        "[token_manager] No stored master key found - user needs to re-authenticate for cipher decryption"
                    );
                    return;
                }
            }
        };

        // Convert encrypted user key data to base64 for consistent derivation
        use base64::{engine::general_purpose, Engine as _};
        let encrypted_user_key_b64 = general_purpose::STANDARD.encode(&encrypted_user_key_data);

        // Use new user key derivation from server to restore the user key
        let correlation_id = crate::debug_config::CorrelationId::new();
        match crate::crypto::KeyDerivationService::derive_user_key_from_server(
            &encrypted_user_key_b64,
            &master_key,
            user_id,
            &correlation_id,
        ) {
            Ok(user_key) => {
                // Store the restored user key in cache
                match CRYPTO_CACHE.store_user_key(user_id.to_string(), user_key) {
                    Ok(()) => {
                        info!(
                            user_id = user_id,
                            operation = "restore_user_key",
                            correlation_id = %correlation_id,
                            "[token_manager] Successfully restored and cached user key for cipher decryption"
                        );
                    }
                    Err(e) => {
                        error!(
                            user_id = user_id,
                            operation = "restore_user_key",
                            correlation_id = %correlation_id,
                            error = %e,
                            "[token_manager] Failed to store restored user key in cache"
                        );
                    }
                }
            }
            Err(e) => {
                error!(
                    user_id = user_id,
                    operation = "restore_user_key",
                    correlation_id = %correlation_id,
                    error = %e,
                    "[token_manager] Failed to derive user key consistently during restoration"
                );
            }
        }
    }

    /// Delete access token from memory
    pub async fn delete_access_token(&self, user_id: &str) -> CryptoResult<()> {
        debug!(
            user_id = user_id,
            "[token_manager] Deleting access token from memory"
        );

        let mut access_tokens = self.access_tokens.write().await;
        access_tokens.remove(user_id);

        debug!(
            user_id = user_id,
            "[token_manager] Access token deleted from memory"
        );

        Ok(())
    }

    /// Delete refresh token from storage
    pub async fn delete_refresh_token(&self, user_id: &str) -> CryptoResult<()> {
        debug!(
            user_id = user_id,
            "[token_manager] Deleting refresh token from storage"
        );

        self.delete_key(user_id, StoredKeyType::RefreshToken).await
    }

    /// Clear all tokens for a user (both memory and stronghold)
    pub async fn clear_user_tokens(&self, user_id: &str) -> CryptoResult<()> {
        debug!(
            user_id = user_id,
            "[token_manager] Clearing all tokens for user"
        );

        // Clear access token from memory
        self.delete_access_token(user_id).await?;

        // Clear refresh token from stronghold
        self.delete_refresh_token(user_id).await?;

        debug!(
            user_id = user_id,
            "[token_manager] All tokens cleared for user"
        );

        Ok(())
    }

    /// Clear all access tokens from memory (useful for logout scenarios)
    pub async fn clear_all_access_tokens(&self) -> CryptoResult<()> {
        debug!("[token_manager] Clearing all access tokens from memory");

        let mut access_tokens = self.access_tokens.write().await;
        access_tokens.clear();

        debug!("[token_manager] All access tokens cleared from memory");
        Ok(())
    }

    /// Get access token expiry information
    pub async fn get_access_token_expiry(&self, user_id: &str) -> CryptoResult<Option<u64>> {
        let access_tokens = self.access_tokens.read().await;
        match access_tokens.get(user_id) {
            Some(token_data) => Ok(Some(token_data.expires_at)),
            None => Ok(None),
        }
    }

    /// Get access token remaining time in seconds
    pub async fn get_access_token_remaining_time(
        &self,
        user_id: &str,
    ) -> CryptoResult<Option<u64>> {
        let access_tokens = self.access_tokens.read().await;
        match access_tokens.get(user_id) {
            Some(token_data) => Ok(Some(token_data.expires_in_seconds())),
            None => Ok(None),
        }
    }

    /// Check if user has valid tokens (both access and refresh)
    pub async fn has_valid_tokens(&self, user_id: &str) -> CryptoResult<bool> {
        // Check if we have a refresh token in stronghold
        let has_refresh_token = self.retrieve_refresh_token(user_id).await?.is_some();

        if !has_refresh_token {
            return Ok(false);
        }

        // Check if we have a valid access token or can refresh it
        match self.retrieve_access_token(user_id).await? {
            Some(_) => Ok(true),
            None => Ok(false),
        }
    }

    /// Validate storage backend
    pub async fn validate_backend(&self) -> CryptoResult<()> {
        self.validate_backend_with_correlation(None).await
    }

    /// Validate storage backend with correlation ID
    pub async fn validate_backend_with_correlation(
        &self,
        correlation_id: Option<&CorrelationId>,
    ) -> CryptoResult<()> {
        let correlation_id = correlation_id.cloned().unwrap_or_else(CorrelationId::new);

        debug!(
            operation = "validate_backend",
            correlation_id = %correlation_id,
            "[token_manager] Starting storage backend validation"
        );

        // Test that we can access the app data directory
        let _app_data_dir = self.get_app_data_dir()?;

        // Test store/retrieve operation
        let test_user_id = "backend_test_user";
        let test_data = b"test_value";

        self.store_key(test_user_id, StoredKeyType::RefreshToken, test_data, None)
            .await?;

        let retrieved_data = self
            .retrieve_key(test_user_id, StoredKeyType::RefreshToken)
            .await?;

        if retrieved_data.as_deref() != Some(test_data) {
            return Err(CryptoError::Storage(
                "Retrieved data doesn't match stored data".to_string(),
            ));
        }

        // Clean up test data
        let _ = self
            .delete_key(test_user_id, StoredKeyType::RefreshToken)
            .await;

        debug!(
            operation = "validate_backend",
            correlation_id = %correlation_id,
            "[token_manager] Storage backend validation successful"
        );

        Ok(())
    }

    // Key storage methods

    /// Store biometric key
    pub async fn store_biometric_key(&self, user_id: &str, key: &[u8]) -> CryptoResult<()> {
        self.store_key(user_id, StoredKeyType::BiometricKey, key, None)
            .await
    }

    /// Retrieve biometric key
    pub async fn retrieve_biometric_key(&self, user_id: &str) -> CryptoResult<Option<Vec<u8>>> {
        self.retrieve_key(user_id, StoredKeyType::BiometricKey)
            .await
    }

    /// Delete biometric key
    pub async fn delete_biometric_key(&self, user_id: &str) -> CryptoResult<()> {
        self.delete_key(user_id, StoredKeyType::BiometricKey).await
    }

    /// Store master key hash
    pub async fn store_master_key_hash(&self, user_id: &str, hash: &str) -> CryptoResult<()> {
        self.store_key(user_id, StoredKeyType::MasterKeyHash, hash.as_bytes(), None)
            .await
    }

    /// Retrieve master key hash
    pub async fn retrieve_master_key_hash(&self, user_id: &str) -> CryptoResult<Option<String>> {
        match self
            .retrieve_key(user_id, StoredKeyType::MasterKeyHash)
            .await?
        {
            Some(hash_bytes) => {
                let hash = String::from_utf8(hash_bytes)
                    .map_err(|e| CryptoError::Storage(format!("Invalid hash format: {}", e)))?;
                Ok(Some(hash))
            }
            None => Ok(None),
        }
    }

    /// Clear all keys for a user (including tokens)
    pub async fn clear_all_user_data(&self, user_id: &str) -> CryptoResult<()> {
        debug!(
            user_id = user_id,
            "[token_manager] Clearing all user data (tokens and keys)"
        );

        // Clear access token from memory
        self.delete_access_token(user_id).await?;

        // Clear all data from storage
        let key_types = [
            StoredKeyType::RefreshToken,
            StoredKeyType::BiometricKey,
            StoredKeyType::UserKey,
            StoredKeyType::MasterKeyHash,
            StoredKeyType::EncryptedUserKey,
        ];

        for key_type in &key_types {
            let _ = self.delete_key(user_id, key_type.clone()).await; // Ignore errors for non-existent keys
        }

        debug!(user_id = user_id, "[token_manager] All user data cleared");

        Ok(())
    }

    // Local data storage methods (for biometrics and other local data)

    /// Store local data with a custom filename
    pub async fn store_local_data(&self, filename: &str, data: &[u8]) -> CryptoResult<()> {
        let mut path = self.get_app_data_dir()?;
        path.push(filename);

        tokio::fs::write(&path, data)
            .await
            .map_err(|e| CryptoError::Storage(format!("Failed to write local data file: {}", e)))?;

        debug!(
            filename = filename,
            data_size = data.len(),
            "[token_manager] Successfully stored local data"
        );

        Ok(())
    }

    /// Retrieve local data with a custom filename
    pub async fn retrieve_local_data(&self, filename: &str) -> CryptoResult<Option<Vec<u8>>> {
        let mut path = self.get_app_data_dir()?;
        path.push(filename);

        match tokio::fs::read(&path).await {
            Ok(data) => {
                debug!(
                    filename = filename,
                    data_size = data.len(),
                    "[token_manager] Successfully retrieved local data"
                );
                Ok(Some(data))
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                debug!(
                    filename = filename,
                    "[token_manager] Local data file not found"
                );
                Ok(None)
            }
            Err(e) => Err(CryptoError::Storage(format!(
                "Failed to read local data file: {}",
                e
            ))),
        }
    }

    /// Delete local data with a custom filename
    pub async fn delete_local_data(&self, filename: &str) -> CryptoResult<()> {
        let mut path = self.get_app_data_dir()?;
        path.push(filename);

        match tokio::fs::remove_file(&path).await {
            Ok(()) => {
                debug!(
                    filename = filename,
                    "[token_manager] Successfully deleted local data file"
                );
                Ok(())
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                debug!(
                    filename = filename,
                    "[token_manager] Local data file not found (already deleted)"
                );
                Ok(())
            }
            Err(e) => Err(CryptoError::Storage(format!(
                "Failed to delete local data file: {}",
                e
            ))),
        }
    }

    /// Check if a key exists for a user
    pub async fn has_key(&self, user_id: &str, key_type: StoredKeyType) -> CryptoResult<bool> {
        let filename = Self::get_key_name(user_id, &key_type);
        let mut path = self.get_app_data_dir()?;
        path.push(&filename);

        Ok(path.exists())
    }
}
