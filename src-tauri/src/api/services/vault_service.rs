use crate::api::repositories::traits::{FolderRepository, VaultRepository};
use crate::crypto::{cache::CRYPTO_CACHE, cipher_crypto::CipherCrypto, UserKey};
use crate::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;
use tracing::{debug, error, info, warn};

#[derive(Debug, Serialize, Deserialize)]
pub struct CipherData {
    pub id: Option<String>,
    pub name: String,
    pub notes: Option<String>,
    #[serde(rename = "folderId")]
    pub folder_id: Option<String>,
    #[serde(rename = "organizationId")]
    pub organization_id: Option<String>,
    #[serde(rename = "type")]
    pub cipher_type: u8,
    pub favorite: bool,
    pub reprompt: u8,
    pub login: Option<LoginData>,
    #[serde(rename = "secureNote")]
    pub secure_note: Option<SecureNoteData>,
    pub card: Option<CardData>,
    pub identity: Option<IdentityData>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginData {
    pub username: Option<String>,
    pub password: Option<String>,
    pub uris: Option<Vec<LoginUriData>>,
    pub totp: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginUriData {
    pub uri: Option<String>,
    #[serde(rename = "match")]
    pub match_type: Option<u8>,
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

/// Raw cipher response from API (encrypted format)
/// This matches the actual API response structure with encrypted strings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawCipherResponse {
    pub id: String,
    #[serde(rename = "organizationId")]
    pub organization_id: Option<String>,
    #[serde(rename = "folderId")]
    pub folder_id: Option<String>,
    pub name: String,          // Encrypted string
    pub notes: Option<String>, // Encrypted string
    #[serde(rename = "type")]
    pub cipher_type: u8,
    pub favorite: bool,
    pub reprompt: u8,
    #[serde(rename = "revisionDate")]
    pub revision_date: String,
    #[serde(rename = "creationDate")]
    pub creation_date: String,
    #[serde(rename = "deletedDate")]
    pub deleted_date: Option<String>,
    pub data: Option<RawCipherData>, // Nested encrypted data
    pub login: Option<RawLoginData>, // Type-specific encrypted data
    #[serde(rename = "secureNote")]
    pub secure_note: Option<RawSecureNoteData>,
    pub card: Option<RawCardData>,
    pub identity: Option<RawIdentityData>,
    pub key: Option<String>, // Item-specific encryption key
    #[serde(rename = "collectionIds")]
    pub collection_ids: Option<Vec<String>>,
    pub edit: Option<bool>,
    #[serde(rename = "viewPassword")]
    pub view_password: Option<bool>,
    #[serde(rename = "organizationUseTotp")]
    pub organization_use_totp: Option<bool>,
    pub attachments: Option<Value>,
    pub fields: Option<Vec<Value>>,
    #[serde(rename = "passwordHistory")]
    pub password_history: Option<Vec<Value>>,
    pub object: Option<String>,
}

/// Raw cipher data object (encrypted format)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawCipherData {
    pub name: Option<String>,     // Encrypted string
    pub notes: Option<String>,    // Encrypted string
    pub username: Option<String>, // Encrypted string
    pub password: Option<String>, // Encrypted string
    pub uri: Option<String>,      // Encrypted string
    pub uris: Option<Vec<RawLoginUriData>>,
    pub totp: Option<String>, // Encrypted string
    #[serde(rename = "autofillOnPageLoad")]
    pub autofill_on_page_load: Option<bool>,
    pub fields: Option<Vec<Value>>,
    #[serde(rename = "passwordHistory")]
    pub password_history: Option<Vec<Value>>,
    #[serde(rename = "passwordRevisionDate")]
    pub password_revision_date: Option<String>,
}

/// Raw login data (encrypted format)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawLoginData {
    pub username: Option<String>, // Encrypted string
    pub password: Option<String>, // Encrypted string
    pub uri: Option<String>,      // Encrypted string
    pub uris: Option<Vec<RawLoginUriData>>,
    pub totp: Option<String>, // Encrypted string
    #[serde(rename = "autofillOnPageLoad")]
    pub autofill_on_page_load: Option<bool>,
    #[serde(rename = "passwordRevisionDate")]
    pub password_revision_date: Option<String>,
}

