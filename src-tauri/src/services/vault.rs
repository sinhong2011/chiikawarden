use crate::crypto::{cache::CRYPTO_CACHE, CipherCrypto, CryptoResult, CryptoService, UserKey};
use crate::error::{AppError, AppResult};
use crate::logging::log_vault_operation;
use crate::models::{
    CardView, Cipher, CipherView, Collection, Folder, IdentityView, LoginUriView, LoginView,
    SecureNoteView,
};
use crate::storage::{AppDatabase, MemoryCache};
use serde_json::Value;
use std::sync::Arc;
use tracing::{debug, error, info, warn};

/// Vault service for managing ciphers, folders, and collections
pub struct VaultService {
    database: Arc<AppDatabase>,
    cache: Arc<MemoryCache>,
    crypto: Arc<CryptoService>,
}

impl VaultService {
    pub fn new(
        database: Arc<AppDatabase>,
        cache: Arc<MemoryCache>,
        crypto: Arc<CryptoService>,
    ) -> Self {
        Self {
            database,
            cache,
            crypto,
        }
    }

    /// Clear user key from cache when MAC verification fails
    /// This forces the user to re-authenticate with valid credentials
    async fn clear_invalid_user_key(&self, user_id: &str) -> CryptoResult<()> {
        use crate::crypto::cache::CRYPTO_CACHE;

        debug!(
            "[vault] Clearing invalid user key from cache for user: {}",
            user_id
        );

        // Clear the invalid user key from cache
        if let Err(e) = CRYPTO_CACHE.remove_user_key(user_id) {
            warn!(
                "[vault] Failed to remove invalid user key from cache: {:?}",
                e
            );
        }

        Ok(())
    }

    /// Get all ciphers for a user
    pub async fn get_all_ciphers(&self, user_id: &str) -> AppResult<Vec<CipherView>> {
        debug!(user_id = user_id, "[vault] Getting all ciphers for user");

        // Try to get from cache first
        let cached_ciphers = self.get_cached_ciphers(user_id).await;
        if !cached_ciphers.is_empty() {
            debug!(
                user_id = user_id,
                count = cached_ciphers.len(),
                "[vault] Retrieved {} ciphers from cache",
                cached_ciphers.len()
            );
            return Ok(cached_ciphers);
        }

        // Get from database
        let encrypted_ciphers = self.database.get_all_ciphers(user_id).await?;
        let mut decrypted_ciphers = Vec::new();
        let mut failed_count = 0;

        info!(
            user_id = user_id,
            encrypted_count = encrypted_ciphers.len(),
            "[vault] Retrieved {} encrypted ciphers from database, starting decryption",
            encrypted_ciphers.len()
        );

        for cipher in encrypted_ciphers {
            match self.decrypt_cipher(&cipher).await {
                Ok(decrypted) => {
                    // Cache the decrypted cipher
                    self.cache.cache_cipher(decrypted.clone()).await;
                    decrypted_ciphers.push(decrypted);
                }
                Err(e) => {
                    failed_count += 1;

                    // Check if this is a MAC verification failure and clear cache
                    let error_str = format!("{:?}", e);
                    if error_str.contains("MAC verification failed") {
                        warn!(
                            user_id = user_id,
                            cipher_id = %cipher.id,
                            error = %e,
                            "[vault] MAC verification failed, clearing user key cache"
                        );

                        // Clear the invalid user key from cache
                        if let Err(clear_err) = self.clear_invalid_user_key(&cipher.user_id).await {
                            warn!(
                                user_id = user_id,
                                cipher_id = %cipher.id,
                                error = %clear_err,
                                "[vault] Failed to clear invalid user key from cache"
                            );
                        }
                    }

                    warn!(
                        user_id = user_id,
                        cipher_id = %cipher.id,
                        error = %e,
                        "[vault] Failed to decrypt cipher {}: {}",
                        cipher.id,
                        e
                    );
                    log_vault_operation("decrypt", "cipher", Some(&cipher.id), false);
                    continue;
                }
            }
        }

        if failed_count > 0 {
            warn!(
                user_id = user_id,
                failed_count = failed_count,
                success_count = decrypted_ciphers.len(),
                "[vault] Completed cipher decryption with {} failures out of {} total",
                failed_count,
                decrypted_ciphers.len() + failed_count
            );
        } else {
            info!(
                user_id = user_id,
                count = decrypted_ciphers.len(),
                "[vault] Successfully decrypted all {} ciphers",
                decrypted_ciphers.len()
            );
        }
        Ok(decrypted_ciphers)
    }

