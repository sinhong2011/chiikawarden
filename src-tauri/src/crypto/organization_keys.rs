use crate::crypto::{EncryptionService, EncryptionType, UserKey};
use crate::debug_config::CorrelationId;
use crate::error::{AppError, AppResult};
use crate::models::cipher::Cipher;
use crate::storage::database::AppDatabase;
use base64::{engine::general_purpose, Engine as _};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use std::sync::Arc;
use tracing::{debug, error, info, warn};
use zeroize::ZeroizeOnDrop;

/// Organization key for encrypting/decrypting organization-owned ciphers
#[derive(Debug, Clone, ZeroizeOnDrop)]
pub struct OrganizationKey {
    #[zeroize(skip)]
    pub organization_id: String,
    pub key_data: Vec<u8>,
    #[zeroize(skip)]
    pub created_at: DateTime<Utc>,
    #[zeroize(skip)]
    pub updated_at: DateTime<Utc>,
}

impl OrganizationKey {
    /// Create a new organization key
    pub fn new(organization_id: String, key_data: Vec<u8>) -> Self {
        let now = Utc::now();
        Self {
            organization_id,
            key_data,
            created_at: now,
            updated_at: now,
        }
    }

    /// Get the key data as bytes
    pub fn as_bytes(&self) -> &[u8] {
        &self.key_data
    }

    /// Get the organization ID
    pub fn organization_id(&self) -> &str {
        &self.organization_id
    }
}

/// Organization key database record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrganizationKeyRecord {
    pub id: String,
    pub organization_id: String,
    pub user_id: String,
    pub encrypted_key: String,
    pub key_type: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub is_active: bool,
}

impl OrganizationKeyRecord {
    /// Create from database row
    pub fn from_database_row(row: &serde_json::Value) -> AppResult<Self> {
        let get_string = |key: &str| -> AppResult<String> {
            row.get(key)
                .and_then(|v| v.as_str())
                .ok_or_else(|| AppError::DatabaseError {
                    message: format!("Missing or invalid string field: {}", key),
                })
                .map(|s| s.to_string())
        };

        let get_bool = |key: &str| -> AppResult<bool> {
            row.get(key)
                .and_then(|v| v.as_i64())
                .ok_or_else(|| AppError::DatabaseError {
                    message: format!("Missing or invalid boolean field: {}", key),
                })
                .map(|i| i != 0)
        };

        let get_datetime = |key: &str| -> AppResult<DateTime<Utc>> {
            let date_str = get_string(key)?;
            DateTime::parse_from_rfc3339(&date_str)
                .map(|dt| dt.with_timezone(&Utc))
                .map_err(|_| AppError::DatabaseError {
                    message: format!("Invalid datetime format for field: {}", key),
                })
        };

        Ok(OrganizationKeyRecord {
            id: get_string("id")?,
            organization_id: get_string("organization_id")?,
            user_id: get_string("user_id")?,
            encrypted_key: get_string("encrypted_key")?,
            key_type: get_string("key_type")?,
            created_at: get_datetime("created_at")?,
            updated_at: get_datetime("updated_at")?,
            is_active: get_bool("is_active")?,
        })
    }
}

/// Organization key management service
pub struct OrganizationKeyService {
    database: Arc<AppDatabase>,
}

impl OrganizationKeyService {
    /// Create a new organization key service
    pub fn new(database: Arc<AppDatabase>) -> Self {
        Self { database }
    }

