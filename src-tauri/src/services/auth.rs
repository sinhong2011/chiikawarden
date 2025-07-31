use crate::api::ApiClient;
use crate::crypto::{CryptoService, MasterKey, UserKey};
use crate::error::{AppError, AppResult};
use crate::models::user::User;
use crate::services::ServerProviderService;
use crate::storage::AppDatabase;
use crate::storage::SecureKeyStore;
use base64::prelude::*;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// Bitwarden registration request structure
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct RegisterRequest {
    email: String,
    master_password_hash: String,
    key: String,
    kdf: Option<i32>,
    kdf_iterations: Option<i32>,
    kdf_memory: Option<i32>,
    kdf_parallelism: Option<i32>,
    name: Option<String>,
    master_password_hint: Option<String>,
}

/// Bitwarden registration response structure
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RegisterResponse {
    object: String,
    captcha_bypass_token: String,
}

/// Authentication service for handling login/logout operations
pub struct AuthService {
    secure_storage: Arc<SecureKeyStore>,
    crypto_service: Arc<CryptoService>,
    database: Arc<AppDatabase>,
    api_client: Arc<ApiClient>,
    server_provider_service: Arc<ServerProviderService>,
}

impl AuthService {
    pub fn new(
        secure_storage: Arc<SecureKeyStore>,
        crypto_service: Arc<CryptoService>,
        database: Arc<AppDatabase>,
        api_client: Arc<ApiClient>,
        server_provider_service: Arc<ServerProviderService>,
    ) -> Self {
        Self {
            secure_storage,
            crypto_service,
            database,
            api_client,
            server_provider_service,
        }
    }

    /// Store master key securely
    pub async fn store_master_key(&self, user_id: &str, master_key: &MasterKey) -> AppResult<()> {
        use tracing::{debug, error, info};

        debug!(
            user_id = user_id,
            operation = "store_master_key",
            "Starting master key storage operation"
        );

        let start_time = std::time::Instant::now();

        let result = self
            .secure_storage
            .store_master_key(user_id, master_key.as_bytes())
            .await
            .map_err(|e| {
                let elapsed = start_time.elapsed();
                error!(
                    user_id = user_id,
                    operation = "store_master_key",
                    elapsed_ms = elapsed.as_millis(),
                    error = %e,
                    error_type = "secure_storage_failure",
                    "Master key storage failed - secure storage operation failed"
                );
                AppError::StorageError {
                    message: format!("Failed to store master key for user {}: {}", user_id, e),
                }
            });

        match &result {
            Ok(_) => {
                let elapsed = start_time.elapsed();
                info!(
                    user_id = user_id,
                    operation = "store_master_key",
                    elapsed_ms = elapsed.as_millis(),
                    "Master key stored successfully"
                );
            }
            Err(e) => {
                let elapsed = start_time.elapsed();
                error!(
                    user_id = user_id,
                    operation = "store_master_key",
                    elapsed_ms = elapsed.as_millis(),
                    error = %e,
                    "Master key storage operation failed"
                );
            }
        }

        result
    }

    /// Retrieve master key
    pub async fn get_master_key(&self, user_id: &str) -> AppResult<Option<MasterKey>> {
        match self.secure_storage.get_master_key(user_id).await {
            Ok(key_bytes) => Ok(Some(MasterKey::new(key_bytes))),
            Err(_) => Ok(None),
        }
    }

    /// Delete stored master key
    pub async fn delete_master_key(&self, user_id: &str) -> AppResult<()> {
        self.secure_storage
            .delete_user_data(user_id)
            .await
            .map_err(|_| AppError::CryptographyError {
                operation: "delete_master_key".to_string(),
            })
    }

    /// Derive master key from password
    pub async fn derive_master_key(
        &self,
        password: &str,
        email: &str,
        iterations: u32,
    ) -> AppResult<MasterKey> {
        self.crypto_service
            .derive_master_key(password, email, iterations)
            .map_err(|_| AppError::CryptographyError {
                operation: "derive_master_key".to_string(),
            })
    }

    /// Hash master key for authentication
    pub async fn hash_master_key(
        &self,
        master_key: &MasterKey,
        password: &str,
    ) -> AppResult<String> {
        self.crypto_service
            .hash_master_key(master_key, password)
            .map_err(|_| AppError::CryptographyError {
                operation: "hash_master_key".to_string(),
            })
    }