    /// Decrypt ciphers with resilient error handling (Bitwarden-style)
    /// Returns (successful_ciphers, failed_ciphers) tuple
    pub async fn decrypt_ciphers_resilient(
        &self,
        user_id: &str,
    ) -> AppResult<(Vec<CipherView>, Vec<CipherView>)> {
        // Get encrypted ciphers from database
        let encrypted_ciphers = self.database.get_all_ciphers(user_id).await?;

        info!(
            user_id = user_id,
            encrypted_count = encrypted_ciphers.len(),
            "[vault] Retrieved {} encrypted ciphers from database, starting resilient decryption",
            encrypted_ciphers.len()
        );

        let mut successful_ciphers = Vec::new();
        let mut failed_ciphers = Vec::new();
        let mut consecutive_failures = 0;
        let max_consecutive_failures = 5; // Circuit breaker threshold

        for cipher in encrypted_ciphers {
            match self.decrypt_cipher_resilient(&cipher).await {
                Ok(decrypted) => {
                    successful_ciphers.push(decrypted);
                    consecutive_failures = 0; // Reset on success

                    // Record success for circuit breaker recovery
                    self.record_decryption_success(user_id).await;
                }
                Err(e) => {
                    consecutive_failures += 1;

                    // Create a failed cipher view for display
                    let failed_cipher = self.create_failed_cipher_view(&cipher, &e);
                    failed_ciphers.push(failed_cipher);

                    warn!(
                        user_id = user_id,
                        cipher_id = %cipher.id,
                        error = %e,
                        consecutive_failures = consecutive_failures,
                        error_type = ?std::mem::discriminant(&e),
                        "[vault] Failed to decrypt cipher {}: {}",
                        cipher.id,
                        e
                    );

                    // Circuit breaker: check if we should stop based on error patterns
                    if self.should_stop_decryption(user_id, &e).await {
                        warn!(
                            user_id = user_id,
                            consecutive_failures = consecutive_failures,
                            total_processed = successful_ciphers.len() + failed_ciphers.len(),
                            "[vault] Circuit breaker triggered - stopping decryption"
                        );
                        break;
                    }

                    // Also check consecutive failure threshold as backup
                    if consecutive_failures >= max_consecutive_failures {
                        warn!(
                            user_id = user_id,
                            consecutive_failures = consecutive_failures,
                            max_consecutive_failures = max_consecutive_failures,
                            "[vault] Max consecutive failures reached - stopping decryption"
                        );
                        break;
                    }

                    log_vault_operation("decrypt", "cipher", Some(&cipher.id), false);
                }
            }
        }

        Ok((successful_ciphers, failed_ciphers))
    }

