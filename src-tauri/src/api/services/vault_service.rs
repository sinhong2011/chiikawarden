use crate::api::repositories::traits::{FolderRepository, VaultRepository};
use crate::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;
use tracing::{debug, error, info};

#[derive(Debug, Serialize, Deserialize)]
pub struct CipherData {
    pub id: Option<String>,
    pub name: String,
    pub notes: Option<String>,
    pub folder_id: Option<String>,
    pub organization_id: Option<String>,
    pub cipher_type: u8,
    pub favorite: bool,
    pub reprompt: u8,
    pub login: Option<LoginData>,
    pub secure_note: Option<SecureNoteData>,
    pub card: Option<CardData>,
    pub identity: Option<IdentityData>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginData {
    pub username: Option<String>,
    pub password: Option<String>,
    pub uri: Option<String>,
    pub totp: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SecureNoteData {
    pub r#type: u8,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CardData {
    pub cardholder_name: Option<String>,
    pub number: Option<String>,
    pub exp_month: Option<String>,
    pub exp_year: Option<String>,
    pub code: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IdentityData {
    pub title: Option<String>,
    pub first_name: Option<String>,
    pub middle_name: Option<String>,
    pub last_name: Option<String>,
    pub address1: Option<String>,
    pub address2: Option<String>,
    pub address3: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub postal_code: Option<String>,
    pub country: Option<String>,
    pub company: Option<String>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub ssn: Option<String>,
    pub username: Option<String>,
    pub passport_number: Option<String>,
    pub license_number: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FolderData {
    pub id: Option<String>,
    pub name: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncData {
    pub ciphers: Vec<Value>,
    pub folders: Vec<Value>,
    pub collections: Vec<Value>,
    pub profile: Value,
    pub revision_date: String,
}

/// API vault service for handling complex vault business logic
pub struct ApiVaultService {
    vault_repository: Arc<dyn VaultRepository + Send + Sync>,
    folder_repository: Arc<dyn FolderRepository + Send + Sync>,
}

impl ApiVaultService {
    pub fn new(
        vault_repository: Arc<dyn VaultRepository + Send + Sync>,
        folder_repository: Arc<dyn FolderRepository + Send + Sync>,
    ) -> Self {
        Self {
            vault_repository,
            folder_repository,
        }
    }

    /// Perform full vault sync
    pub async fn sync_vault(
        &self,
        access_token: &str,
        last_revision: Option<&str>,
    ) -> AppResult<SyncData> {
        debug!(
            has_last_revision = last_revision.is_some(),
            last_revision = last_revision.unwrap_or("none"),
            "Starting vault sync"
        );

        let response = self
            .vault_repository
            .sync_vault(access_token, last_revision)
            .await
            .map_err(|e| {
                error!(error = %e, "Vault sync request failed");
                e
            })?;

        debug!("Vault sync response received, parsing");
        let result = self.parse_sync_response(response).await;

        match &result {
            Ok(sync_data) => {
                info!(
                    ciphers_count = sync_data.ciphers.len(),
                    folders_count = sync_data.folders.len(),
                    collections_count = sync_data.collections.len(),
                    revision_date = sync_data.revision_date,
                    "Vault sync successful"
                );
            }
            Err(e) => {
                error!(error = %e, "Vault sync parsing failed");
            }
        }

        result
    }

    /// Get all ciphers
    pub async fn get_ciphers(&self, access_token: &str) -> AppResult<Vec<CipherData>> {
        debug!("Starting get ciphers request");

        let response = self
            .vault_repository
            .get_ciphers(access_token)
            .await
            .map_err(|e| {
                error!(error = %e, "Get ciphers request failed");
                e
            })?;

        debug!("Get ciphers response received, parsing");
        let result = self.parse_ciphers_response(response).await;

        match &result {
            Ok(ciphers) => {
                info!(ciphers_count = ciphers.len(), "Get ciphers successful");
            }
            Err(e) => {
                error!(error = %e, "Get ciphers parsing failed");
            }
        }

        result
    }

    /// Create a new cipher
    pub async fn create_cipher(
        &self,
        cipher: CipherData,
        access_token: &str,
    ) -> AppResult<CipherData> {
        let cipher_json = self.cipher_to_json(&cipher)?;
        let response = self
            .vault_repository
            .create_cipher(&cipher_json, access_token)
            .await?;

        self.parse_cipher_response(response).await
    }

    /// Update an existing cipher
    pub async fn update_cipher(
        &self,
        cipher: CipherData,
        access_token: &str,
    ) -> AppResult<CipherData> {
        let cipher_id = cipher
            .id
            .as_ref()
            .ok_or_else(|| AppError::ValidationError {
                field: "cipher.id".to_string(),
                message: "Cipher ID is required for update".to_string(),
            })?;

        let cipher_json = self.cipher_to_json(&cipher)?;
        let response = self
            .vault_repository
            .update_cipher(cipher_id, &cipher_json, access_token)
            .await?;

        self.parse_cipher_response(response).await
    }

    /// Delete a cipher
    pub async fn delete_cipher(&self, cipher_id: &str, access_token: &str) -> AppResult<()> {
        let _response = self
            .vault_repository
            .delete_cipher(cipher_id, access_token)
            .await?;
        Ok(())
    }

    /// Move cipher to trash
    pub async fn move_to_trash(&self, cipher_id: &str, access_token: &str) -> AppResult<()> {
        let _response = self
            .vault_repository
            .send_to_trash(cipher_id, access_token)
            .await?;
        Ok(())
    }

    /// Restore cipher from trash
    pub async fn restore_from_trash(&self, cipher_id: &str, access_token: &str) -> AppResult<()> {
        let _response = self
            .vault_repository
            .restore_from_trash(cipher_id, access_token)
            .await?;
        Ok(())
    }

    /// Get all folders
    pub async fn get_folders(&self, access_token: &str) -> AppResult<Vec<FolderData>> {
        let response = self.folder_repository.get_folders(access_token).await?;
        self.parse_folders_response(response).await
    }

    /// Create a new folder
    pub async fn create_folder(
        &self,
        folder: FolderData,
        access_token: &str,
    ) -> AppResult<FolderData> {
        let folder_json = self.folder_to_json(&folder)?;
        let response = self
            .folder_repository
            .create_folder(&folder_json, access_token)
            .await?;

        self.parse_folder_response(response).await
    }

    /// Update an existing folder
    pub async fn update_folder(
        &self,
        folder: FolderData,
        access_token: &str,
    ) -> AppResult<FolderData> {
        let folder_id = folder
            .id
            .as_ref()
            .ok_or_else(|| AppError::ValidationError {
                field: "folder.id".to_string(),
                message: "Folder ID is required for update".to_string(),
            })?;

        let folder_json = self.folder_to_json(&folder)?;
        let response = self
            .folder_repository
            .update_folder(folder_id, &folder_json, access_token)
            .await?;

        self.parse_folder_response(response).await
    }

    /// Delete a folder
    pub async fn delete_folder(&self, folder_id: &str, access_token: &str) -> AppResult<()> {
        let _response = self
            .folder_repository
            .delete_folder(folder_id, access_token)
            .await?;
        Ok(())
    }

    /// Convert CipherData to JSON
    fn cipher_to_json(&self, cipher: &CipherData) -> AppResult<Value> {
        serde_json::to_value(cipher).map_err(|e| AppError::ValidationError {
            field: "cipher_serialization".to_string(),
            message: format!("Failed to serialize cipher: {}", e),
        })
    }

    /// Convert FolderData to JSON
    fn folder_to_json(&self, folder: &FolderData) -> AppResult<Value> {
        serde_json::to_value(folder).map_err(|e| AppError::ValidationError {
            field: "folder_serialization".to_string(),
            message: format!("Failed to serialize folder: {}", e),
        })
    }

    /// Parse sync response from API
    async fn parse_sync_response(&self, response: Value) -> AppResult<SyncData> {
        let ciphers = response
            .get("Ciphers")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        let folders = response
            .get("Folders")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        let collections = response
            .get("Collections")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        let profile = response.get("Profile").cloned().unwrap_or(Value::Null);

        let revision_date = response
            .get("RevisionDate")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        Ok(SyncData {
            ciphers,
            folders,
            collections,
            profile,
            revision_date,
        })
    }

    /// Parse ciphers response from API
    async fn parse_ciphers_response(&self, response: Value) -> AppResult<Vec<CipherData>> {
        let ciphers_array = response
            .get("Data")
            .and_then(|v| v.as_array())
            .ok_or_else(|| AppError::ValidationError {
                field: "response.Data".to_string(),
                message: "Invalid ciphers response format".to_string(),
            })?;

        let mut ciphers = Vec::new();
        for cipher_value in ciphers_array {
            match serde_json::from_value(cipher_value.clone()) {
                Ok(cipher) => ciphers.push(cipher),
                Err(e) => {
                    eprintln!("Failed to parse cipher: {}", e);
                    continue;
                }
            }
        }

        Ok(ciphers)
    }

    /// Parse single cipher response from API
    async fn parse_cipher_response(&self, response: Value) -> AppResult<CipherData> {
        serde_json::from_value(response).map_err(|e| AppError::ValidationError {
            field: "cipher_response".to_string(),
            message: format!("Failed to parse cipher response: {}", e),
        })
    }

    /// Parse folders response from API
    async fn parse_folders_response(&self, response: Value) -> AppResult<Vec<FolderData>> {
        let folders_array = response
            .get("Data")
            .and_then(|v| v.as_array())
            .ok_or_else(|| AppError::ValidationError {
                field: "response.Data".to_string(),
                message: "Invalid folders response format".to_string(),
            })?;

        let mut folders = Vec::new();
        for folder_value in folders_array {
            match serde_json::from_value(folder_value.clone()) {
                Ok(folder) => folders.push(folder),
                Err(e) => {
                    eprintln!("Failed to parse folder: {}", e);
                    continue;
                }
            }
        }

        Ok(folders)
    }

    /// Parse single folder response from API
    async fn parse_folder_response(&self, response: Value) -> AppResult<FolderData> {
        serde_json::from_value(response).map_err(|e| AppError::ValidationError {
            field: "folder_response".to_string(),
            message: format!("Failed to parse folder response: {}", e),
        })
    }
}