    /// Generate and encrypt user key
    pub async fn generate_user_key(&self, master_key: &MasterKey) -> AppResult<(UserKey, String)> {
        let user_key =
            self.crypto_service
                .generate_user_key()
                .map_err(|_| AppError::CryptographyError {
                    operation: "generate_user_key".to_string(),
                })?;

        let encrypted_user_key = self
            .crypto_service
            .encrypt_user_key(&user_key, master_key)
            .map_err(|_| AppError::CryptographyError {
                operation: "encrypt_user_key".to_string(),
            })?;

        // Convert encrypted data to Bitwarden encrypted string format
        use crate::crypto::{cipher_crypto::EncryptedString, EncryptionType};
        let encrypted_string = EncryptedString::from_encrypted_data(
            &encrypted_user_key,
            EncryptionType::AesCbc256HmacSha256B64,
        );

        Ok((user_key, encrypted_string))
    }

    /// Store encrypted user key
    pub async fn store_encrypted_user_key(
        &self,
        user_id: &str,
        encrypted_user_key: &[u8],
    ) -> AppResult<()> {
        self.secure_storage
            .store_device_key(user_id, encrypted_user_key)
            .await
            .map_err(|_| AppError::CryptographyError {
                operation: "store_encrypted_user_key".to_string(),
            })
    }

    /// Get user by email for authentication
    pub async fn get_user_by_email(&self, email: &str) -> AppResult<Option<User>> {
        use tracing::{debug, error};

        debug!(
            email = email,
            operation = "get_user_by_email",
            "Looking up user by email for authentication"
        );

        match self.database.get_user_by_email(email).await {
            Ok(user) => {
                debug!(
                    email = email,
                    user_id = user.id,
                    "User found for authentication"
                );
                Ok(Some(user))
            }
            Err(AppError::DatabaseError { message }) if message.contains("not found") => {
                debug!(email = email, "User not found for authentication");
                Ok(None)
            }
            Err(e) => {
                error!(
                    email = email,
                    error = %e,
                    "Database error during user lookup"
                );
                Err(e)
            }
        }
    }

    /// Get user by ID for re-authentication
    pub async fn get_user_by_id(&self, user_id: &str) -> AppResult<Option<User>> {
        use tracing::{debug, error};

        debug!(
            user_id = user_id,
            operation = "get_user_by_id",
            "Looking up user by ID for re-authentication"
        );

        match self.database.get_user_by_id(user_id).await {
            Ok(user) => {
                debug!(
                    user_id = user_id,
                    email = user.email,
                    "User found for re-authentication"
                );
                Ok(Some(user))
            }
            Err(AppError::DatabaseError { message }) if message.contains("not found") => {
                debug!(user_id = user_id, "User not found for re-authentication");
                Ok(None)
            }
            Err(e) => {
                error!(
                    user_id = user_id,
                    error = %e,
                    "Database error during user lookup by ID"
                );
                Err(e)
            }
        }
    }

    /// Authenticate user with email and password
    pub async fn authenticate_user(&self, email: &str, password: &str) -> AppResult<Option<User>> {
        use tracing::{debug, error, info, warn};

        info!(
            email = email,
            operation = "authenticate_user",
            "Starting user authentication"
        );

        let start_time = std::time::Instant::now();

        // Get user by email
        let user = match self.get_user_by_email(email).await? {
            Some(user) => user,
            None => {
                let elapsed = start_time.elapsed();
                warn!(
                    email = email,
                    elapsed_ms = elapsed.as_millis(),
                    "Authentication failed: user not found"
                );
                return Ok(None);
            }
        };

        // Check if user has a master key hash (required for authentication)
        let stored_hash = match &user.master_key_hash {
            Some(hash) => hash,
            None => {
                let elapsed = start_time.elapsed();
                error!(
                    email = email,
                    user_id = user.id,
                    elapsed_ms = elapsed.as_millis(),
                    "Authentication failed: user has no master key hash stored"
                );
                return Err(AppError::AuthenticationError {
                    message: "User account is not properly configured for authentication"
                        .to_string(),
                });
            }
        };

        debug!(
            email = email,
            user_id = user.id,
            "Deriving master key for authentication"
        );

        // Derive master key from provided password
        let derived_master_key = self
            .derive_master_key(password, email, user.kdf_iterations as u32)
            .await?;

        debug!(
            email = email,
            user_id = user.id,
            "Generating hash for password verification"
        );

        // Generate hash from derived master key
        let derived_hash = self.hash_master_key(&derived_master_key, password).await?;

        // Compare hashes
        let is_valid = derived_hash == *stored_hash;

        let elapsed = start_time.elapsed();

        if is_valid {
            info!(
                email = email,
                user_id = user.id,
                elapsed_ms = elapsed.as_millis(),
                "Authentication successful"
            );
            Ok(Some(user))
        } else {
            warn!(
                email = email,
                user_id = user.id,
                elapsed_ms = elapsed.as_millis(),
                "Authentication failed: invalid password"
            );
            Ok(None)
        }
    }