    /// Decrypt a cipher with resilient error handling (no aggressive key clearing)
    async fn decrypt_cipher_resilient(&self, cipher: &Cipher) -> AppResult<CipherView> {
        debug!(
            cipher_id = %cipher.id,
            cipher_type = cipher.cipher_type,
            "[vault] Starting resilient cipher decryption"
        );

        // Get the user key from crypto cache
        let user_key = match self.cache.get_user_key(&cipher.user_id).await {
            Ok(Some(key)) => key,
            Ok(None) => {
                error!(
                    cipher_id = %cipher.id,
                    user_id = %cipher.user_id,
                    "[vault] No user key found in cache for cipher decryption. User needs to re-authenticate."
                );
                return Err(AppError::ReAuthenticationRequired {
                    message: "Your session has expired. Please enter your master password to decrypt your vault.".to_string(),
                });
            }
            Err(e) => {
                warn!(
                    cipher_id = %cipher.id,
                    user_id = %cipher.user_id,
                    error = %e,
                    "[vault] Failed to retrieve user key from cache"
                );
                return Err(e);
            }
        };

        // Decrypt the basic cipher fields with better error classification
        let decrypted_name = match CipherCrypto::decrypt_string(&cipher.name, &user_key) {
            Ok(name) => name,
            Err(e) => {
                // Classify the error type based on Bitwarden patterns
                return self
                    .handle_decryption_error(&cipher.user_id, &cipher.id, e)
                    .await;
            }
        };

        let decrypted_notes = CipherCrypto::decrypt_optional_string(&cipher.notes, &user_key)?;

        // Continue with the rest of the decryption...
        let cipher_type = match cipher.cipher_type {
            1 => crate::models::CipherType::Login,
            2 => crate::models::CipherType::SecureNote,
            3 => crate::models::CipherType::Card,
            4 => crate::models::CipherType::Identity,
            _ => crate::models::CipherType::Login,
        };

        // Parse the encrypted_data JSON without decrypting it first
        // Individual fields will be decrypted by the parse_*_data methods
        let encrypted_data_json: Value = serde_json::from_str(&cipher.encrypted_data)
            .map_err(|e| AppError::permanent_decryption_error(
                "parse_cipher_data_json".to_string(),
                format!("Invalid JSON in cipher data: {}", e),
            ))?;

        // Parse type-specific data
        let (login, secure_note, card, identity) = match cipher_type {
            crate::models::CipherType::Login => {
                let login_data = self.parse_login_data(&encrypted_data_json, &user_key)?;
                (Some(login_data), None, None, None)
            }
            crate::models::CipherType::SecureNote => {
                let secure_note_data = self.parse_secure_note_data(&encrypted_data_json)?;
                (None, Some(secure_note_data), None, None)
            }
            crate::models::CipherType::Card => {
                let card_data = self.parse_card_data(&encrypted_data_json, &user_key)?;
                (None, None, Some(card_data), None)
            }
            crate::models::CipherType::Identity => {
                let identity_data = self.parse_identity_data(&encrypted_data_json, &user_key)?;
                (None, None, None, Some(identity_data))
            }
        };

        Ok(CipherView {
            id: cipher.id.clone(),
            organization_id: cipher.organization_id.clone(),
            folder_id: cipher.folder_id.clone(),
            name: decrypted_name,
            notes: decrypted_notes,
            cipher_type,
            login,
            secure_note,
            card,
            identity,
            favorite: cipher.favorite,
            reprompt: cipher.reprompt,
            revision_date: cipher.revision_date,
            created_date: cipher.created_date,
        })
    }

    /// Handle decryption errors with smart classification (Bitwarden-style)
    async fn handle_decryption_error(
        &self,
        user_id: &str,
        cipher_id: &str,
        error: AppError,
    ) -> AppResult<CipherView> {
        // Record the failure in cache for tracking
        if let Ok(threshold_exceeded) = CRYPTO_CACHE.record_failure(user_id) {
            if threshold_exceeded {
                warn!(
                    user_id = user_id,
                    cipher_id = cipher_id,
                    "[vault] Failure threshold exceeded for user - considering key validation"
                );

                // Only invalidate key if we should based on failure patterns
                if let Ok(should_invalidate) = CRYPTO_CACHE.should_invalidate_user_key(user_id) {
                    if should_invalidate {
                        warn!(
                            user_id = user_id,
                            "[vault] Invalidating user key due to consistent failure pattern"
                        );
                        self.clear_invalid_user_key(user_id).await?;
                        return Err(AppError::KeyValidationError {
                            key_type: "user_key".to_string(),
                            message:
                                "User key validation failed due to consistent decryption failures"
                                    .to_string(),
                        });
                    }
                }
            }
        }

        // Classify error type based on content
        let error_str = format!("{:?}", error);
        if error_str.contains("MAC verification failed") {
            return Err(AppError::MacVerificationError {
                context: format!("cipher_{}_{}", user_id, cipher_id),
                message: "MAC verification failed - could be data corruption or key mismatch"
                    .to_string(),
            });
        }

        // Return as transient error for retry
        Err(AppError::TransientDecryptionError {
            operation: "decrypt_cipher_name".to_string(),
            message: format!("Decryption failed: {}", error),
            retry_count: 1,
        })
    }

