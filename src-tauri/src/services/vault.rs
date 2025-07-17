use crate::crypto::CryptoService;
use crate::error::AppResult;
use crate::logging::log_vault_operation;
use crate::models::{Cipher, CipherView, Collection, Folder};
use crate::storage::{AppDatabase, MemoryCache};
use std::sync::Arc;
use tracing::{debug, info, warn};

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

    /// Get all ciphers for a user
    pub async fn get_all_ciphers(&self, user_id: &str) -> AppResult<Vec<CipherView>> {debug!(user_id = user_id, "[vault] Getting all ciphers for user");

        // Try to get from cache first
        let cached_ciphers = self.get_cached_ciphers(user_id).await;
        if !cached_ciphers.is_empty() {
            debug!(
                user_id = user_id,
                count = cached_ciphers.len(),
                "[vault] Retrieved {} ciphers from cache",
                cached_ciphers.len()
            );return Ok(cached_ciphers);
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
        }Ok(decrypted_ciphers)
    }

    /// Save a cipher
    pub async fn save_cipher(&self, cipher: CipherView, user_id: &str) -> AppResult<()> {debug!(
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
        log_vault_operation("save", "cipher", Some(&cipher.id), true);Ok(())
    }

    /// Delete a cipher
    pub async fn delete_cipher(&self, cipher_id: &str, user_id: &str) -> AppResult<()> {info!(
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
        log_vault_operation("delete", "cipher", Some(cipher_id), true);Ok(())
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
        // This is a placeholder - in a real implementation, you would:
        // 1. Get the user's encryption key
        // 2. Decrypt the cipher data
        // 3. Parse the decrypted JSON into appropriate structures

        // For now, return a basic CipherView
        Ok(CipherView {
            id: cipher.id.clone(),
            organization_id: cipher.organization_id.clone(),
            folder_id: cipher.folder_id.clone(),
            name: cipher.name.clone(),
            notes: cipher.notes.clone(),
            cipher_type: match cipher.cipher_type {
                1 => crate::models::CipherType::Login,
                2 => crate::models::CipherType::SecureNote,
                3 => crate::models::CipherType::Card,
                4 => crate::models::CipherType::Identity,
                _ => crate::models::CipherType::Login,
            },
            login: None, // Would be populated from decrypted data
            secure_note: None,
            card: None,
            identity: None,
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
}