    /// Store an organization key encrypted with the user's key
    pub async fn store_organization_key(
        &self,
        organization_id: &str,
        user_id: &str,
        organization_key: &OrganizationKey,
        user_key: &UserKey,
        correlation_id: &CorrelationId,
    ) -> AppResult<()> {
        debug!(
            organization_id = organization_id,
            user_id = user_id,
            correlation_id = %correlation_id,
            "[org_keys] Storing organization key"
        );

        // Encrypt organization key with user key
        let encrypted_data = EncryptionService::encrypt(
            organization_key.as_bytes(),
            user_key.as_bytes(),
            EncryptionType::AesCbc256HmacSha256B64,
        )
        .map_err(|e| AppError::CryptographyError {
            operation: format!("Organization key encryption failed: {}", e),
        })?;

        let encrypted_key_b64 = general_purpose::STANDARD.encode(&encrypted_data.data);

        // Store in database
        let record = OrganizationKeyRecord {
            id: uuid::Uuid::new_v4().to_string(),
            organization_id: organization_id.to_string(),
            user_id: user_id.to_string(),
            encrypted_key: encrypted_key_b64,
            key_type: "organization".to_string(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            is_active: true,
        };

        self.store_organization_key_record(&record).await?;

        info!(
            organization_id = organization_id,
            user_id = user_id,
            correlation_id = %correlation_id,
            "[org_keys] Organization key stored successfully"
        );

        Ok(())
    }

    /// Retrieve and decrypt an organization key
    pub async fn get_organization_key(
        &self,
        organization_id: &str,
        user_id: &str,
        user_key: &UserKey,
        correlation_id: &CorrelationId,
    ) -> AppResult<Option<OrganizationKey>> {
        debug!(
            organization_id = organization_id,
            user_id = user_id,
            correlation_id = %correlation_id,
            "[org_keys] Retrieving organization key"
        );

        // Get encrypted key from database
        let record = self
            .get_organization_key_record(organization_id, user_id)
            .await?;

        let record = match record {
            Some(r) => r,
            None => {
                debug!(
                    organization_id = organization_id,
                    user_id = user_id,
                    correlation_id = %correlation_id,
                    "[org_keys] Organization key not found"
                );
                return Ok(None);
            }
        };

        if !record.is_active {
            warn!(
                organization_id = organization_id,
                user_id = user_id,
                correlation_id = %correlation_id,
                "[org_keys] Organization key is inactive"
            );
            return Ok(None);
        }

        // Decrypt organization key
        let encrypted_data = general_purpose::STANDARD
            .decode(&record.encrypted_key)
            .map_err(|e| AppError::CryptographyError {
                operation: format!("Failed to decode organization key: {}", e),
            })?;

        // Create EncryptedData structure for decryption
        let encrypted_data_struct = crate::crypto::EncryptedData {
            iv: vec![0u8; 16], // Placeholder - in production, store IV separately
            data: encrypted_data,
            mac: None,
        };

        let decrypted_key = EncryptionService::decrypt(
            &encrypted_data_struct,
            user_key.as_bytes(),
            EncryptionType::AesCbc256B64,
        )
        .map_err(|e| AppError::CryptographyError {
            operation: format!("Organization key decryption failed: {}", e),
        })?;

        let org_key = OrganizationKey::new(organization_id.to_string(), decrypted_key);

        info!(
            organization_id = organization_id,
            user_id = user_id,
            correlation_id = %correlation_id,
            "[org_keys] Organization key retrieved successfully"
        );

        Ok(Some(org_key))
    }

    /// Validate organization key against sample ciphers
    pub async fn validate_organization_key(
        &self,
        organization_id: &str,
        organization_key: &OrganizationKey,
        correlation_id: &CorrelationId,
    ) -> AppResult<bool> {
        debug!(
            organization_id = organization_id,
            correlation_id = %correlation_id,
            "[org_keys] Validating organization key"
        );

        // Get sample organization ciphers for validation
        let sample_ciphers = self
            .database
            .get_sample_organization_ciphers(organization_id, 5)
            .await?;

        if sample_ciphers.is_empty() {
            debug!(
                organization_id = organization_id,
                correlation_id = %correlation_id,
                "[org_keys] No sample ciphers found - key validation skipped"
            );
            return Ok(true); // No ciphers to validate against
        }

        let mut successful_decryptions = 0;
        let mut total_attempts = 0;

        for cipher in &sample_ciphers {
            total_attempts += 1;

            match self
                .validate_cipher_with_org_key(cipher, organization_key, correlation_id)
                .await
            {
                Ok(true) => {
                    successful_decryptions += 1;
                    debug!(
                        cipher_id = cipher.id,
                        organization_id = organization_id,
                        correlation_id = %correlation_id,
                        "[org_keys] Cipher decryption successful"
                    );
                }
                Ok(false) => {
                    warn!(
                        cipher_id = cipher.id,
                        organization_id = organization_id,
                        correlation_id = %correlation_id,
                        "[org_keys] Cipher decryption failed - MAC verification failed"
                    );
                }
                Err(e) => {
                    error!(
                        cipher_id = cipher.id,
                        organization_id = organization_id,
                        error = %e,
                        correlation_id = %correlation_id,
                        "[org_keys] Cipher decryption error"
                    );
                }
            }
        }

        let validation_success = successful_decryptions == total_attempts && total_attempts > 0;

        if validation_success {
            info!(
                organization_id = organization_id,
                successful_decryptions = successful_decryptions,
                total_attempts = total_attempts,
                correlation_id = %correlation_id,
                "[org_keys] Organization key validation successful"
            );
        } else {
            error!(
                organization_id = organization_id,
                successful_decryptions = successful_decryptions,
                total_attempts = total_attempts,
                correlation_id = %correlation_id,
                "[org_keys] Organization key validation failed"
            );
        }

        Ok(validation_success)
    }

    /// Validate a single cipher with organization key
    async fn validate_cipher_with_org_key(
        &self,
        cipher: &Cipher,
        organization_key: &OrganizationKey,
        correlation_id: &CorrelationId,
    ) -> AppResult<bool> {
        // Create a temporary UserKey from organization key for decryption
        // This is a workaround since CipherCrypto expects UserKey
        let temp_user_key = UserKey::new(organization_key.as_bytes().to_vec());

        // Try to decrypt cipher name as a validation test
        if !cipher.name.is_empty() {
            match crate::crypto::cipher_crypto::CipherCrypto::decrypt_string(
                &cipher.name,
                &temp_user_key,
            ) {
                Ok(_decrypted_name) => {
                    debug!(
                        cipher_id = cipher.id,
                        correlation_id = %correlation_id,
                        "[org_keys] Cipher name decryption successful"
                    );
                    return Ok(true);
                }
                Err(e) => {
                    debug!(
                        cipher_id = cipher.id,
                        error = %e,
                        correlation_id = %correlation_id,
                        "[org_keys] Cipher name decryption failed"
                    );
                    return Ok(false);
                }
            }
        }

        // If no name, try notes
        if let Some(ref encrypted_notes) = cipher.notes {
            match crate::crypto::cipher_crypto::CipherCrypto::decrypt_string(
                encrypted_notes,
                &temp_user_key,
            ) {
                Ok(_decrypted_notes) => {
                    debug!(
                        cipher_id = cipher.id,
                        correlation_id = %correlation_id,
                        "[org_keys] Cipher notes decryption successful"
                    );
                    return Ok(true);
                }
                Err(e) => {
                    debug!(
                        cipher_id = cipher.id,
                        error = %e,
                        correlation_id = %correlation_id,
                        "[org_keys] Cipher notes decryption failed"
                    );
                    return Ok(false);
                }
            }
        }

        // No encrypted fields to validate
        warn!(
            cipher_id = cipher.id,
            correlation_id = %correlation_id,
            "[org_keys] No encrypted fields found for validation"
        );
        Ok(true)
    }

    /// Store organization key record in database
    async fn store_organization_key_record(&self, record: &OrganizationKeyRecord) -> AppResult<()> {
        let query = r#"
            INSERT INTO organization_keys
            (id, organization_id, user_id, encrypted_key, key_type, created_at, updated_at, is_active)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        "#;

        self.database
            .execute_query(
                query,
                vec![
                    serde_json::Value::String(record.id.clone()),
                    serde_json::Value::String(record.organization_id.clone()),
                    serde_json::Value::String(record.user_id.clone()),
                    serde_json::Value::String(record.encrypted_key.clone()),
                    serde_json::Value::String(record.key_type.clone()),
                    serde_json::Value::String(record.created_at.to_rfc3339()),
                    serde_json::Value::String(record.updated_at.to_rfc3339()),
                    serde_json::Value::Number((if record.is_active { 1 } else { 0 }).into()),
                ],
            )
            .await?;

        Ok(())
    }

    /// Get organization key record from database
    async fn get_organization_key_record(
        &self,
        organization_id: &str,
        user_id: &str,
    ) -> AppResult<Option<OrganizationKeyRecord>> {
        let query = r#"
            SELECT id, organization_id, user_id, encrypted_key, key_type, created_at, updated_at, is_active
            FROM organization_keys
            WHERE organization_id = ? AND user_id = ? AND is_active = 1
            ORDER BY created_at DESC
            LIMIT 1
        "#;

        let result = self
            .database
            .select_query(
                query,
                vec![
                    serde_json::Value::String(organization_id.to_string()),
                    serde_json::Value::String(user_id.to_string()),
                ],
            )
            .await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Expected array result from organization key query".to_string(),
        })?;