    /// Create a failed cipher view for display (Bitwarden pattern)
    fn create_failed_cipher_view(&self, cipher: &Cipher, error: &AppError) -> CipherView {
        CipherView {
            id: cipher.id.clone(),
            organization_id: cipher.organization_id.clone(),
            folder_id: cipher.folder_id.clone(),
            name: format!("[Decryption Failed] {}", cipher.id), // Show ID for failed items
            notes: Some(format!("Failed to decrypt: {}", error)),
            cipher_type: crate::models::CipherType::Login, // Default type
            login: None,
            secure_note: None,
            card: None,
            identity: None,
            favorite: cipher.favorite,
            reprompt: cipher.reprompt,
            revision_date: cipher.revision_date,
            created_date: cipher.created_date,
        }
    }

    /// Determine if decryption should stop based on error patterns and circuit breaker
    async fn should_stop_decryption(&self, user_id: &str, error: &AppError) -> bool {
        let service_name = format!("vault_decryption_{}", user_id);

        // Check circuit breaker state
        if let Ok(can_execute) = CRYPTO_CACHE.can_execute(&service_name) {
            if !can_execute {
                warn!(
                    user_id = user_id,
                    service = service_name,
                    "[vault] Circuit breaker is open - stopping decryption"
                );
                return true;
            }
        }

        // Record failure in circuit breaker if this should trigger it
        if error.should_trigger_circuit_breaker() {
            if let Ok(is_open) = CRYPTO_CACHE.record_circuit_failure(&service_name) {
                if is_open {
                    warn!(
                        user_id = user_id,
                        error = %error,
                        "[vault] Circuit breaker opened due to permanent failure"
                    );
                    return true;
                }
            }
        }

        // Stop if this is a key validation error (permanent failure)
        if error.should_invalidate_key() {
            warn!(
                user_id = user_id,
                error = %error,
                "[vault] Stopping decryption due to key validation failure"
            );
            return true;
        }

        // Continue for transient errors
        false
    }

    /// Record successful decryption for circuit breaker recovery
    async fn record_decryption_success(&self, user_id: &str) {
        let service_name = format!("vault_decryption_{}", user_id);

        if let Err(e) = CRYPTO_CACHE.record_success(&service_name) {
            warn!(
                user_id = user_id,
                service = service_name,
                error = %e,
                "[vault] Failed to record circuit breaker success"
            );
        }
    }

    /// Save a cipher
    pub async fn save_cipher(&self, cipher: CipherView, user_id: &str) -> AppResult<()> {
        debug!(
            user_id = user_id,
            cipher_id = %cipher.id,
            cipher_name = %cipher.name,
            "[vault] Saving cipher"
        );

        // Encrypt the cipher
        let encrypted_cipher = self.encrypt_cipher(&cipher, user_id).await?;

        // Save to database
        self.database
            .save_cipher(user_id, &encrypted_cipher)
            .await?;

        // Update cache
        self.cache.cache_cipher(cipher.clone()).await;

        info!(
            user_id = user_id,
            cipher_id = %cipher.id,
            cipher_name = %cipher.name,
            "[vault] Successfully saved cipher"
        );
        log_vault_operation("save", "cipher", Some(&cipher.id), true);
        Ok(())
    }

