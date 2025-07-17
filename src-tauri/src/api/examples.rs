use crate::api::{
    client::ApiClient,
    repositories::{ApiAuthRepository, ApiFolderRepository, ApiVaultRepository},
    services::{ApiAuthService, ApiSyncService, ApiVaultService},
};
use crate::services::ServerProviderService;
use std::sync::Arc;
use tauri::AppHandle;

/// Example of how to set up the new API architecture
pub struct ApiSetupExample {
    pub auth_service: Arc<ApiAuthService>,
    pub vault_service: Arc<ApiVaultService>,
    pub sync_service: Arc<ApiSyncService>,
}

impl ApiSetupExample {
    /// Create a new API setup with all services configured
    pub fn new(app_handle: AppHandle, server_provider_service: Arc<ServerProviderService>) -> Self {
        // 1. Create the HTTP client (low-level)
        let api_client = Arc::new(ApiClient::new(app_handle, server_provider_service));

        // 2. Create repositories (data access layer)
        let auth_repository = Arc::new(ApiAuthRepository::new(api_client.clone()));
        let vault_repository = Arc::new(ApiVaultRepository::new(api_client.clone()));
        let folder_repository = Arc::new(ApiFolderRepository::new(api_client));

        // 3. Create services (business logic layer)
        let auth_service = Arc::new(ApiAuthService::new(auth_repository));
        let vault_service = Arc::new(ApiVaultService::new(
            vault_repository.clone(),
            folder_repository.clone(),
        ));
        let sync_service = Arc::new(ApiSyncService::new(vault_repository, folder_repository));

        Self {
            auth_service,
            vault_service,
            sync_service,
        }
    }
}

/// Example usage patterns
#[allow(dead_code)]
pub mod usage_examples {
    use super::*;
    use crate::api::services::{CipherData, FolderData, LoginRequest, SyncRequest};
    use crate::error::AppResult;

    /// Example: User authentication flow
    pub async fn authenticate_user(
        auth_service: &ApiAuthService,
        email: &str,
        password_hash: &str,
    ) -> AppResult<String> {
        // 1. Authenticate user
        let login_request = LoginRequest {
            email: email.to_string(),
            password_hash: password_hash.to_string(),
            two_factor_token: None,
        };

        let login_response = auth_service.authenticate(login_request).await?;

        // 2. Get user profile
        let user_profile = auth_service
            .get_user_profile(&login_response.access_token)
            .await?;

        println!("User {} authenticated successfully", user_profile.email);
        Ok(login_response.access_token)
    }

    /// Example: Vault operations
    pub async fn manage_vault(
        vault_service: &ApiVaultService,
        access_token: &str,
    ) -> AppResult<()> {
        // 1. Get all ciphers
        let ciphers = vault_service.get_ciphers(access_token).await?;
        println!("Found {} ciphers", ciphers.len());

        // 2. Create a new cipher
        let new_cipher = CipherData {
            id: None,
            name: "Example Login".to_string(),
            notes: Some("Created via API".to_string()),
            folder_id: None,
            organization_id: None,
            cipher_type: 1, // Login type
            favorite: false,
            reprompt: 0,
            login: Some(crate::api::services::LoginData {
                username: Some("user@example.com".to_string()),
                password: Some("secure_password".to_string()),
                uri: Some("https://example.com".to_string()),
                totp: None,
            }),
            secure_note: None,
            card: None,
            identity: None,
        };

        let created_cipher = vault_service
            .create_cipher(new_cipher, access_token)
            .await?;
        println!("Created cipher with ID: {:?}", created_cipher.id);

        // 3. Create a folder
        let new_folder = FolderData {
            id: None,
            name: "Work Accounts".to_string(),
        };

        let created_folder = vault_service
            .create_folder(new_folder, access_token)
            .await?;
        println!("Created folder with ID: {:?}", created_folder.id);

        Ok(())
    }

    /// Example: Sync operations
    pub async fn sync_vault(
        sync_service: &ApiSyncService,
        access_token: &str,
        last_revision: Option<&str>,
    ) -> AppResult<()> {
        // 1. Check if sync is needed
        if let Some(revision) = last_revision {
            let sync_needed = sync_service.is_sync_needed(access_token, revision).await?;
            if !sync_needed {
                println!("Vault is already up to date");
                return Ok(());
            }
        }

        // 2. Calculate sync priority
        let priority = sync_service.calculate_sync_priority(last_revision).await?;
        println!("Sync priority: {}/10", priority);

        // 3. Perform sync
        let sync_request = SyncRequest {
            access_token: access_token.to_string(),
            last_revision: last_revision.map(|s| s.to_string()),
            force_full_sync: last_revision.is_none(),
        };

        let sync_result = sync_service.sync(sync_request).await?;

        if sync_result.success {
            println!("Sync completed successfully:");
            println!("  - Ciphers updated: {}", sync_result.ciphers_updated);
            println!("  - Folders updated: {}", sync_result.folders_updated);
            println!(
                "  - Collections updated: {}",
                sync_result.collections_updated
            );
            println!("  - New revision: {}", sync_result.revision_date);
        } else {
            println!("Sync completed with errors:");
            for error in &sync_result.errors {
                println!("  - {}", error);
            }
        }

        Ok(())
    }

    /// Example: Error handling patterns
    pub async fn handle_api_errors(
        auth_service: &ApiAuthService,
        access_token: &str,
    ) -> AppResult<()> {
        match auth_service.validate_token(access_token).await {
            Ok(true) => println!("Token is valid"),
            Ok(false) => {
                println!("Token is invalid, need to re-authenticate");
                // Handle token refresh or re-authentication
            }
            Err(e) => {
                println!("Error validating token: {}", e);
                // Handle network or other errors
            }
        }

        Ok(())
    }
}