        if rows.is_empty() {
            return Ok(None);
        }

        let record = OrganizationKeyRecord::from_database_row(&rows[0])?;
        Ok(Some(record))
    }

    /// List all organization keys for a user
    pub async fn list_user_organization_keys(
        &self,
        user_id: &str,
        correlation_id: &CorrelationId,
    ) -> AppResult<Vec<OrganizationKeyRecord>> {
        debug!(
            user_id = user_id,
            correlation_id = %correlation_id,
            "[org_keys] Listing organization keys for user"
        );

        let query = r#"
            SELECT id, organization_id, user_id, encrypted_key, key_type, created_at, updated_at, is_active
            FROM organization_keys
            WHERE user_id = ? AND is_active = 1
            ORDER BY created_at DESC
        "#;

        let result = self
            .database
            .select_query(query, vec![serde_json::Value::String(user_id.to_string())])
            .await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Expected array result from organization keys query".to_string(),
        })?;

        let mut records = Vec::new();
        for row in rows {
            records.push(OrganizationKeyRecord::from_database_row(row)?);
        }

        info!(
            user_id = user_id,
            key_count = records.len(),
            correlation_id = %correlation_id,
            "[org_keys] Retrieved organization keys for user"
        );

        Ok(records)
    }

    /// Revoke an organization key
    pub async fn revoke_organization_key(
        &self,
        organization_id: &str,
        user_id: &str,
        correlation_id: &CorrelationId,
    ) -> AppResult<()> {
        debug!(
            organization_id = organization_id,
            user_id = user_id,
            correlation_id = %correlation_id,
            "[org_keys] Revoking organization key"
        );

        let query = r#"
            UPDATE organization_keys
            SET is_active = 0, updated_at = ?
            WHERE organization_id = ? AND user_id = ?
        "#;

        self.database
            .execute_query(
                query,
                vec![
                    serde_json::Value::String(Utc::now().to_rfc3339()),
                    serde_json::Value::String(organization_id.to_string()),
                    serde_json::Value::String(user_id.to_string()),
                ],
            )
            .await?;

        info!(
            organization_id = organization_id,
            user_id = user_id,
            correlation_id = %correlation_id,
            "[org_keys] Organization key revoked successfully"
        );

        Ok(())
    }
}