    /// Delete a cipher
    pub async fn delete_cipher(&self, cipher_id: &str, user_id: &str) -> AppResult<()> {
        info!(
            user_id = user_id,
            cipher_id = cipher_id,
            "[vault] Deleting cipher"
        );

        // Remove from database
        self.database.delete_cipher(cipher_id, user_id).await?;

        // Remove from cache
        self.cache.remove_cipher(cipher_id).await;

        info!(
            user_id = user_id,
            cipher_id = cipher_id,
            "[vault] Successfully deleted cipher"
        );
        log_vault_operation("delete", "cipher", Some(cipher_id), true);
        Ok(())
    }

    /// Search ciphers
    pub async fn search_ciphers(&self, query: &str, user_id: &str) -> AppResult<Vec<CipherView>> {
        let all_ciphers = self.get_all_ciphers(user_id).await?;
        let query_lower = query.to_lowercase();

        let filtered_ciphers: Vec<CipherView> = all_ciphers
            .into_iter()
            .filter(|cipher| {
                cipher.name.to_lowercase().contains(&query_lower)
                    || cipher
                        .notes
                        .as_ref()
                        .map_or(false, |notes| notes.to_lowercase().contains(&query_lower))
                    || cipher.login.as_ref().map_or(false, |login| {
                        login.username.as_ref().map_or(false, |username| {
                            username.to_lowercase().contains(&query_lower)
                        })
                    })
            })
            .collect();

        Ok(filtered_ciphers)
    }

    /// Get folders for a user
    pub async fn get_folders(&self, user_id: &str) -> AppResult<Vec<Folder>> {
        self.database.get_folders(user_id).await
    }

    /// Save a folder
    pub async fn save_folder(&self, folder: &Folder) -> AppResult<()> {
        self.database.save_folder(folder).await
    }

    /// Delete a folder
    pub async fn delete_folder(&self, folder_id: &str, user_id: &str) -> AppResult<()> {
        self.database.delete_folder(folder_id, user_id).await
    }

    /// Get collections for an organization
    pub async fn get_collections(&self, organization_id: &str) -> AppResult<Vec<Collection>> {
        self.database.get_collections(organization_id).await
    }

    /// Get cached ciphers
    async fn get_cached_ciphers(&self, _user_id: &str) -> Vec<CipherView> {
        // In a real implementation, you would filter by user_id
        // For now, return empty to force database lookup
        Vec::new()
    }