/// Raw login URI data (encrypted format)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawLoginUriData {
    pub uri: Option<String>, // Encrypted string
    #[serde(rename = "match")]
    pub match_type: Option<u8>,
    #[serde(rename = "uriChecksum")]
    pub uri_checksum: Option<String>, // Encrypted string
}

/// Raw secure note data (encrypted format)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawSecureNoteData {
    #[serde(rename = "type")]
    pub r#type: Option<u8>,
}

/// Raw card data (encrypted format)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawCardData {
    #[serde(rename = "cardholderName")]
    pub cardholder_name: Option<String>, // Encrypted string
    pub number: Option<String>, // Encrypted string
    #[serde(rename = "expMonth")]
    pub exp_month: Option<String>, // Encrypted string
    #[serde(rename = "expYear")]
    pub exp_year: Option<String>, // Encrypted string
    pub code: Option<String>,   // Encrypted string
}

/// Raw identity data (encrypted format)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawIdentityData {
    pub title: Option<String>, // Encrypted string
    #[serde(rename = "firstName")]
    pub first_name: Option<String>, // Encrypted string
    #[serde(rename = "middleName")]
    pub middle_name: Option<String>, // Encrypted string
    #[serde(rename = "lastName")]
    pub last_name: Option<String>, // Encrypted string
    pub address1: Option<String>, // Encrypted string
    pub address2: Option<String>, // Encrypted string
    pub address3: Option<String>, // Encrypted string
    pub city: Option<String>,  // Encrypted string
    pub state: Option<String>, // Encrypted string
    #[serde(rename = "postalCode")]
    pub postal_code: Option<String>, // Encrypted string
    pub country: Option<String>, // Encrypted string
    pub company: Option<String>, // Encrypted string
    pub email: Option<String>, // Encrypted string
    pub phone: Option<String>, // Encrypted string
    pub ssn: Option<String>,   // Encrypted string
    pub username: Option<String>, // Encrypted string
    #[serde(rename = "passportNumber")]
    pub passport_number: Option<String>, // Encrypted string
    #[serde(rename = "licenseNumber")]
    pub license_number: Option<String>, // Encrypted string
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

    /// Get a single cipher by ID (returns raw response for debugging)
    pub async fn get_cipher(&self, cipher_id: &str, access_token: &str) -> AppResult<Value> {
        debug!(cipher_id = cipher_id, "Getting single cipher");
        self.vault_repository
            .get_cipher(cipher_id, access_token)
            .await
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

    /// Get user key for decryption operations
    async fn get_user_key(&self, user_id: &str) -> AppResult<UserKey> {
        CRYPTO_CACHE
            .get_user_key(user_id)
            .map_err(|e| AppError::CacheError {
                operation: "get_user_key".to_string(),
                message: format!("Failed to get user key from cache: {}", e),
            })?
            .ok_or_else(|| AppError::AuthenticationError {
                message: "User key not found in cache. Please unlock vault first.".to_string(),
            })
    }

    /// Decrypt raw cipher response with graceful error handling (following Keyguard's approach)
    async fn decrypt_raw_cipher(
        &self,
        raw_cipher: RawCipherResponse,
        user_id: &str,
    ) -> AppResult<CipherData> {
        debug!(
            cipher_id = %raw_cipher.id,
            cipher_type = raw_cipher.cipher_type,
            "[vault_service] Starting raw cipher decryption"
        );

        let user_key = self.get_user_key(user_id).await?;

        // Decrypt top-level fields with priority handling
        let name = self.decrypt_cipher_name(&raw_cipher, &user_key, &raw_cipher.id)?;
        let notes = self.decrypt_cipher_notes(&raw_cipher, &user_key, &raw_cipher.id)?;

        // Decrypt type-specific data
        let login = if let Some(raw_login) = &raw_cipher.login {
            Some(
                self.decrypt_login_data(raw_login, &raw_cipher.data, &user_key, &raw_cipher.id)
                    .await?,
            )
        } else {
            None
        };

        let secure_note = if let Some(raw_secure_note) = &raw_cipher.secure_note {
            Some(self.decrypt_secure_note_data(raw_secure_note)?)
        } else {
            None
        };

        let card = if let Some(raw_card) = &raw_cipher.card {
            Some(
                self.decrypt_card_data(raw_card, &raw_cipher.data, &user_key)
                    .await?,
            )
        } else {
            None
        };

        let identity = if let Some(raw_identity) = &raw_cipher.identity {
            Some(
                self.decrypt_identity_data(raw_identity, &raw_cipher.data, &user_key)
                    .await?,
            )
        } else {
            None
        };

        Ok(CipherData {
            id: Some(raw_cipher.id),
            name,
            notes,
            folder_id: raw_cipher.folder_id,
            organization_id: raw_cipher.organization_id,
            cipher_type: raw_cipher.cipher_type,
            favorite: raw_cipher.favorite,
            reprompt: if raw_cipher.reprompt > 0 {
                raw_cipher.reprompt
            } else {
                0
            },
            login,
            secure_note,
            card,
            identity,
        })
    }

    /// Decrypt raw cipher with fallback handling (following Keyguard's approach)
    async fn decrypt_raw_cipher_with_fallback(
        &self,
        raw_cipher: RawCipherResponse,
        user_id: &str,
    ) -> CipherData {
        match self.decrypt_raw_cipher(raw_cipher.clone(), user_id).await {
            Ok(decrypted) => {
                debug!(
                    cipher_id = %raw_cipher.id,
                    "[vault_service] Successfully decrypted cipher"
                );
                decrypted
            }
            Err(e) => {
                warn!(
                    cipher_id = %raw_cipher.id,
                    error = %e,
                    "[vault_service] Failed to decrypt cipher. Creating fallback entry (following Keyguard approach)"
                );

                // Create fallback entry similar to Keyguard's "Unsupported Item"
                CipherData {
                    id: Some(raw_cipher.id),
                    name: "Unsupported Item".to_string(),
                    notes: Some(format!("Decryption failed: {}", e)),
                    folder_id: raw_cipher.folder_id,
                    organization_id: raw_cipher.organization_id,
                    cipher_type: raw_cipher.cipher_type,
                    favorite: raw_cipher.favorite,
                    reprompt: if raw_cipher.reprompt > 0 {
                        raw_cipher.reprompt
                    } else {
                        0
                    },
                    login: None,
                    secure_note: None,
                    card: None,
                    identity: None,
                }
            }
        }
    }

    /// Decrypt cipher name with priority handling
    fn decrypt_cipher_name(
        &self,
        raw_cipher: &RawCipherResponse,
        user_key: &UserKey,
        cipher_id: &str,
    ) -> AppResult<String> {
        // Priority: data object > top-level
        let encrypted_name = CipherCrypto::get_encrypted_field(
            Some(&raw_cipher.name),
            raw_cipher.data.as_ref().and_then(|d| d.name.as_deref()),
            None,
        );

        if let Some(encrypted_str) = encrypted_name {
            if !encrypted_str.is_empty() {
                return CipherCrypto::decrypt_string_with_context(
                    encrypted_str,
                    user_key,
                    Some(&format!("cipher:{}/name", cipher_id)),
                );
            }
        }

        // Fallback to "Unnamed Item" if no name found
        Ok("Unnamed Item".to_string())
    }

    /// Decrypt cipher notes with priority handling
    fn decrypt_cipher_notes(
        &self,
        raw_cipher: &RawCipherResponse,
        user_key: &UserKey,
        cipher_id: &str,
    ) -> AppResult<Option<String>> {
        // Priority: data object > top-level
        let encrypted_notes = CipherCrypto::get_encrypted_field(
            raw_cipher.notes.as_deref(),
            raw_cipher.data.as_ref().and_then(|d| d.notes.as_deref()),
            None,
        );

        if let Some(encrypted_str) = encrypted_notes {
            if !encrypted_str.is_empty() {
                return Ok(Some(CipherCrypto::decrypt_string_with_context(
                    encrypted_str,
                    user_key,
                    Some(&format!("cipher:{}/notes", cipher_id)),
                )?));
            }
        }

        Ok(None)
    }

    /// Decrypt login data with priority handling
    async fn decrypt_login_data(
        &self,
        raw_login: &RawLoginData,
        raw_data: &Option<RawCipherData>,
        user_key: &UserKey,
        cipher_id: &str,
    ) -> AppResult<LoginData> {
        // Decrypt username with priority: login > data
        let username = if let Some(encrypted_username) = CipherCrypto::get_encrypted_field(
            None,
            raw_data.as_ref().and_then(|d| d.username.as_deref()),
            raw_login.username.as_deref(),
        ) {
            if !encrypted_username.is_empty() {
                Some(CipherCrypto::decrypt_string_with_context(
                    encrypted_username,
                    user_key,
                    Some(&format!("cipher:{}/login/username", cipher_id)),
                )?)
            } else {
                None
            }
        } else {
            None
        };

        // Decrypt password with priority: login > data
        let password = if let Some(encrypted_password) = CipherCrypto::get_encrypted_field(
            None,
            raw_data.as_ref().and_then(|d| d.password.as_deref()),
            raw_login.password.as_deref(),
        ) {
            if !encrypted_password.is_empty() {
                Some(CipherCrypto::decrypt_string_with_context(
                    encrypted_password,
                    user_key,
                    Some(&format!("cipher:{}/login/password", cipher_id)),
                )?)
            } else {
                None
            }
        } else {
            None
        };

        // Decrypt TOTP with priority: login > data
        let totp = if let Some(encrypted_totp) = CipherCrypto::get_encrypted_field(
            None,
            raw_data.as_ref().and_then(|d| d.totp.as_deref()),
            raw_login.totp.as_deref(),
        ) {
            if !encrypted_totp.is_empty() {
                Some(CipherCrypto::decrypt_string(encrypted_totp, user_key)?)
            } else {
                None
            }
        } else {
            None
        };

        // Decrypt URIs
        let uris = if let Some(raw_uris) = &raw_login.uris {
            let mut decrypted_uris = Vec::new();
            for raw_uri in raw_uris {
                if let Some(encrypted_uri) = &raw_uri.uri {
                    if !encrypted_uri.is_empty() {
                        let decrypted_uri = CipherCrypto::decrypt_string(encrypted_uri, user_key)?;
                        decrypted_uris.push(LoginUriData {
                            uri: Some(decrypted_uri),
                            match_type: raw_uri.match_type,
                        });
                    }
                }
            }
            if !decrypted_uris.is_empty() {
                Some(decrypted_uris)
            } else {
                None
            }
        } else {
            None
        };

        Ok(LoginData {
            username,
            password,
            uris,
            totp,
        })
    }

    /// Decrypt secure note data
    fn decrypt_secure_note_data(
        &self,
        raw_secure_note: &RawSecureNoteData,
    ) -> AppResult<SecureNoteData> {
        Ok(SecureNoteData {
            r#type: raw_secure_note.r#type.unwrap_or(0),
        })
    }

    /// Decrypt card data with priority handling
    async fn decrypt_card_data(
        &self,
        raw_card: &RawCardData,
        _raw_data: &Option<RawCipherData>,
        user_key: &UserKey,
    ) -> AppResult<CardData> {
        let cardholder_name =
            CipherCrypto::decrypt_optional_string(&raw_card.cardholder_name, user_key)?;
        let number = CipherCrypto::decrypt_optional_string(&raw_card.number, user_key)?;
        let exp_month = CipherCrypto::decrypt_optional_string(&raw_card.exp_month, user_key)?;
        let exp_year = CipherCrypto::decrypt_optional_string(&raw_card.exp_year, user_key)?;
        let code = CipherCrypto::decrypt_optional_string(&raw_card.code, user_key)?;

        Ok(CardData {
            cardholder_name,
            number,
            exp_month,
            exp_year,
            code,
        })
    }

    /// Decrypt identity data with priority handling
    async fn decrypt_identity_data(
        &self,
        raw_identity: &RawIdentityData,
        _raw_data: &Option<RawCipherData>,
        user_key: &UserKey,
    ) -> AppResult<IdentityData> {
        Ok(IdentityData {
            title: CipherCrypto::decrypt_optional_string(&raw_identity.title, user_key)?,
            first_name: CipherCrypto::decrypt_optional_string(&raw_identity.first_name, user_key)?,
            middle_name: CipherCrypto::decrypt_optional_string(
                &raw_identity.middle_name,
                user_key,
            )?,
            last_name: CipherCrypto::decrypt_optional_string(&raw_identity.last_name, user_key)?,
            address1: CipherCrypto::decrypt_optional_string(&raw_identity.address1, user_key)?,
            address2: CipherCrypto::decrypt_optional_string(&raw_identity.address2, user_key)?,
            address3: CipherCrypto::decrypt_optional_string(&raw_identity.address3, user_key)?,
            city: CipherCrypto::decrypt_optional_string(&raw_identity.city, user_key)?,
            state: CipherCrypto::decrypt_optional_string(&raw_identity.state, user_key)?,
            postal_code: CipherCrypto::decrypt_optional_string(
                &raw_identity.postal_code,
                user_key,
            )?,
            country: CipherCrypto::decrypt_optional_string(&raw_identity.country, user_key)?,
            company: CipherCrypto::decrypt_optional_string(&raw_identity.company, user_key)?,
            email: CipherCrypto::decrypt_optional_string(&raw_identity.email, user_key)?,
            phone: CipherCrypto::decrypt_optional_string(&raw_identity.phone, user_key)?,
            ssn: CipherCrypto::decrypt_optional_string(&raw_identity.ssn, user_key)?,
            username: CipherCrypto::decrypt_optional_string(&raw_identity.username, user_key)?,
            passport_number: CipherCrypto::decrypt_optional_string(
                &raw_identity.passport_number,
                user_key,
            )?,
            license_number: CipherCrypto::decrypt_optional_string(
                &raw_identity.license_number,
                user_key,
            )?,
        })
    }

    /// Parse sync response from API
    async fn parse_sync_response(&self, response: Value) -> AppResult<SyncData> {
        let ciphers = response
            .get("ciphers")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        let folders = response
            .get("folders")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        let collections = response
            .get("collections")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        let profile = response.get("profile").cloned().unwrap_or(Value::Null);

        let revision_date = response
            .get("revisionDate")
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

    /// Parse ciphers response from API using new two-step pipeline
    async fn parse_ciphers_response(&self, _response: Value) -> AppResult<Vec<CipherData>> {
        debug!("[vault_service] Parsing ciphers response using new two-step pipeline");

        // For now, return error asking for user_id to be passed
        // TODO: Update the API to pass user_id for proper decryption
        Err(AppError::ValidationError {
            field: "user_id".to_string(),
            message: "User ID must be provided for cipher decryption. Please update the API to pass user_id.".to_string(),
        })
    }

    /// Parse ciphers response from API with user context using new two-step pipeline
    async fn parse_ciphers_response_with_user(
        &self,
        response: Value,
        user_id: &str,
    ) -> AppResult<Vec<CipherData>> {
        debug!(
            user_id = user_id,
            "[vault_service] Parsing ciphers response with user context using new two-step pipeline"
        );

        // Try different possible response formats
        let ciphers_array = if let Some(data_array) =
            response.get("data").and_then(|v| v.as_array())
        {
            // Standard Vaultwarden format: { "data": [...], "object": "list" }
            data_array
        } else if let Some(data_array) = response.get("Data").and_then(|v| v.as_array()) {
            // Alternative format with uppercase "Data"
            data_array
        } else if response.is_array() {
            // Direct array response
            response.as_array().unwrap()
        } else {
            return Err(AppError::ValidationError {
                field: "response".to_string(),
                message: format!(
                    "Invalid ciphers response format. Expected object with 'data' field or direct array. Got: {}",
                    serde_json::to_string(&response).unwrap_or_else(|_| "unparseable".to_string())
                ),
            });
        };

        debug!(
            cipher_count = ciphers_array.len(),
            user_id = user_id,
            "[vault_service] Found {} ciphers in response, starting two-step parsing",
            ciphers_array.len()
        );

        let mut ciphers = Vec::new();
        let mut successful_count = 0;
        let mut failed_count = 0;

        for (index, cipher_value) in ciphers_array.iter().enumerate() {
            // Step 1: Parse raw encrypted response
            match serde_json::from_value::<RawCipherResponse>(cipher_value.clone()) {
                Ok(raw_cipher) => {
                    debug!(
                        cipher_id = %raw_cipher.id,
                        cipher_index = index,
                        cipher_type = raw_cipher.cipher_type,
                        "[vault_service] Successfully parsed raw cipher, starting decryption"
                    );

                    // Step 2: Decrypt using fallback approach (following Keyguard)
                    let decrypted_cipher = self
                        .decrypt_raw_cipher_with_fallback(raw_cipher, user_id)
                        .await;
                    ciphers.push(decrypted_cipher);
                    successful_count += 1;
                }
                Err(e) => {
                    failed_count += 1;
                    warn!(
                        cipher_index = index,
                        error = %e,
                        user_id = user_id,
                        "[vault_service] Failed to parse raw cipher response, skipping"
                    );
                    debug!(
                        cipher_data = %serde_json::to_string_pretty(cipher_value).unwrap_or_else(|_| "unparseable".to_string()),
                        "[vault_service] Raw cipher data that failed to parse"
                    );
                    continue;
                }
            }
        }

        info!(
            user_id = user_id,
            successful_count = successful_count,
            failed_count = failed_count,
            total_count = ciphers_array.len(),
            "[vault_service] Completed cipher parsing: {} successful, {} failed out of {} total",
            successful_count,
            failed_count,
            ciphers_array.len()
        );

        Ok(ciphers)
    }

    /// Parse single cipher response from API using two-step pipeline
    async fn parse_cipher_response(&self, response: Value) -> AppResult<CipherData> {
        debug!("[vault_service] Parsing single cipher response using new two-step pipeline");

        // Step 1: Parse raw encrypted response
        let raw_cipher: RawCipherResponse = serde_json::from_value(response.clone())
            .map_err(|e| {
                error!(
                    error = %e,
                    response_preview = %serde_json::to_string(&response).unwrap_or_else(|_| "unparseable".to_string())[..std::cmp::min(200, serde_json::to_string(&response).unwrap_or_else(|_| "unparseable".to_string()).len())],
                    "[vault_service] Failed to parse raw cipher response"
                );
                AppError::ValidationError {
                    field: "cipher_response".to_string(),
                    message: format!("Failed to parse raw cipher response: {}", e),
                }
            })?;

        debug!(
            cipher_id = %raw_cipher.id,
            cipher_type = raw_cipher.cipher_type,
            has_login = raw_cipher.login.is_some(),
            has_data = raw_cipher.data.is_some(),
            "[vault_service] Successfully parsed raw cipher response"
        );

        // Step 2: Extract user_id from context (this should be passed in, but for now we'll try to infer)
        // TODO: Modify the API to pass user_id explicitly
        let _user_id = ""; // This will need to be passed from the calling context

        // For now, return error asking for user_id to be passed
        Err(AppError::ValidationError {
            field: "user_id".to_string(),
            message: "User ID must be provided for cipher decryption. Please update the API to pass user_id.".to_string(),
        })
    }

    /// Parse single cipher response from API with user context
    async fn parse_cipher_response_with_user(
        &self,
        response: Value,
        user_id: &str,
    ) -> AppResult<CipherData> {
        debug!(
            user_id = user_id,
            "[vault_service] Parsing single cipher response with user context using new two-step pipeline"
        );

        // Step 1: Parse raw encrypted response
        let raw_cipher: RawCipherResponse = serde_json::from_value(response.clone())
            .map_err(|e| {
                error!(
                    error = %e,
                    user_id = user_id,
                    response_preview = %serde_json::to_string(&response).unwrap_or_else(|_| "unparseable".to_string())[..std::cmp::min(200, serde_json::to_string(&response).unwrap_or_else(|_| "unparseable".to_string()).len())],
                    "[vault_service] Failed to parse raw cipher response"
                );
                AppError::ValidationError {
                    field: "cipher_response".to_string(),
                    message: format!("Failed to parse raw cipher response: {}", e),
                }
            })?;

        debug!(
            cipher_id = %raw_cipher.id,
            cipher_type = raw_cipher.cipher_type,
            user_id = user_id,
            has_login = raw_cipher.login.is_some(),
            has_data = raw_cipher.data.is_some(),
            "[vault_service] Successfully parsed raw cipher response, starting decryption"
        );

        // Step 2: Decrypt using fallback approach (following Keyguard)
        Ok(self
            .decrypt_raw_cipher_with_fallback(raw_cipher, user_id)
            .await)
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
