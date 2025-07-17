use crate::error::AppResult;
use async_trait::async_trait;
use serde_json::Value;

/// Authentication repository trait for handling auth-related API operations
#[async_trait]
pub trait AuthRepository {
    /// Get KDF settings for user before login (prelogin)
    async fn prelogin(&self, email: &str) -> AppResult<Value>;

    /// Login with email and password
    async fn login(
        &self,
        email: &str,
        password_hash: &str,
        two_factor_token: Option<&str>,
    ) -> AppResult<Value>;

    /// Refresh access token
    async fn refresh_access_token(&self, refresh_token: &str) -> AppResult<Value>;

    /// Get user profile
    async fn get_profile(&self, access_token: &str) -> AppResult<Value>;

    /// Logout (revoke token)
    async fn logout(&self, access_token: &str) -> AppResult<()>;
}

/// Vault repository trait for handling vault-related API operations
#[async_trait]
pub trait VaultRepository {
    /// Sync vault data
    async fn sync_vault(&self, access_token: &str, last_revision: Option<&str>)
        -> AppResult<Value>;

    /// Get all ciphers
    async fn get_ciphers(&self, access_token: &str) -> AppResult<Value>;

    /// Create a new cipher
    async fn create_cipher(&self, cipher_data: &Value, access_token: &str) -> AppResult<Value>;

    /// Update an existing cipher
    async fn update_cipher(
        &self,
        cipher_id: &str,
        cipher_data: &Value,
        access_token: &str,
    ) -> AppResult<Value>;

    /// Delete a cipher
    async fn delete_cipher(&self, cipher_id: &str, access_token: &str) -> AppResult<Value>;

    /// Send cipher to trash (soft delete)
    async fn send_to_trash(&self, cipher_id: &str, access_token: &str) -> AppResult<Value>;

    /// Restore cipher from trash
    async fn restore_from_trash(&self, cipher_id: &str, access_token: &str) -> AppResult<Value>;

    /// Permanently delete cipher
    async fn permanently_delete(&self, cipher_id: &str, access_token: &str) -> AppResult<Value>;

    /// Get collections
    async fn get_collections(&self, access_token: &str) -> AppResult<Value>;
}

/// Folder repository trait for handling folder-related API operations
#[async_trait]
pub trait FolderRepository {
    /// Get all folders
    async fn get_folders(&self, access_token: &str) -> AppResult<Value>;

    /// Create a new folder
    async fn create_folder(&self, folder_data: &Value, access_token: &str) -> AppResult<Value>;

    /// Update an existing folder
    async fn update_folder(
        &self,
        folder_id: &str,
        folder_data: &Value,
        access_token: &str,
    ) -> AppResult<Value>;

    /// Delete a folder
    async fn delete_folder(&self, folder_id: &str, access_token: &str) -> AppResult<Value>;
}