    /// Decrypt a cipher
    async fn decrypt_cipher(&self, cipher: &Cipher) -> AppResult<CipherView> {
        debug!(
            cipher_id = %cipher.id,
            cipher_type = cipher.cipher_type,
            "[vault] Starting cipher decryption"
        );

        // Get the user key from crypto cache
        let user_key = match self.cache.get_user_key(&cipher.user_id).await {
            Ok(Some(key)) => key,
            Ok(None) => {
                error!(
                    cipher_id = %cipher.id,
                    user_id = %cipher.user_id,
                    "[vault] No user key found in cache for cipher decryption. User needs to re-authenticate."
                );
                return Err(crate::error::AppError::ReAuthenticationRequired {
                    message: "Your session has expired. Please enter your master password to decrypt your vault.".to_string(),
                });
            }
            Err(e) => {
                warn!(
                    cipher_id = %cipher.id,
                    user_id = %cipher.user_id,
                    error = %e,
                    "[vault] Failed to retrieve user key from cache"
                );
                return Err(e);
            }
        };

        // Decrypt the basic cipher fields
        let decrypted_name = match CipherCrypto::decrypt_string(&cipher.name, &user_key) {
            Ok(name) => name,
            Err(e) => {
                warn!("[vault] Failed to decrypt cipher {}: {:?}", cipher.id, e);

                // Check if this is a MAC verification failure (key mismatch)
                let is_mac_failure = match &e {
                    crate::error::AppError::CryptographyError { operation } => {
                        debug!("[vault] CryptographyError operation: {}", operation);
                        operation.contains("decrypt_string")
                    }
                    _ => {
                        // Check if the error message contains MAC verification failure
                        let error_str = format!("{:?}", e);
                        debug!(
                            "[vault] Checking error string for MAC failure: {}",
                            error_str
                        );
                        error_str.contains("MAC verification failed")
                    }
                };

                if is_mac_failure {
                    warn!("[vault] Detected MAC verification failure for cipher {} - user key is invalid", cipher.id);

                    // Clear the invalid user key from cache
                    if let Err(clear_err) = self.clear_invalid_user_key(&cipher.user_id).await {
                        warn!("[vault] Failed to clear invalid user key: {:?}", clear_err);
                    }

                    return Err(crate::error::AppError::AuthenticationError {
                        message:
                            "User key is invalid. Please re-authenticate to decrypt your vault."
                                .to_string(),
                    });
                } else {
                    return Err(crate::error::AppError::CryptographyError {
                        operation: format!("decrypt_string: {}", e),
                    });
                }
            }
        };

        let decrypted_notes = CipherCrypto::decrypt_optional_string(&cipher.notes, &user_key)?;

        // Decrypt the cipher data based on type
        let cipher_type = match cipher.cipher_type {
            1 => crate::models::CipherType::Login,
            2 => crate::models::CipherType::SecureNote,
            3 => crate::models::CipherType::Card,
            4 => crate::models::CipherType::Identity,
            _ => crate::models::CipherType::Login,
        };

        // Parse the encrypted_data JSON without decrypting it first
        // Individual fields will be decrypted by the parse_*_data methods
        let encrypted_data_json: Value = serde_json::from_str(&cipher.encrypted_data)
            .map_err(|e| AppError::permanent_decryption_error(
                "parse_cipher_data_json".to_string(),
                format!("Invalid JSON in cipher data: {}", e),
            ))?;

        // Parse type-specific data
        let (login, secure_note, card, identity) = match cipher_type {
            crate::models::CipherType::Login => {
                let login_data = self.parse_login_data(&encrypted_data_json, &user_key)?;
                (Some(login_data), None, None, None)
            }
            crate::models::CipherType::SecureNote => {
                let secure_note_data = self.parse_secure_note_data(&encrypted_data_json)?;
                (None, Some(secure_note_data), None, None)
            }
            crate::models::CipherType::Card => {
                let card_data = self.parse_card_data(&encrypted_data_json, &user_key)?;
                (None, None, Some(card_data), None)
            }
            crate::models::CipherType::Identity => {
                let identity_data = self.parse_identity_data(&encrypted_data_json, &user_key)?;
                (None, None, None, Some(identity_data))
            }
        };

        debug!(
            cipher_id = %cipher.id,
            cipher_name = %decrypted_name,
            "[vault] Successfully decrypted cipher"
        );

        Ok(CipherView {
            id: cipher.id.clone(),
            organization_id: cipher.organization_id.clone(),
            folder_id: cipher.folder_id.clone(),
            name: decrypted_name,
            notes: decrypted_notes,
            cipher_type,
            login,
            secure_note,
            card,
            identity,
            favorite: cipher.favorite,
            reprompt: cipher.reprompt,
            revision_date: cipher.revision_date,
            created_date: cipher.created_date,
        })
    }

    /// Encrypt a cipher
    async fn encrypt_cipher(&self, cipher: &CipherView, user_id: &str) -> AppResult<Cipher> {
        // This is a placeholder - in a real implementation, you would:
        // 1. Get the user's encryption key
        // 2. Serialize the cipher data to JSON
        // 3. Encrypt the JSON data

        Ok(Cipher {
            id: cipher.id.clone(),
            user_id: user_id.to_string(),
            organization_id: cipher.organization_id.clone(),
            folder_id: cipher.folder_id.clone(),
            name: cipher.name.clone(),
            notes: cipher.notes.clone(),
            cipher_type: cipher.cipher_type.clone() as i32,
            encrypted_data: "encrypted_placeholder".to_string(), // Would be actual encrypted data
            favorite: cipher.favorite,
            reprompt: cipher.reprompt,
            revision_date: cipher.revision_date,
            created_date: cipher.created_date,
            deleted_date: None,
            enc_type: 2, // AES-256-CBC with HMAC-SHA256
            mac: None,
        })
    }