    /// Create a new user account via remote Bitwarden API
    pub async fn create_user(
        &self,
        email: &str,
        password: &str,
        kdf_iterations: u32,
    ) -> AppResult<User> {
        use tracing::{debug, error, info};
        use uuid::Uuid;

        info!(
            email = email,
            operation = "create_user",
            "Creating new user account via Bitwarden API"
        );

        // Step 1: Generate cryptographic keys locally
        debug!(
            email = email,
            "Generating cryptographic keys for registration"
        );

        // Derive master key
        let master_key = self
            .derive_master_key(password, email, kdf_iterations)
            .await?;

        // Generate master key hash
        let master_key_hash = self.hash_master_key(&master_key, password).await?;

        // Generate and encrypt user key
        let (_user_key, encrypted_user_key) = self.generate_user_key(&master_key).await?;

        // Step 2: Register user with Bitwarden API
        debug!(email = email, "Registering user with remote Bitwarden API");

        let register_request = RegisterRequest {
            email: email.to_string(),
            master_password_hash: master_key_hash.clone(),
            key: encrypted_user_key.clone(), // Already in Bitwarden encrypted string format
            kdf: Some(0),                    // PBKDF2
            kdf_iterations: Some(kdf_iterations as i32),
            kdf_memory: None,
            kdf_parallelism: None,
            name: None,
            master_password_hint: None,
        };

        let _register_response: RegisterResponse = self
            .api_client
            .post("/accounts/register", &register_request, None)
            .await
            .map_err(|e| {
                error!(
                    email = email,
                    operation = "bitwarden_register",
                    error = %e,
                    "Failed to register user with Bitwarden API"
                );
                AppError::NetworkError {
                    status: 0,
                    message: format!("Failed to register user with Bitwarden: {}", e),
                }
            })?;

        info!(
            email = email,
            "User successfully registered with Bitwarden API"
        );

        // Step 3: Create local user record ONLY after successful remote registration
        let user_id = format!("user_{}", Uuid::new_v4());

        debug!(
            email = email,
            user_id = user_id,
            "Creating local user record after successful remote registration"
        );

        // Get current server provider ID
        let current_provider = self
            .server_provider_service
            .get_current_provider()
            .await
            .ok_or_else(|| AppError::ValidationError {
                field: "server_provider".to_string(),
                message: "No current server provider set".to_string(),
            })?;
        let server_provider_id = current_provider.id;

        let user = User {
            id: user_id.clone(),
            email: email.to_string(),
            master_key_hash: Some(master_key_hash),
            encrypted_private_key_new: None,
            encrypted_user_key_new: Some(
                base64::prelude::BASE64_STANDARD.encode(&encrypted_user_key),
            ),
            key_derivation_method: "server_provided".to_string(),
            device_trust_enabled: false,
            webauthn_enabled: false,
            server_provider_id,
            kdf_type: 0, // PBKDF2
            kdf_iterations: kdf_iterations as i32,
            kdf_memory: None,
            kdf_parallelism: None,
            created_date: chrono::Utc::now(),
            revision_date: chrono::Utc::now(),
        };

        // Store user in local database
        self.database.create_user(&user).await?;

        // Store master key securely
        self.store_master_key(&user_id, &master_key).await?;

        // Store encrypted user key (convert from string to bytes)
        let encrypted_user_key_bytes = encrypted_user_key.as_bytes();
        self.store_encrypted_user_key(&user_id, encrypted_user_key_bytes)
            .await?;

        info!(
            email = email,
            user_id = user_id,
            "User account created successfully with remote Bitwarden integration"
        );

        Ok(user)
    }
}