    /// Parse login cipher data
    fn parse_login_data(&self, data: &Value, user_key: &UserKey) -> AppResult<LoginView> {
        let login_obj = data.get("login").unwrap_or(&Value::Null);

        let username = login_obj
            .get("username")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let password = login_obj
            .get("password")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let totp = login_obj
            .get("totp")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        // Parse URIs
        let mut uris = Vec::new();
        if let Some(uris_array) = login_obj.get("uris").and_then(|v| v.as_array()) {
            for uri_obj in uris_array {
                let uri = uri_obj
                    .get("uri")
                    .and_then(|v| v.as_str())
                    .map(|s| CipherCrypto::decrypt_string(s, user_key))
                    .transpose()?;

                let match_type = uri_obj
                    .get("match")
                    .and_then(|v| v.as_i64())
                    .map(|i| i as i32);

                uris.push(LoginUriView { uri, match_type });
            }
        }

        Ok(LoginView {
            username,
            password,
            totp,
            uris,
        })
    }

    /// Parse secure note cipher data
    fn parse_secure_note_data(&self, data: &Value) -> AppResult<SecureNoteView> {
        let note_type = data
            .get("secureNote")
            .and_then(|v| v.get("type"))
            .and_then(|v| v.as_i64())
            .unwrap_or(0) as i32;

        Ok(SecureNoteView { note_type })
    }

    /// Parse card cipher data
    fn parse_card_data(&self, data: &Value, user_key: &UserKey) -> AppResult<CardView> {
        let card_obj = data.get("card").unwrap_or(&Value::Null);

        let cardholder_name = card_obj
            .get("cardholderName")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let brand = card_obj
            .get("brand")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let number = card_obj
            .get("number")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let exp_month = card_obj
            .get("expMonth")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let exp_year = card_obj
            .get("expYear")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let code = card_obj
            .get("code")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        Ok(CardView {
            cardholder_name,
            brand,
            number,
            exp_month,
            exp_year,
            code,
        })
    }

    /// Parse identity cipher data
    fn parse_identity_data(&self, data: &Value, user_key: &UserKey) -> AppResult<IdentityView> {
        let identity_obj = data.get("identity").unwrap_or(&Value::Null);

        let title = identity_obj
            .get("title")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let first_name = identity_obj
            .get("firstName")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let middle_name = identity_obj
            .get("middleName")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let last_name = identity_obj
            .get("lastName")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let address1 = identity_obj
            .get("address1")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let address2 = identity_obj
            .get("address2")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let address3 = identity_obj
            .get("address3")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let city = identity_obj
            .get("city")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let state = identity_obj
            .get("state")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let postal_code = identity_obj
            .get("postalCode")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let country = identity_obj
            .get("country")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let company = identity_obj
            .get("company")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let email = identity_obj
            .get("email")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let phone = identity_obj
            .get("phone")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let ssn = identity_obj
            .get("ssn")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let username = identity_obj
            .get("username")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let passport_number = identity_obj
            .get("passportNumber")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        let license_number = identity_obj
            .get("licenseNumber")
            .and_then(|v| v.as_str())
            .map(|s| CipherCrypto::decrypt_string(s, user_key))
            .transpose()?;

        Ok(IdentityView {
            title,
            first_name,
            middle_name,
            last_name,
            address1,
            address2,
            address3,
            city,
            state,
            postal_code,
            country,
            company,
            email,
            phone,
            ssn,
            username,
            passport_number,
            license_number,
        })
    }
}
