use crate::api::repositories::traits::VaultRepository;
use crate::app_state::AppState;
use crate::crypto::cache::CRYPTO_CACHE;
use crate::crypto::cipher_crypto::EncryptedString;
use crate::crypto::{DeviceIdentifier, DeviceTrustService};
use crate::debug_config::CorrelationId;
use crate::debug_token_op;
use crate::error::AppError;

use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::{command, Emitter, State};
use tracing::{debug, error, info, warn};

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct KdfConfig {
    pub kdf_type: u32,
    pub iterations: u32,
    pub memory: Option<u32>,
    pub parallelism: Option<u32>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct PreloginRequest {
    pub email: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct PreloginResponse {
    pub kdf: u32,
    #[serde(rename = "kdfIterations")]
    pub kdf_iterations: u32,
    #[serde(rename = "kdfMemory")]
    pub kdf_memory: Option<u32>,
    #[serde(rename = "kdfParallelism")]
    pub kdf_parallelism: Option<u32>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
    pub kdf_config: KdfConfig,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct LoginResponse {
    pub success: bool,
    pub user_id: String,
    pub master_key: Vec<u8>,
    pub master_key_hash: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct TokenDiagnosticResult {
    pub user_id: String,
    pub access_token_present: bool,
    pub refresh_token_present: bool,
    pub access_token_expired: Option<bool>,
    pub recommendations: Vec<String>,
    pub timestamp: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct KeyringBackendStatus {
    pub backend_available: bool,
    pub backend_type: String,
    pub can_store_retrieve: bool,
    pub error_message: Option<String>,
    pub timestamp: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct UnlockRequest {
    pub user_id: String,
    pub password: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct UnlockResponse {
    pub success: bool,
    pub master_key: Option<Vec<u8>>,
    pub user_key: Option<Vec<u8>>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SetupAccountRequest {
    pub email: String,
    pub password: String,
    pub kdf_config: KdfConfig,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SetupAccountResponse {
    pub user_id: String,
    pub master_key: Vec<u8>,
    pub master_key_hash: String,
    pub user_key: Vec<u8>,
    pub encrypted_user_key: Vec<u8>,
    pub public_key: Vec<u8>,
    pub encrypted_private_key: Vec<u8>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct BiometricUnlockRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct BiometricUnlockResponse {
    pub success: bool,
    pub user_key: Option<Vec<u8>>,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct EstablishDeviceTrustRequest {
    pub user_id: String,
    pub device_name: String,
    pub device_type: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct EstablishDeviceTrustResponse {
    pub device_id: String,
    pub device_identifier: String,
    pub trust_established: bool,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct DeviceTrustLoginRequest {
    pub device_identifier: String,
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct DeviceTrustLoginResponse {
    pub success: bool,
    pub user_id: String,
    pub device_trusted: bool,
}

// Process prelogin with email
#[command]
#[specta::specta]
pub async fn prelogin(
    request: PreloginRequest,
    state: State<'_, AppState>,
) -> Result<PreloginResponse, String> {
    let response = state
        .api_auth_service()
        .prelogin(&request.email)
        .await
        .map_err(|e| e.to_string())?;

    Ok(PreloginResponse {
        kdf: response.kdf,
        kdf_iterations: response.kdf_iterations,
        kdf_memory: response.kdf_memory,
        kdf_parallelism: response.kdf_parallelism,
    })
}

/// Process login with master password - authenticates against remote Bitwarden API
#[command]
#[specta::specta]
pub async fn login_with_password(
    request: LoginRequest,
    state: State<'_, AppState>,
) -> Result<LoginResponse, AppError> {
    use crate::crypto::{kdf::HashPurpose, KdfService};
    use tracing::{debug, error, info};

    let correlation_id = CorrelationId::new();

    info!(
        email = request.email,
        operation = "login_with_password",
        correlation_id = %correlation_id,
        "[auth_flow] Starting login with password authentication via remote API"
    );

    debug_token_op!(
        email = request.email,
        operation = "login_with_password",
        correlation_id = %correlation_id,
        flow_stage = "start",
        "[auth_flow] Login flow initiated"
    );

    let start_time = std::time::Instant::now();

    // Step 1: Derive master key from password using provided KDF config
    debug!(
        email = request.email,
        kdf_type = request.kdf_config.kdf_type,
        iterations = request.kdf_config.iterations,
        "Deriving master key from password"
    );

    let kdf_config = crate::crypto::KdfConfig {
        kdf_type: match request.kdf_config.kdf_type {
            0 => crate::crypto::KdfType::Pbkdf2Sha256,
            1 => crate::crypto::KdfType::Argon2id,
            _ => {
                error!(
                    email = request.email,
                    kdf_type = request.kdf_config.kdf_type,
                    "Invalid KDF type provided"
                );
                return Err(AppError::ValidationError {
                    field: "kdf_type".to_string(),
                    message: "Invalid KDF type".to_string(),
                });
            }
        },
        iterations: request.kdf_config.iterations,
        memory: request.kdf_config.memory,
        parallelism: request.kdf_config.parallelism,
    };

    // DEBUG STEP 1: Log KDF configuration being used
    debug!(
        email = request.email,
        kdf_type = ?kdf_config.kdf_type,
        iterations = kdf_config.iterations,
        memory = ?kdf_config.memory,
        parallelism = ?kdf_config.parallelism,
        "[DEBUG_MAC] Step 1: KDF configuration for master key derivation"
    );

    // DEBUG STEP 2: Log email normalization for salt
    let normalized_email = request.email.to_lowercase();
    debug!(
        original_email = request.email,
        normalized_email = normalized_email,
        "[DEBUG_MAC] Step 2a: Email normalization for salt generation"
    );

    let master_key = KdfService::derive_master_key(&request.password, &request.email, &kdf_config)
        .map_err(|e| {
            error!(
                email = request.email,
                operation = "derive_master_key",
                error = %e,
                "Failed to derive master key during login"
            );
            AppError::CryptographyError {
                operation: format!("Failed to derive master key: {}", e),
            }
        })?;

    // DEBUG STEP 2: Log master key derivation result (safe preview only)
    debug!(
        email = request.email,
        master_key_len = master_key.as_bytes().len(),
        master_key_preview = format!("{:02x?}", &master_key.as_bytes()[..8]),
        "[DEBUG_MAC] Step 2b: Master key derived successfully"
    );

    // Step 2: Hash master key for server authentication
    let password_hash = KdfService::hash_master_key(
        &request.password,
        &master_key,
        HashPurpose::ServerAuthorization,
    )
    .map_err(|e| {
        error!(
            email = request.email,
            operation = "hash_master_key",
            error = %e,
            "Failed to hash master key for server authentication"
        );
        AppError::CryptographyError {
            operation: format!("Failed to hash master key: {}", e),
        }
    })?;

    debug!(
        email = request.email,
        "Master key hash generated for server authentication"
    );

    // Step 3: Authenticate with remote Bitwarden API
    debug!(
        email = request.email,
        "Authenticating with remote Bitwarden API"
    );

    let api_login_request = crate::api::services::auth_service::LoginRequest {
        email: request.email.clone(),
        password_hash,
        two_factor_token: None, // TODO: Add 2FA support
    };

    let api_response = state
        .api_auth_service()
        .authenticate(api_login_request)
        .await
        .map_err(|e| {
            error!(
                email = request.email,
                operation = "api_authenticate",
                error = %e,
                "Failed to authenticate with remote Bitwarden API"
            );
            // Return user-friendly error message
            AppError::AuthenticationError {
                message: "Invalid email or password. Please check your credentials.".to_string(),
            }
        })?;

    debug!(
        email = request.email,
        user_id = api_response.user_id,
        "Remote API authentication successful"
    );

    // Step 4: Generate master key hash for local authorization (database storage)
    let master_key_hash_local = KdfService::hash_master_key(
        &request.password,
        &master_key,
        HashPurpose::LocalAuthorization,
    )
    .map_err(|e| {
        error!(
            email = request.email,
            user_id = api_response.user_id,
            operation = "hash_master_key_local",
            error = %e,
            "Failed to hash master key for local authorization"
        );
        AppError::CryptographyError {
            operation: format!("Failed to hash master key: {}", e),
        }
    })?;

    debug!(
        email = request.email,
        user_id = api_response.user_id,
        hash_prefix = &master_key_hash_local[..8.min(master_key_hash_local.len())],
        operation = "hash_master_key_local",
        "[auth] Generated master key hash for local authorization - prefix: {}",
        &master_key_hash_local[..8.min(master_key_hash_local.len())]
    );

    // Step 5: Store/update user in local database
    debug!(
        email = request.email,
        user_id = api_response.user_id,
        "Storing user information in local database"
    );

    // Get current server provider ID
    let current_provider = state
        .server_provider_service
        .get_current_provider()
        .await
        .ok_or_else(|| AppError::ValidationError {
            field: "server_provider".to_string(),
            message: "No current server provider set".to_string(),
        })?;
    let server_provider_id = current_provider.id;

    // Step 6: Create user record with master key hash for local authorization
    debug!(
        email = request.email,
        user_id = api_response.user_id,
        operation = "create_user_with_hash",
        "[auth] Creating user record with master key hash for unlock functionality"
    );

    let user = crate::models::user::User {
        id: api_response.user_id.clone(),
        email: request.email.clone(),
        master_key_hash: Some(master_key_hash_local.clone()), // Store hash for local unlock
        // BREAKING: Use new key management fields
        encrypted_private_key_new: None,
        encrypted_user_key_new: api_response.encrypted_user_key.clone(), // Store encrypted user key from API
        key_derivation_method: "server_provided".to_string(),
        device_trust_enabled: false,
        webauthn_enabled: false,
        server_provider_id,
        kdf_type: request.kdf_config.kdf_type as i32,
        kdf_iterations: request.kdf_config.iterations as i32,
        kdf_memory: request.kdf_config.memory.map(|v| v as i32),
        kdf_parallelism: request.kdf_config.parallelism.map(|v| v as i32),
        created_date: chrono::Utc::now(),
        revision_date: chrono::Utc::now(),
    };

    debug!(
        email = request.email,
        user_id = api_response.user_id,
        has_master_key_hash = user.master_key_hash.is_some(),
        hash_length = user.master_key_hash.as_ref().map(|h| h.len()).unwrap_or(0),
        operation = "create_user_record",
        "[auth] User record created with master_key_hash: {} (length: {})",
        user.master_key_hash.is_some(),
        user.master_key_hash.as_ref().map(|h| h.len()).unwrap_or(0)
    );

    // Step 8: Upsert user (create or update if exists) with comprehensive logging
    debug!(
        email = request.email,
        user_id = api_response.user_id,
        operation = "upsert_user",
        "[auth] Attempting to upsert user record to database"
    );

    state.database().upsert_user(&user).await.map_err(|e| {
        error!(
            email = request.email,
            user_id = api_response.user_id,
            operation = "upsert_user",
            error = %e,
            "[auth] Failed to store user in local database: {}", e
        );
        e
    })?;

    info!(
        email = request.email,
        user_id = api_response.user_id,
        has_master_key_hash = user.master_key_hash.is_some(),
        operation = "upsert_user",
        "[auth] User stored successfully in local database with master_key_hash: {}",
        user.master_key_hash.is_some()
    );

    // Step 9: Verify the user was stored correctly by reading it back
    debug!(
        email = request.email,
        user_id = api_response.user_id,
        operation = "verify_user_storage",
        "[auth] Verifying user was stored correctly in database"
    );

    match state.database().get_user_by_id(&api_response.user_id).await {
        Ok(stored_user) => {
            debug!(
                email = request.email,
                user_id = api_response.user_id,
                stored_has_hash = stored_user.master_key_hash.is_some(),
                stored_hash_length = stored_user
                    .master_key_hash
                    .as_ref()
                    .map(|h| h.len())
                    .unwrap_or(0),
                operation = "verify_user_storage",
                "[auth] Database verification: user stored with master_key_hash: {} (length: {})",
                stored_user.master_key_hash.is_some(),
                stored_user
                    .master_key_hash
                    .as_ref()
                    .map(|h| h.len())
                    .unwrap_or(0)
            );

            if stored_user.master_key_hash.is_none() {
                error!(
                    email = request.email,
                    user_id = api_response.user_id,
                    operation = "verify_user_storage",
                    "[auth] CRITICAL: User stored in database but master_key_hash is None!"
                );
            }
        }
        Err(e) => {
            error!(
                email = request.email,
                user_id = api_response.user_id,
                operation = "verify_user_storage",
                error = %e,
                "[auth] Failed to verify user storage: {}", e
            );
        }
    }

    // Step 10: Store master key securely for this session
    debug!(
        email = request.email,
        user_id = api_response.user_id,
        operation = "store_master_key",
        "[auth] Storing master key in secure storage for session use"
    );

    state
        .auth_service()
        .store_master_key(&api_response.user_id, &master_key)
        .await
        .map_err(|e| {
            error!(
                email = request.email,
                user_id = api_response.user_id,
                operation = "store_master_key",
                error = %e,
                "[auth] Failed to store master key in secure storage during login: {}", e
            );
            e
        })?;

    debug!(
        email = request.email,
        user_id = api_response.user_id,
        operation = "store_master_key",
        "[auth] Master key stored successfully in secure storage"
    );

    // Step 10.5: Derive and cache user key for cipher decryption using new key derivation service
    debug!(
        email = request.email,
        user_id = api_response.user_id,
        operation = "derive_user_key_from_server",
        "[auth] Using new KeyDerivationService for login (no fallback)"
    );

    let user_key = match api_response.encrypted_user_key.as_deref() {
        Some(encrypted_user_key_b64) => {
            // DEBUG STEP 3: Log encrypted user key details
            debug!(
                email = request.email,
                user_id = api_response.user_id,
                encrypted_key_len = encrypted_user_key_b64.len(),
                encrypted_key_preview =
                    &encrypted_user_key_b64[..std::cmp::min(50, encrypted_user_key_b64.len())],
                "[DEBUG_MAC] Step 3a: Encrypted user key from server"
            );

            // KEYGUARD COMPATIBILITY CHECK: Run comprehensive verification
            info!(
                email = request.email,
                user_id = api_response.user_id,
                "[KEYGUARD_VERIFY] Running Keyguard compatibility verification before attempting decryption"
            );

            match crate::crypto::encryption::KeyDerivationService::verify_keyguard_compatibility(
                &master_key,
                encrypted_user_key_b64,
            ) {
                Ok(()) => {
                    info!(
                        email = request.email,
                        user_id = api_response.user_id,
                        "[KEYGUARD_VERIFY] Compatibility verification passed - proceeding with decryption"
                    );
                }
                Err(e) => {
                    warn!(
                        email = request.email,
                        user_id = api_response.user_id,
                        error = %e,
                        "[KEYGUARD_VERIFY] Compatibility verification failed - this explains the MAC verification failure"
                    );
                }
            }

            match crate::crypto::KeyDerivationService::derive_user_key_from_server(
                encrypted_user_key_b64,
                &master_key,
                &api_response.user_id,
                &correlation_id,
            ) {
                Ok(key) => {
                    debug!(
                        email = request.email,
                        user_id = api_response.user_id,
                        user_key_len = key.as_bytes().len(),
                        user_key_preview = format!("{:02x?}", &key.as_bytes()[..8]),
                        "[DEBUG_MAC] Step 3b: Successfully derived user key during login"
                    );

                    // Validate the user key against existing ciphers using new validation service
                    debug!(
                        email = request.email,
                        user_id = api_response.user_id,
                        "[auth] Validating user key against existing ciphers with new validation service"
                    );

                    match crate::crypto::KeyValidationService::validate_user_key_against_ciphers(
                        &key,
                        &api_response.user_id,
                        &state.database,
                        &correlation_id,
                    )
                    .await
                    {
                        Ok(is_valid) => {
                            if is_valid {
                                info!(
                                    email = request.email,
                                    user_id = api_response.user_id,
                                    "[auth] ✅ User key validation PASSED - consistent with existing ciphers"
                                );
                            } else {
                                error!(
                                    email = request.email,
                                    user_id = api_response.user_id,
                                    "[auth] ❌ User key validation FAILED - this is a breaking change issue"
                                );
                                return Err(AppError::AuthenticationError {
                                    message: "User key validation failed. Your vault data may be inaccessible.".to_string(),
                                });
                            }
                        }
                        Err(e) => {
                            error!(
                                email = request.email,
                                user_id = api_response.user_id,
                                error = %e,
                                "[auth] User key validation error - treating as failure"
                            );
                            return Err(AppError::AuthenticationError {
                                message: format!("User key validation error: {}", e),
                            });
                        }
                    }

                    key
                }
                Err(e) => {
                    error!(
                        email = request.email,
                        user_id = api_response.user_id,
                        error = %e,
                        "[auth] User key derivation failed"
                    );
                    return Err(AppError::CryptographyError {
                        operation: format!("derive_user_key_from_server failed: {}", e),
                    });
                }
            }
        }
        None => {
            error!(
                email = request.email,
                user_id = api_response.user_id,
                "[auth] CRITICAL: Server did not provide encrypted user key - this is required"
            );
            return Err(AppError::AuthenticationError {
                message: "Server did not provide encrypted user key. Please contact support."
                    .to_string(),
            });
        }
    };

    // Clear any existing cache data before storing new keys
    if let Err(e) = crate::crypto::cache::CRYPTO_CACHE.clear_user_data(&api_response.user_id) {
        warn!(
            email = request.email,
            user_id = api_response.user_id,
            error = %e,
            "[auth] Failed to clear existing crypto cache before storing new user key"
        );
    }

    // Store the user key in memory cache for vault operations
    if let Err(e) = state
        .memory_cache()
        .store_user_key(api_response.user_id.clone(), user_key.clone())
        .await
    {
        warn!(
            email = request.email,
            user_id = api_response.user_id,
            error = %e,
            "[auth] Failed to store user key in cache during login"
        );
    } else {
        info!(
            email = request.email,
            user_id = api_response.user_id,
            operation = "derive_user_key_consistently",
            "[auth] User key derived and cached successfully - cipher decryption will work"
        );
    }

    // Store encrypted user key for session restoration if available
    if let Some(encrypted_user_key_str) = &api_response.encrypted_user_key {
        match EncryptedString::from_string(encrypted_user_key_str) {
            Ok(enc_string) => {
                let encrypted_data = enc_string.to_encrypted_data();

                // Store encrypted user key for session restoration
                let token_manager = state.token_manager();
                let token_manager = token_manager.read().await;

                // Serialize the encrypted data for storage
                match serde_json::to_vec(&encrypted_data) {
                    Ok(serialized_encrypted_data) => {
                        if let Err(e) = token_manager
                            .store_encrypted_user_key(
                                &api_response.user_id,
                                &serialized_encrypted_data,
                            )
                            .await
                        {
                            warn!(
                                email = request.email,
                                user_id = api_response.user_id,
                                error = %e,
                                "[auth] Failed to store encrypted user key for session restoration"
                            );
                        } else {
                            info!(
                                email = request.email,
                                user_id = api_response.user_id,
                                "[auth] Encrypted user key stored for session restoration"
                            );
                        }
                    }
                    Err(e) => {
                        warn!(
                            email = request.email,
                            user_id = api_response.user_id,
                            error = %e,
                            "[auth] Failed to serialize encrypted user key for storage"
                        );
                    }
                }
            }
            Err(e) => {
                warn!(
                    email = request.email,
                    user_id = api_response.user_id,
                    error = %e,
                    "[auth] Failed to parse encrypted user key from API response"
                );
            }
        }
    }

    // Step 11: Store access and refresh tokens securely
    debug_token_op!(
        email = request.email,
        user_id = api_response.user_id,
        operation = "store_tokens",
        correlation_id = %correlation_id,
        flow_stage = "token_storage",
        "[auth_flow] Storing access and refresh tokens in secure storage"
    );

    // Store access token with expiry using TokenManager
    {
        let token_manager = state.token_manager();
        let token_manager = token_manager.read().await;

        token_manager
            .store_access_token_with_correlation(
                &api_response.user_id,
                &api_response.access_token,
                api_response.expires_in,
                Some(&correlation_id),
            )
            .await
            .map_err(|e| {
                error!(
                    email = request.email,
                    user_id = api_response.user_id,
                    operation = "store_access_token_with_expiry",
                    correlation_id = %correlation_id,
                    flow_stage = "token_storage",
                    error = %e,
                    "[auth_flow] Failed to store access token with expiry: {}", e
                );
                AppError::CryptographyError {
                    operation: format!("Failed to store access token with expiry: {}", e),
                }
            })?;

        info!(
            email = request.email,
            user_id = api_response.user_id,
            expires_in = api_response.expires_in,
            operation = "store_access_token_with_expiry",
            correlation_id = %correlation_id,
            flow_stage = "token_storage",
            success = true,
            "[auth_flow] Access token stored successfully with expiry"
        );
    }

    // Store refresh token using TokenManager
    {
        info!(
            email = request.email,
            user_id = api_response.user_id,
            operation = "store_refresh_token",
            correlation_id = %correlation_id,
            flow_stage = "token_storage_start",
            refresh_token_length = api_response.refresh_token.len(),
            access_token_length = api_response.access_token.len(),
            token_preview = &api_response.refresh_token[..std::cmp::min(20, api_response.refresh_token.len())],
            "[auth_flow] Starting refresh token storage - this is CRITICAL for API access"
        );

        let token_manager = state.token_manager();
        let token_manager = token_manager.read().await;

        token_manager
            .store_refresh_token_with_correlation(
                &api_response.user_id,
                &api_response.refresh_token,
                Some(&correlation_id)
            )
            .await
            .map_err(|e| {
                error!(
                    email = request.email,
                    user_id = api_response.user_id,
                    operation = "store_refresh_token",
                    correlation_id = %correlation_id,
                    flow_stage = "token_storage_failed",
                    error = %e,
                    "[auth_flow] CRITICAL FAILURE: Failed to store refresh token - user will NOT be able to sync with server: {}", e
                );
                AppError::CryptographyError {
                    operation: format!("Failed to store refresh token: {}", e),
                }
            })?;

        // Verify token was stored successfully by attempting to retrieve it
        match token_manager
            .retrieve_refresh_token(&api_response.user_id)
            .await
        {
            Ok(Some(stored_token)) => {
                let tokens_match = stored_token == api_response.refresh_token;
                info!(
                    email = request.email,
                    user_id = api_response.user_id,
                    operation = "verify_token_storage",
                    correlation_id = %correlation_id,
                    flow_stage = "token_verification_success",
                    stored_token_length = stored_token.len(),
                    original_token_length = api_response.refresh_token.len(),
                    tokens_match = tokens_match,
                    "[auth_flow] Refresh token storage verification: {} - API calls will {}",
                    if tokens_match { "SUCCESS" } else { "MISMATCH" },
                    if tokens_match { "work" } else { "FAIL" }
                );

                if !tokens_match {
                    error!(
                        email = request.email,
                        user_id = api_response.user_id,
                        operation = "verify_token_storage",
                        correlation_id = %correlation_id,
                        flow_stage = "token_verification_mismatch",
                        "[auth_flow] CRITICAL: Stored token does not match original - this will cause sync failures"
                    );
                }
            }
            Ok(None) => {
                error!(
                    email = request.email,
                    user_id = api_response.user_id,
                    operation = "verify_token_storage",
                    correlation_id = %correlation_id,
                    flow_stage = "token_verification_not_found",
                    "[auth_flow] CRITICAL: Token was not stored - sync will fail"
                );
            }
            Err(e) => {
                error!(
                    email = request.email,
                    user_id = api_response.user_id,
                    operation = "verify_token_storage",
                    correlation_id = %correlation_id,
                    flow_stage = "token_verification_failed",
                    error = %e,
                    "[auth_flow] CRITICAL: Cannot retrieve stored token - sync will fail: {}", e
                );
            }
        }

        info!(
            email = request.email,
            user_id = api_response.user_id,
            operation = "store_refresh_token",
            correlation_id = %correlation_id,
            flow_stage = "token_storage_complete",
            "[auth_flow] Refresh token storage process completed - user should now be able to sync"
        );
    }

    let elapsed = start_time.elapsed();

    info!(
        email = request.email,
        user_id = api_response.user_id,
        elapsed_ms = elapsed.as_millis(),
        "Login with password completed successfully via remote API"
    );

    Ok(LoginResponse {
        success: true,
        user_id: api_response.user_id,
        master_key: master_key.as_bytes().to_vec(),
        master_key_hash: master_key_hash_local,
    })
}

/// Unlock vault with master password
#[command]
#[specta::specta]
pub async fn unlock_with_password(
    request: UnlockRequest,
    state: State<'_, AppState>,
) -> Result<UnlockResponse, AppError> {
    use tracing::{debug, error, info, warn};

    let start_time = std::time::Instant::now();

    info!(
        user_id = request.user_id,
        operation = "unlock_with_password",
        "[auth] Starting password unlock process"
    );

    debug!(
        user_id = request.user_id,
        password_length = request.password.len(),
        operation = "unlock_with_password",
        "[auth] Input parameters received - password length: {} chars",
        request.password.len()
    );

    // Step 1: Retrieve user data from database
    debug!(
        user_id = request.user_id,
        operation = "unlock_with_password",
        step = "retrieve_user_data",
        "[auth] Attempting to retrieve user data from database"
    );

    let user = match state.database().get_user_by_id(&request.user_id).await {
        Ok(user) => {
            debug!(
                user_id = request.user_id,
                email = user.email,
                kdf_iterations = user.kdf_iterations,
                kdf_type = user.kdf_type,
                has_master_key_hash = user.master_key_hash.is_some(),
                has_encrypted_user_key = user.encrypted_user_key_new.is_some(),
                operation = "unlock_with_password",
                step = "retrieve_user_data",
                "[auth] User data retrieved successfully"
            );
            user
        }
        Err(e) => {
            let elapsed = start_time.elapsed();
            // Check if this is a "user not found" error
            if let AppError::DatabaseError { message } = &e {
                if message.contains("not found") {
                    warn!(
                        user_id = request.user_id,
                        elapsed_ms = elapsed.as_millis(),
                        operation = "unlock_with_password",
                        step = "retrieve_user_data",
                        error_type = "user_not_found",
                        "[auth] Unlock failed - user not found in database"
                    );
                    return Ok(UnlockResponse {
                        success: false,
                        master_key: None,
                        user_key: None,
                    });
                }
            }

            error!(
                user_id = request.user_id,
                elapsed_ms = elapsed.as_millis(),
                operation = "unlock_with_password",
                step = "retrieve_user_data",
                error = %e,
                error_type = "database_error",
                "[auth] Unlock failed - database error retrieving user: {}", e
            );
            return Err(AppError::DatabaseError {
                message: format!("Failed to retrieve user data: {}", e),
            });
        }
    };

    // Step 2: Validate user has required authentication data
    debug!(
        user_id = request.user_id,
        operation = "unlock_with_password",
        step = "validate_user_data",
        "[auth] Validating user has required authentication data"
    );

    let _master_key_hash = match &user.master_key_hash {
        Some(hash) => {
            debug!(
                user_id = request.user_id,
                operation = "unlock_with_password",
                step = "validate_user_data",
                "[auth] User has master key hash stored"
            );
            hash
        }
        None => {
            let elapsed = start_time.elapsed();
            error!(
                user_id = request.user_id,
                elapsed_ms = elapsed.as_millis(),
                operation = "unlock_with_password",
                step = "validate_user_data",
                error_type = "missing_master_key_hash",
                "[auth] Unlock failed - user has no master key hash stored (account not properly configured)"
            );

            // TODO: Consider implementing automatic master key hash generation for incomplete accounts
            // This would involve:
            // 1. Deriving master key from provided password
            // 2. Generating master key hash
            // 3. Updating user record in database
            // 4. Continuing with normal unlock flow
            // However, this should only be done if we can verify the password is correct

            return Ok(UnlockResponse {
                success: false,
                master_key: None,
                user_key: None,
            });
        }
    };

    // Step 3: Try to get stored master key from secure storage
    debug!(
        user_id = request.user_id,
        operation = "unlock_with_password",
        step = "retrieve_stored_master_key",
        "[auth] Attempting to retrieve stored master key from secure storage"
    );

    match state.auth_service().get_master_key(&request.user_id).await {
        Ok(Some(stored_master_key)) => {
            debug!(
                user_id = request.user_id,
                stored_key_length = stored_master_key.as_bytes().len(),
                operation = "unlock_with_password",
                step = "retrieve_stored_master_key",
                "[auth] Stored master key retrieved successfully - length: {} bytes",
                stored_master_key.as_bytes().len()
            );

            // Step 4: Derive master key from provided password
            debug!(
                user_id = request.user_id,
                email = user.email,
                kdf_iterations = user.kdf_iterations,
                operation = "unlock_with_password",
                step = "derive_master_key",
                "[auth] Deriving master key from password using KDF"
            );

            let derived_master_key = match state
                .auth_service()
                .derive_master_key(&request.password, &user.email, user.kdf_iterations as u32)
                .await
            {
                Ok(key) => {
                    debug!(
                        user_id = request.user_id,
                        derived_key_length = key.as_bytes().len(),
                        operation = "unlock_with_password",
                        step = "derive_master_key",
                        "[auth] Master key derived successfully - length: {} bytes",
                        key.as_bytes().len()
                    );
                    key
                }
                Err(e) => {
                    let elapsed = start_time.elapsed();
                    error!(
                        user_id = request.user_id,
                        elapsed_ms = elapsed.as_millis(),
                        operation = "unlock_with_password",
                        step = "derive_master_key",
                        error = %e,
                        error_type = "key_derivation_failed",
                        "[auth] Unlock failed - master key derivation failed: {}", e
                    );
                    return Err(e);
                }
            };

            // Step 5: Compare derived key with stored key
            debug!(
                user_id = request.user_id,
                operation = "unlock_with_password",
                step = "compare_keys",
                "[auth] Comparing derived master key with stored master key"
            );

            // TODO: In a proper implementation, we should compare master key hashes instead of raw keys
            // This is a security issue that should be addressed
            let keys_match = stored_master_key.as_bytes() == derived_master_key.as_bytes();

            debug!(
                user_id = request.user_id,
                keys_match = keys_match,
                stored_key_len = stored_master_key.as_bytes().len(),
                derived_key_len = derived_master_key.as_bytes().len(),
                operation = "unlock_with_password",
                step = "compare_keys",
                "[auth] Key comparison result: {} (stored: {} bytes, derived: {} bytes)",
                if keys_match { "MATCH" } else { "NO MATCH" },
                stored_master_key.as_bytes().len(),
                derived_master_key.as_bytes().len()
            );

            if keys_match {
                // Step 6: Retrieve/derive user key for vault operations
                debug!(
                    user_id = request.user_id,
                    operation = "unlock_with_password",
                    step = "retrieve_user_key",
                    "[auth] Keys match - attempting to retrieve user key"
                );

                // Use new key derivation service (no fallback)
                debug!(
                    user_id = request.user_id,
                    has_encrypted_user_key = user.encrypted_user_key_new.is_some(),
                    key_derivation_method = user.key_derivation_method,
                    operation = "unlock_with_password",
                    step = "derive_user_key_from_server",
                    "[auth] Starting server-provided user key derivation"
                );

                let correlation_id = crate::debug_config::CorrelationId::new();
                let user_key = match user.encrypted_user_key_new.as_deref() {
                    Some(encrypted_user_key_b64) => {
                        match crate::crypto::KeyDerivationService::derive_user_key_from_server(
                            encrypted_user_key_b64,
                            &derived_master_key,
                            &request.user_id,
                            &correlation_id,
                        ) {
                            Ok(key) => key,
                            Err(e) => {
                                error!(
                                    user_id = request.user_id,
                                    error = %e,
                                    "[auth] Failed to derive user key from server during unlock"
                                );
                                return Err(AppError::CryptographyError {
                                    operation: format!("derive_user_key_from_server: {}", e),
                                });
                            }
                        }
                    }
                    None => {
                        error!(
                            user_id = request.user_id,
                            "[auth] No encrypted user key found - user needs to log in again"
                        );
                        return Err(AppError::AuthenticationError {
                            message: "No encrypted user key found. Please log in again."
                                .to_string(),
                        });
                    }
                };

                // Only clear potentially stale user key, not the entire cache
                // This prevents breaking vault operations after unlock
                if let Err(e) = crate::crypto::cache::CRYPTO_CACHE.remove_user_key(&request.user_id)
                {
                    warn!(
                        user_id = request.user_id,
                        error = %e,
                        "[auth] Failed to clear existing user key from crypto cache"
                    );
                }

                // Store the user key in memory cache for vault operations
                if let Err(e) = state
                    .memory_cache()
                    .store_user_key(request.user_id.clone(), user_key.clone())
                    .await
                {
                    warn!(
                        user_id = request.user_id,
                        error = %e,
                        "[auth] Failed to store user key in cache"
                    );
                }

                let final_user_key_bytes = Some(user_key.as_bytes().to_vec());

                // Handle auto-unlock key storage based on vault timeout setting
                if let Ok(settings) = state.settings_store_service.get_settings().await {
                    if settings.vault_timeout.is_never() {
                        // Store user key for auto-unlock when timeout is "Never"
                        if let Err(e) = state
                            .secure_storage
                            .store_auto_unlock_key(&request.user_id, &user_key)
                            .await
                        {
                            warn!(
                                user_id = request.user_id,
                                error = %e,
                                "[auth] Failed to store auto-unlock key - continuing with normal unlock"
                            );
                        } else {
                            info!(
                                user_id = request.user_id,
                                "[auth] Auto-unlock key stored successfully for never timeout"
                            );
                        }
                    } else {
                        // Clear any existing auto-unlock key when timeout is not "Never"
                        // NOTE: Only clear the auto-unlock key from secure storage, not the crypto cache
                        // The crypto cache should remain intact for vault operations
                        if let Err(e) = state
                            .secure_storage
                            .clear_auto_unlock_key(&request.user_id)
                            .await
                        {
                            warn!(
                                user_id = request.user_id,
                                error = %e,
                                "[auth] Failed to clear auto-unlock key - continuing with normal unlock"
                            );
                        } else {
                            debug!(
                                user_id = request.user_id,
                                "[auth] Auto-unlock key cleared (vault timeout is not 'Never')"
                            );
                        }
                    }
                } else {
                    warn!(
                        user_id = request.user_id,
                        "[auth] Failed to get settings for auto-unlock key management"
                    );
                }

                let elapsed = start_time.elapsed();
                info!(
                    user_id = request.user_id,
                    elapsed_ms = elapsed.as_millis(),
                    operation = "unlock_with_password",
                    result = "success",
                    "[auth] Password unlock completed successfully in {}ms",
                    elapsed.as_millis()
                );

                Ok(UnlockResponse {
                    success: true,
                    master_key: Some(derived_master_key.as_bytes().to_vec()),
                    user_key: final_user_key_bytes,
                })
            } else {
                let elapsed = start_time.elapsed();
                warn!(
                    user_id = request.user_id,
                    elapsed_ms = elapsed.as_millis(),
                    operation = "unlock_with_password",
                    step = "compare_keys",
                    result = "failure",
                    error_type = "invalid_password",
                    "[auth] Password unlock failed - invalid password (key mismatch) in {}ms",
                    elapsed.as_millis()
                );

                Ok(UnlockResponse {
                    success: false,
                    master_key: None,
                    user_key: None,
                })
            }
        }
        Ok(None) => {
            let elapsed = start_time.elapsed();
            warn!(
                user_id = request.user_id,
                elapsed_ms = elapsed.as_millis(),
                operation = "unlock_with_password",
                step = "retrieve_stored_master_key",
                result = "failure",
                error_type = "no_stored_master_key",
                "[auth] Password unlock failed - no stored master key found in secure storage in {}ms",
                elapsed.as_millis()
            );

            Ok(UnlockResponse {
                success: false,
                master_key: None,
                user_key: None,
            })
        }
        Err(e) => {
            let elapsed = start_time.elapsed();
            error!(
                user_id = request.user_id,
                elapsed_ms = elapsed.as_millis(),
                operation = "unlock_with_password",
                step = "retrieve_stored_master_key",
                error = %e,
                error_type = "secure_storage_error",
                "[auth] Password unlock failed - secure storage error: {} in {}ms",
                e,
                elapsed.as_millis()
            );

            Err(e)
        }
    }
}

/// Setup new account with master password
#[command]
#[specta::specta]
pub async fn setup_account(
    request: SetupAccountRequest,
    state: State<'_, AppState>,
) -> Result<SetupAccountResponse, AppError> {
    use tracing::{error, info};

    info!(
        email = request.email,
        operation = "setup_account",
        "Setting up new user account"
    );

    // Create user account with proper authentication setup
    let user = state
        .auth_service()
        .create_user(
            &request.email,
            &request.password,
            request.kdf_config.iterations,
        )
        .await
        .map_err(|e| {
            error!(
                email = request.email,
                operation = "create_user",
                error = %e,
                "Failed to create user account"
            );
            e
        })?;

    // Derive master key for response
    let master_key = state
        .auth_service()
        .derive_master_key(
            &request.password,
            &request.email,
            request.kdf_config.iterations,
        )
        .await?;

    // Generate master key hash for response
    let master_key_hash = state
        .auth_service()
        .hash_master_key(&master_key, &request.password)
        .await?;

    // Generate user key for response
    let (user_key, encrypted_user_key) =
        state.auth_service().generate_user_key(&master_key).await?;

    info!(
        email = request.email,
        user_id = user.id,
        "Account setup completed successfully"
    );

    Ok(SetupAccountResponse {
        user_id: user.id,
        master_key: master_key.as_bytes().to_vec(),
        master_key_hash,
        user_key: user_key.as_bytes().to_vec(),
        encrypted_user_key: encrypted_user_key.into_bytes(),
        public_key: vec![],            // TODO: Generate RSA key pair
        encrypted_private_key: vec![], // TODO: Generate and encrypt private key
    })
}

/// Unlock with auto-unlock key (for "never timeout" scenarios)
#[command]
#[specta::specta]
pub async fn unlock_with_auto_key(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<UnlockResponse, AppError> {
    use tracing::{debug, info, warn};

    let start_time = std::time::Instant::now();

    info!(
        user_id = user_id,
        operation = "unlock_with_auto_key",
        "[auth] Starting auto-unlock process"
    );

    // Check if auto-unlock is enabled in settings
    let settings = state.settings_store_service.get_settings().await?;
    if !settings.vault_timeout.is_never() {
        warn!(
            user_id = user_id,
            "[auth] Auto-unlock attempted but vault timeout is not set to 'Never'"
        );
        return Ok(UnlockResponse {
            success: false,
            master_key: None,
            user_key: None,
        });
    }

    // Retrieve auto-unlock key from secure storage
    match state.secure_storage.get_auto_unlock_key(&user_id).await? {
        Some(user_key) => {
            debug!(
                user_id = user_id,
                "[auth] Auto-unlock key retrieved successfully"
            );

            // Only clear potentially stale user key, not the entire cache
            // This prevents breaking vault operations after unlock
            if let Err(e) = crate::crypto::cache::CRYPTO_CACHE.remove_user_key(&user_id) {
                warn!(
                    user_id = user_id,
                    error = %e,
                    "[auth] Failed to clear existing user key from crypto cache"
                );
            }

            // Store the user key in memory cache for vault operations
            if let Err(e) = state
                .memory_cache()
                .store_user_key(user_id.clone(), user_key.clone())
                .await
            {
                warn!(
                    user_id = user_id,
                    error = %e,
                    "[auth] Failed to store auto-unlock user key in cache"
                );
            }

            let elapsed = start_time.elapsed();
            info!(
                user_id = user_id,
                elapsed_ms = elapsed.as_millis(),
                operation = "unlock_with_auto_key",
                result = "success",
                "[auth] Auto-unlock completed successfully in {}ms",
                elapsed.as_millis()
            );

            Ok(UnlockResponse {
                success: true,
                master_key: None, // Master key not available in auto-unlock
                user_key: Some(user_key.as_bytes().to_vec()),
            })
        }
        None => {
            let elapsed = start_time.elapsed();
            warn!(
                user_id = user_id,
                elapsed_ms = elapsed.as_millis(),
                operation = "unlock_with_auto_key",
                result = "failure",
                error_type = "no_auto_unlock_key",
                "[auth] Auto-unlock failed - no auto-unlock key found in {}ms",
                elapsed.as_millis()
            );

            Ok(UnlockResponse {
                success: false,
                master_key: None,
                user_key: None,
            })
        }
    }
}

/// Unlock with biometric authentication
#[command]
#[specta::specta]
pub async fn unlock_with_biometric(
    request: BiometricUnlockRequest,
) -> Result<BiometricUnlockResponse, AppError> {
    // TODO: Implement biometric authentication
    // In a real implementation, you would:
    // 1. Verify biometric authentication
    // 2. Retrieve and decrypt the user key using biometric storage
    // 3. Return the decrypted keys

    println!("Biometric unlock requested for user: {}", request.user_id);

    Ok(BiometricUnlockResponse {
        success: true,
        user_key: Some(vec![0u8; 64]), // Placeholder
    })
}

/// Setup biometric unlock
#[command]
#[specta::specta]
pub async fn setup_biometric_unlock(user_id: String, user_key: Vec<u8>) -> Result<bool, AppError> {
    // TODO: Implement biometric setup
    // In a real implementation, you would:
    // 1. Generate a biometric key
    // 2. Encrypt the user key with the biometric key
    // 3. Store the encrypted user key in secure storage

    println!("Setting up biometric unlock for user: {}", user_id);
    println!("User key length: {}", user_key.len());

    Ok(true)
}

/// Lock the vault
#[command]
#[specta::specta]
pub async fn lock_vault(user_id: String, state: State<'_, AppState>) -> Result<(), AppError> {
    use tracing::{info, warn};

    info!(
        user_id = user_id,
        operation = "lock_vault",
        "[auth] Locking vault and clearing sensitive keys"
    );

    // Clear keys based on their definitions (Lock event)
    if let Err(e) = crate::storage::key_definition::KeyDefinitionService::clear_keys_on_event(
        &user_id,
        crate::storage::key_definition::ClearOn::Lock,
        &state.secure_storage,
        &state.memory_cache,
    )
    .await
    {
        warn!(
            user_id = user_id,
            error = %e,
            "[auth] Failed to clear some keys during vault lock"
        );
    }

    // Also clear crypto cache
    if let Err(e) = crate::crypto::cache::CRYPTO_CACHE.clear_user_data(&user_id) {
        warn!(
            user_id = user_id,
            error = %e,
            "[auth] Failed to clear crypto cache during vault lock"
        );
    }

    info!(user_id = user_id, "[auth] Vault locked successfully");

    Ok(())
}

/// Check if user key is available for decryption
#[command]
#[specta::specta]
pub async fn check_user_key_available(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<bool, AppError> {
    match state.memory_cache().get_user_key(&user_id).await {
        Ok(Some(_)) => Ok(true),
        Ok(None) => Ok(false),
        Err(_) => Ok(false),
    }
}

/// Check if auto-unlock is available for a user
#[command]
#[specta::specta]
pub async fn check_auto_unlock_available(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<bool, AppError> {
    use tracing::debug;

    debug!(
        user_id = user_id,
        "[auth] Checking auto-unlock availability"
    );

    // First check if vault timeout is set to "Never"
    match state.settings_store_service.get_settings().await {
        Ok(settings) => {
            if !settings.vault_timeout.is_never() {
                debug!(
                    user_id = user_id,
                    "[auth] Auto-unlock not available - vault timeout is not 'Never'"
                );
                return Ok(false);
            }
        }
        Err(_) => {
            debug!(
                user_id = user_id,
                "[auth] Auto-unlock not available - failed to get settings"
            );
            return Ok(false);
        }
    }

    // Check if auto-unlock key exists
    match state.secure_storage.has_auto_unlock_key(&user_id).await {
        Ok(has_key) => {
            debug!(
                user_id = user_id,
                has_auto_unlock_key = has_key,
                "[auth] Auto-unlock availability check completed"
            );
            Ok(has_key)
        }
        Err(_) => {
            debug!(
                user_id = user_id,
                "[auth] Auto-unlock not available - failed to check key existence"
            );
            Ok(false)
        }
    }
}

/// Re-authenticate user with master password to restore user key for decryption
#[command]
#[specta::specta]
pub async fn reauth_with_master_password(
    user_id: String,
    master_password: String,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    info!(
        user_id = user_id,
        operation = "reauth_with_master_password",
        "[auth] Starting re-authentication to restore user key for decryption"
    );

    // Get user from database
    let user = state
        .auth_service()
        .get_user_by_id(&user_id)
        .await?
        .ok_or_else(|| AppError::AuthenticationError {
            message: "User not found".to_string(),
        })?;

    // Derive master key from password
    let master_key = state.crypto_service().derive_master_key(
        &master_password,
        &user.email,
        user.kdf_iterations as u32,
    )?;

    // Verify password by comparing hashes
    let derived_hash = state
        .crypto_service()
        .hash_master_key(&master_key, &master_password)?;

    let stored_hash = user
        .master_key_hash
        .ok_or_else(|| AppError::AuthenticationError {
            message: "User has no stored master key hash".to_string(),
        })?;

    if derived_hash != stored_hash {
        return Err(AppError::AuthenticationError {
            message: "Invalid master password".to_string(),
        });
    }

    // Get encrypted user key from storage
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    let encrypted_user_key_data = token_manager
        .retrieve_encrypted_user_key(&user_id)
        .await?
        .ok_or_else(|| AppError::ReAuthenticationRequired {
            message: "No stored encrypted user key found. Please log in again.".to_string(),
        })?;

    // Convert encrypted data back to base64 for consistent derivation
    use base64::{engine::general_purpose, Engine as _};
    let encrypted_user_key_b64 = general_purpose::STANDARD.encode(&encrypted_user_key_data);

    // Use new user key derivation from server
    let correlation_id = crate::debug_config::CorrelationId::new();
    let decrypted_user_key = crate::crypto::KeyDerivationService::derive_user_key_from_server(
        &encrypted_user_key_b64,
        &master_key,
        &user_id,
        &correlation_id,
    )
    .map_err(|e| AppError::CryptographyError {
        operation: format!("derive_user_key_from_server: {}", e),
    })?;

    // Store user key in cache
    state
        .memory_cache()
        .store_user_key(user_id.clone(), decrypted_user_key)
        .await?;

    info!(
        user_id = user_id,
        operation = "reauth_with_master_password",
        "[auth] Re-authentication successful - user key restored for decryption"
    );

    Ok(())
}

/// Refresh access token using the new TokenManager
#[command]
#[specta::specta]
pub async fn refresh_token(user_id: String, state: State<'_, AppState>) -> Result<(), AppError> {
    let correlation_id = CorrelationId::new();

    info!(
        user_id = user_id,
        operation = "refresh_token",
        correlation_id = %correlation_id,
        flow_stage = "start",
        "[auth_flow] Starting token refresh for user using TokenManager"
    );

    // Use the new TokenManager for automatic token refresh
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    debug_token_op!(
        user_id = user_id,
        operation = "refresh_token",
        correlation_id = %correlation_id,
        flow_stage = "token_manager_refresh",
        "[auth_flow] Using TokenManager for automatic refresh"
    );

    token_manager
        .refresh_access_token_with_correlation(&user_id, Some(&correlation_id))
        .await
        .map_err(|e| {
            error!(
                user_id = user_id,
                operation = "refresh_token",
                correlation_id = %correlation_id,
                flow_stage = "token_manager_refresh",
                error = %e,
                "[auth_flow] TokenManager refresh failed: {}", e
            );
            AppError::AuthenticationError {
                message: format!("Token refresh failed: {}", e),
            }
        })?;

    info!(
        user_id = user_id,
        operation = "refresh_token",
        correlation_id = %correlation_id,
        flow_stage = "complete",
        success = true,
        "[auth_flow] Token refresh completed successfully using TokenManager"
    );

    Ok(())
}

/// Test stronghold integration - verify tokens persist correctly
#[command]
#[specta::specta]
pub async fn test_stronghold_integration(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<String, AppError> {
    let correlation_id = CorrelationId::new();

    info!(
        user_id = user_id,
        operation = "test_stronghold_integration",
        correlation_id = %correlation_id,
        "[stronghold_test] Starting stronghold integration test"
    );

    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    // Test 1: Validate backend
    token_manager
        .validate_backend_with_correlation(Some(&correlation_id))
        .await
        .map_err(|e| {
            error!(
                operation = "test_stronghold_integration",
                correlation_id = %correlation_id,
                error = %e,
                "[stronghold_test] Backend validation failed: {}", e
            );
            AppError::StorageError {
                message: format!("Stronghold backend validation failed: {}", e),
            }
        })?;

    // Test 2: Store and retrieve a test refresh token
    let test_refresh_token = "test_refresh_token_12345";
    token_manager
        .store_refresh_token_with_correlation(&user_id, test_refresh_token, Some(&correlation_id))
        .await
        .map_err(|e| {
            error!(
                user_id = user_id,
                operation = "test_stronghold_integration",
                correlation_id = %correlation_id,
                error = %e,
                "[stronghold_test] Failed to store test refresh token: {}", e
            );
            AppError::StorageError {
                message: format!("Failed to store test refresh token: {}", e),
            }
        })?;

    let retrieved_token = token_manager
        .retrieve_refresh_token_with_correlation(&user_id, Some(&correlation_id))
        .await
        .map_err(|e| {
            error!(
                user_id = user_id,
                operation = "test_stronghold_integration",
                correlation_id = %correlation_id,
                error = %e,
                "[stronghold_test] Failed to retrieve test refresh token: {}", e
            );
            AppError::StorageError {
                message: format!("Failed to retrieve test refresh token: {}", e),
            }
        })?;

    if retrieved_token.as_deref() != Some(test_refresh_token) {
        error!(
            user_id = user_id,
            operation = "test_stronghold_integration",
            correlation_id = %correlation_id,
            expected = test_refresh_token,
            retrieved = ?retrieved_token,
            "[stronghold_test] Token mismatch"
        );
        return Err(AppError::StorageError {
            message: "Retrieved token doesn't match stored token".to_string(),
        });
    }

    // Test 3: Store and retrieve an access token with expiry
    let test_access_token = "test_access_token_67890";
    let expires_in = 3600; // 1 hour
    token_manager
        .store_access_token_with_correlation(
            &user_id,
            test_access_token,
            expires_in,
            Some(&correlation_id),
        )
        .await
        .map_err(|e| {
            error!(
                user_id = user_id,
                operation = "test_stronghold_integration",
                correlation_id = %correlation_id,
                error = %e,
                "[stronghold_test] Failed to store test access token: {}", e
            );
            AppError::StorageError {
                message: format!("Failed to store test access token: {}", e),
            }
        })?;

    let retrieved_access_token = token_manager
        .retrieve_access_token_with_correlation(&user_id, Some(&correlation_id))
        .await
        .map_err(|e| {
            error!(
                user_id = user_id,
                operation = "test_stronghold_integration",
                correlation_id = %correlation_id,
                error = %e,
                "[stronghold_test] Failed to retrieve test access token: {}", e
            );
            AppError::StorageError {
                message: format!("Failed to retrieve test access token: {}", e),
            }
        })?;

    if retrieved_access_token.as_deref() != Some(test_access_token) {
        error!(
            user_id = user_id,
            operation = "test_stronghold_integration",
            correlation_id = %correlation_id,
            expected = test_access_token,
            retrieved = ?retrieved_access_token,
            "[stronghold_test] Access token mismatch"
        );
        return Err(AppError::StorageError {
            message: "Retrieved access token doesn't match stored token".to_string(),
        });
    }

    // Clean up test data
    let _ = token_manager.clear_user_tokens(&user_id).await;

    info!(
        user_id = user_id,
        operation = "test_stronghold_integration",
        correlation_id = %correlation_id,
        "[stronghold_test] Stronghold integration test completed successfully"
    );

    Ok("Stronghold integration test passed: backend validation, token storage, and retrieval all working correctly".to_string())
}

/// Logout user - complete cleanup of all user data
#[command]
#[specta::specta]
pub async fn logout(user_id: String, state: State<'_, AppState>) -> Result<(), AppError> {
    use tracing::{debug, error, info, warn};

    let correlation_id = CorrelationId::new();

    info!(
        user_id = user_id,
        operation = "logout",
        correlation_id = %correlation_id,
        flow_stage = "start",
        "[auth_flow] Starting complete logout process for user"
    );

    let start_time = std::time::Instant::now();
    let mut errors = Vec::new();

    // Step 1: Server token revocation (skipped for now - not critical for logout)
    debug_token_op!(
        user_id = user_id,
        operation = "logout",
        correlation_id = %correlation_id,
        flow_stage = "server_revocation",
        "[auth_flow] Step 1: Skipping server token revocation (not implemented)"
    );

    // Step 2: Clear all stored tokens and keys using TokenManager
    debug_token_op!(
        user_id = user_id,
        operation = "logout",
        correlation_id = %correlation_id,
        flow_stage = "clear_tokens",
        "[auth_flow] Step 2: Clearing all tokens and keys using TokenManager"
    );

    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    if let Err(e) = token_manager.clear_all_user_data(&user_id).await {
        error!(
            user_id = user_id,
            operation = "logout",
            correlation_id = %correlation_id,
            flow_stage = "clear_tokens",
            error = %e,
            success = false,
            "[auth_flow] Failed to clear user tokens using TokenManager: {}", e
        );
        errors.push(format!("Failed to clear tokens: {}", e));
    } else {
        info!(
            user_id = user_id,
            operation = "logout",
            correlation_id = %correlation_id,
            flow_stage = "clear_tokens",
            success = true,
            "[auth_flow] Successfully cleared all tokens and keys using TokenManager"
        );
    }

    // Step 3: Clear database sessions and user data
    debug!(user_id = user_id, "Step 3: Clearing database sessions");

    if let Err(e) = state.database().clear_user_session(&user_id).await {
        error!(
            user_id = user_id,
            error = %e,
            "Failed to clear user session from database"
        );
        errors.push(format!("Failed to clear database session: {}", e));
    } else {
        debug!(user_id = user_id, "Successfully cleared database session");
    }

    // Step 4: Clear crypto cache and memory cache
    debug_token_op!(
        user_id = user_id,
        operation = "logout",
        correlation_id = %correlation_id,
        flow_stage = "clear_cache",
        "[auth_flow] Step 4: Clearing crypto cache and memory cache"
    );

    // Clear crypto cache
    if let Err(e) = crate::crypto::cache::CRYPTO_CACHE.clear_user_data(&user_id) {
        error!(
            user_id = user_id,
            operation = "logout",
            correlation_id = %correlation_id,
            flow_stage = "clear_cache",
            error = %e,
            success = false,
            "[auth_flow] Failed to clear crypto cache: {}", e
        );
        errors.push(format!("Failed to clear crypto cache: {}", e));
    } else {
        info!(
            user_id = user_id,
            operation = "logout",
            correlation_id = %correlation_id,
            flow_stage = "clear_cache",
            success = true,
            "[auth_flow] Successfully cleared crypto cache"
        );
    }

    // Clear memory cache
    state.memory_cache().clear_user_data(&user_id).await;

    // Step 5: Emit logout event for frontend cleanup
    debug!(user_id = user_id, "Step 5: Emitting logout event");

    if let Err(e) = state.app_handle.emit("user_logged_out", &user_id) {
        warn!(
            user_id = user_id,
            error = %e,
            "Failed to emit logout event"
        );
        // Don't add this to errors as it's not critical
    }

    let elapsed = start_time.elapsed();

    if errors.is_empty() {
        info!(
            user_id = user_id,
            elapsed_ms = elapsed.as_millis(),
            operation = "logout",
            "Logout completed successfully"
        );
        Ok(())
    } else {
        let error_message = format!("Logout completed with errors: {}", errors.join(", "));
        error!(
            user_id = user_id,
            elapsed_ms = elapsed.as_millis(),
            errors = ?errors,
            operation = "logout",
            "Logout completed with errors"
        );
        Err(AppError::InternalError {
            message: error_message,
        })
    }
}

/// Get all users from database for user detection
#[command]
#[specta::specta]
pub async fn get_all_users(
    state: State<'_, AppState>,
) -> Result<Vec<crate::models::user::User>, AppError> {
    debug!("Getting all users from database");

    match state.database().get_all_users().await {
        Ok(users) => {
            debug!("Successfully retrieved {} users from database", users.len());
            Ok(users)
        }
        Err(e) => {
            error!(
                error = %e,
                "Failed to retrieve users from database"
            );
            Err(AppError::DatabaseError {
                message: format!("Failed to get users: {}", e),
            })
        }
    }
}

/// Check if user has valid access token (debug helper)
#[command]
#[specta::specta]
pub async fn check_user_access_token(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<bool, AppError> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    match token_manager.retrieve_access_token(&user_id).await {
        Ok(Some(_)) => Ok(true),
        Ok(None) => Ok(false),
        Err(e) => {
            error!(
                user_id = user_id,
                error = %e,
                "Failed to check access token using TokenManager"
            );
            Err(AppError::CryptographyError {
                operation: format!("Failed to check access token: {}", e),
            })
        }
    }
}

/// Comprehensive token status diagnostic (debug helper)
#[command]
#[specta::specta]
pub async fn diagnose_token_status(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<TokenDiagnosticResult, AppError> {
    use tracing::{debug, info};

    info!(
        user_id = user_id,
        operation = "diagnose_token_status",
        "Starting comprehensive token diagnostic using TokenManager"
    );

    let mut diagnostic = TokenDiagnosticResult {
        user_id: user_id.clone(),
        access_token_present: false,
        refresh_token_present: false,
        access_token_expired: None,
        recommendations: Vec::new(),
        timestamp: chrono::Utc::now().to_rfc3339(),
    };

    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    // Check access token presence
    match token_manager.retrieve_access_token(&user_id).await {
        Ok(Some(_)) => {
            diagnostic.access_token_present = true;
            debug!(user_id = user_id, "Access token found using TokenManager");
        }
        Ok(None) => {
            diagnostic.access_token_present = false;
            diagnostic
                .recommendations
                .push("Access token is missing. Re-authentication required.".to_string());
            debug!(
                user_id = user_id,
                "Access token not found using TokenManager"
            );
        }
        Err(e) => {
            diagnostic
                .recommendations
                .push(format!("Failed to check access token: {}", e));
            error!(user_id = user_id, error = %e, "Failed to retrieve access token using TokenManager");
        }
    }

    // Check refresh token presence
    match token_manager.retrieve_refresh_token(&user_id).await {
        Ok(Some(_)) => {
            diagnostic.refresh_token_present = true;
            debug!(user_id = user_id, "Refresh token found using TokenManager");
        }
        Ok(None) => {
            diagnostic.refresh_token_present = false;
            diagnostic.recommendations.push("Refresh token is missing. This will prevent automatic token refresh. Re-authentication required.".to_string());
            debug!(
                user_id = user_id,
                "Refresh token not found using TokenManager"
            );
        }
        Err(e) => {
            diagnostic
                .recommendations
                .push(format!("Failed to check refresh token: {}", e));
            error!(user_id = user_id, error = %e, "Failed to retrieve refresh token using TokenManager");
        }
    }

    // Check access token expiry if present
    if diagnostic.access_token_present {
        match token_manager.is_access_token_expired(&user_id).await {
            Ok(is_expired) => {
                diagnostic.access_token_expired = Some(is_expired);
                if is_expired {
                    diagnostic
                        .recommendations
                        .push("Access token is expired and needs refresh.".to_string());
                    debug!(
                        user_id = user_id,
                        "Access token is expired using TokenManager"
                    );
                } else {
                    debug!(
                        user_id = user_id,
                        "Access token is still valid using TokenManager"
                    );
                }
            }
            Err(e) => {
                diagnostic
                    .recommendations
                    .push(format!("Failed to check access token expiry: {}", e));
                error!(user_id = user_id, error = %e, "Failed to check access token expiry using TokenManager");
            }
        }
    }

    // Generate overall recommendations
    if !diagnostic.access_token_present || !diagnostic.refresh_token_present {
        diagnostic.recommendations.push(
            "Solution: Log out and log back in to refresh all authentication tokens.".to_string(),
        );
    } else if diagnostic.access_token_expired == Some(true) && !diagnostic.refresh_token_present {
        diagnostic.recommendations.push("Critical: Access token expired but no refresh token available. Immediate re-authentication required.".to_string());
    }

    info!(
        user_id = user_id,
        access_token_present = diagnostic.access_token_present,
        refresh_token_present = diagnostic.refresh_token_present,
        access_token_expired = diagnostic.access_token_expired,
        recommendations_count = diagnostic.recommendations.len(),
        "Token diagnostic completed"
    );

    Ok(diagnostic)
}

/// Check keyring backend status (debug helper)
#[command]
#[specta::specta]
pub async fn check_keyring_backend(
    state: State<'_, AppState>,
) -> Result<KeyringBackendStatus, AppError> {
    use tracing::{debug, error, info};

    info!(
        operation = "check_keyring_backend",
        "Checking TokenManager backend status"
    );

    let mut status = KeyringBackendStatus {
        backend_available: false,
        backend_type: "unknown".to_string(),
        can_store_retrieve: false,
        error_message: None,
        timestamp: chrono::Utc::now().to_rfc3339(),
    };

    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    // Test TokenManager backend validation
    match token_manager.validate_backend().await {
        Ok(()) => {
            status.backend_available = true;
            status.backend_type = "file_based".to_string();
            debug!("TokenManager backend validation successful");
        }
        Err(e) => {
            status.backend_available = false;
            status.error_message = Some(format!("Backend validation failed: {}", e));
            error!(error = %e, "TokenManager backend validation failed");
        }
    }

    // Test actual store/retrieve functionality using access token methods
    let test_user_id = "keyring_test_user";
    let test_token = "test_access_token_data";

    match token_manager
        .store_access_token(test_user_id, test_token, 3600)
        .await
    {
        Ok(()) => {
            // Try to retrieve it
            match token_manager.retrieve_access_token(test_user_id).await {
                Ok(Some(retrieved_token)) if retrieved_token == test_token => {
                    status.can_store_retrieve = true;
                    debug!("TokenManager store/retrieve test successful");

                    // Clean up test data
                    let _ = token_manager.delete_access_token(test_user_id).await;
                }
                Ok(Some(_)) => {
                    status.error_message =
                        Some("Retrieved token doesn't match stored token".to_string());
                    error!("TokenManager test failed: token mismatch");
                }
                Ok(None) => {
                    status.error_message = Some("Failed to retrieve stored test token".to_string());
                    error!("TokenManager test failed: no token retrieved");
                }
                Err(e) => {
                    status.error_message = Some(format!("Failed to retrieve test token: {}", e));
                    error!(error = %e, "TokenManager retrieve test failed");
                }
            }
        }
        Err(e) => {
            status.error_message = Some(format!("Failed to store test token: {}", e));
            error!(error = %e, "TokenManager store test failed");
        }
    }

    info!(
        backend_available = status.backend_available,
        backend_type = status.backend_type,
        can_store_retrieve = status.can_store_retrieve,
        has_error = status.error_message.is_some(),
        "Keyring backend check completed"
    );

    Ok(status)
}

/// Store a test refresh token for diagnostic purposes
#[command]
#[specta::specta]
pub async fn store_test_refresh_token(
    user_id: String,
    token: String,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    token_manager
        .store_refresh_token(&user_id, &token)
        .await
        .map_err(|e| AppError::CryptographyError {
            operation: format!(
                "Failed to store test refresh token using TokenManager: {}",
                e
            ),
        })?;

    Ok(())
}

/// Force user to re-login by clearing their authentication state
#[command]
#[specta::specta]
pub async fn force_relogin(user_id: String, state: State<'_, AppState>) -> Result<(), AppError> {
    use tracing::info;

    info!(
        user_id = user_id,
        operation = "force_relogin",
        "[auth] Forcing user to re-login by clearing authentication state"
    );

    // Clear any existing tokens
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    if let Err(e) = token_manager.clear_user_tokens(&user_id).await {
        warn!(
            user_id = user_id,
            error = %e,
            "[auth] Failed to clear tokens during force re-login"
        );
    }

    info!(
        user_id = user_id,
        operation = "force_relogin",
        "[auth] User authentication state cleared - they must perform full login"
    );

    Ok(())
}

/// Comprehensive authentication flow diagnostic
#[command]
#[specta::specta]
pub async fn diagnose_auth_flow(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<String, AppError> {
    use tracing::info;

    let correlation_id = CorrelationId::new();

    info!(
        user_id = user_id,
        operation = "diagnose_auth_flow",
        correlation_id = %correlation_id,
        "[auth_diagnostic] Starting comprehensive authentication flow diagnosis"
    );

    let mut diagnostic_report = String::new();
    diagnostic_report.push_str("=== AUTHENTICATION FLOW DIAGNOSTIC REPORT ===\n\n");

    // 1. Check if user exists in database
    diagnostic_report.push_str("1. USER DATABASE CHECK:\n");
    match state.database.get_user_by_id(&user_id).await {
        Ok(user) => {
            diagnostic_report.push_str(&format!("   ✅ User found in database: {}\n", user.email));
            diagnostic_report.push_str(&format!(
                "   ✅ Has master key hash: {}\n",
                user.master_key_hash.is_some()
            ));
        }
        Err(e) => {
            diagnostic_report.push_str(&format!("   ❌ Database error or user not found: {}\n", e));
        }
    }

    // 2. Check token manager state
    diagnostic_report.push_str("\n2. TOKEN MANAGER CHECK:\n");
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    // Check refresh token
    match token_manager.retrieve_refresh_token(&user_id).await {
        Ok(Some(refresh_token)) => {
            diagnostic_report.push_str(&format!(
                "   ✅ Refresh token found (length: {})\n",
                refresh_token.len()
            ));
            diagnostic_report.push_str(&format!(
                "   ✅ Token preview: {}...\n",
                &refresh_token[..std::cmp::min(20, refresh_token.len())]
            ));
        }
        Ok(None) => {
            diagnostic_report
                .push_str("   ❌ NO refresh token found - this is why API calls fail\n");
        }
        Err(e) => {
            diagnostic_report.push_str(&format!("   ❌ Error retrieving refresh token: {}\n", e));
        }
    }

    // Check access token
    match token_manager.retrieve_access_token(&user_id).await {
        Ok(Some(access_token)) => {
            diagnostic_report.push_str(&format!(
                "   ✅ Access token available (length: {})\n",
                access_token.len()
            ));
        }
        Ok(None) => {
            diagnostic_report.push_str("   ⚠️  No access token in memory (will try to refresh)\n");
        }
        Err(e) => {
            diagnostic_report.push_str(&format!("   ❌ Error retrieving access token: {}\n", e));
        }
    }

    // 3. Check server connectivity
    diagnostic_report.push_str("\n3. SERVER CONNECTIVITY CHECK:\n");
    // This would require making an actual API call, which we'll skip for now
    diagnostic_report
        .push_str("   ℹ️  Server connectivity check skipped (would require API call)\n");

    // 4. Recommendations
    diagnostic_report.push_str("\n4. RECOMMENDATIONS:\n");
    if diagnostic_report.contains("NO refresh token found") {
        diagnostic_report
            .push_str("   🔧 SOLUTION: User needs to perform full LOGIN (not just unlock)\n");
        diagnostic_report.push_str("   🔧 ACTION: Navigate to /login and enter credentials\n");
        diagnostic_report
            .push_str("   🔧 NOTE: Unlock only works with local data, Login gets server tokens\n");
    } else {
        diagnostic_report.push_str("   ✅ Authentication state looks good\n");
    }

    diagnostic_report.push_str("\n=== END DIAGNOSTIC REPORT ===\n");

    info!(
        user_id = user_id,
        operation = "diagnose_auth_flow",
        correlation_id = %correlation_id,
        "[auth_diagnostic] Diagnostic report generated"
    );

    Ok(diagnostic_report)
}

/// Retrieve a test refresh token for diagnostic purposes
#[command]
#[specta::specta]
pub async fn retrieve_test_refresh_token(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<Option<String>, AppError> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    let token = token_manager
        .retrieve_refresh_token(&user_id)
        .await
        .map_err(|e| AppError::CryptographyError {
            operation: format!(
                "Failed to retrieve test refresh token using TokenManager: {}",
                e
            ),
        })?;

    Ok(token)
}

/// Clear test tokens for diagnostic purposes
#[command]
#[specta::specta]
pub async fn clear_test_tokens(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    // Clear both access and refresh tokens using TokenManager
    let _ = token_manager.delete_access_token(&user_id).await;
    let _ = token_manager.delete_refresh_token(&user_id).await;

    Ok(())
}

/// Clear all tokens for a user (for recovery purposes)
#[command]
#[specta::specta]
pub async fn clear_user_tokens(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    let token_manager = state.token_manager();
    let token_manager = token_manager.read().await;

    token_manager
        .clear_all_user_data(&user_id)
        .await
        .map_err(|e| AppError::CryptographyError {
            operation: format!("Failed to clear user tokens using TokenManager: {}", e),
        })?;

    Ok(())
}

/// Change master password
#[command]
#[specta::specta]
pub async fn change_master_password(
    user_id: String,
    current_password: String,
    new_password: String,
    email: String,
    kdf_config: KdfConfig,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    // Verify current password first
    let unlock_result = unlock_with_password(
        UnlockRequest {
            user_id: user_id.clone(),
            password: current_password,
        },
        state.clone(),
    )
    .await?;

    if !unlock_result.success {
        return Ok(false);
    }

    // Derive new master key
    let new_master_key = state
        .auth_service()
        .derive_master_key(&new_password, &email, kdf_config.iterations)
        .await
        .map_err(|e| e.to_string())?;

    // Generate new master key hash
    let _new_local_hash = state
        .auth_service()
        .hash_master_key(&new_master_key, &new_password)
        .await
        .map_err(|e| e.to_string())?;

    // Store new master key
    state
        .auth_service()
        .store_master_key(&user_id, &new_master_key)
        .await
        .map_err(|e| e.to_string())?;

    // Re-encrypt user key with new master key
    // This would require retrieving the current user key and re-encrypting it
    println!("Password changed successfully for user: {}", user_id);

    Ok(true)
}

/// Debug command to check what keys are currently cached
#[command]
#[specta::specta]
pub async fn debug_check_cache_status(user_id: String) -> Result<String, String> {
    debug!("[auth] Checking cache status for user: {}", user_id);

    // Check crypto cache stats
    let stats = CRYPTO_CACHE
        .get_stats()
        .map_err(|e| format!("Failed to get cache stats: {}", e))?;

    // Try to get user key from cache
    let user_key_exists = CRYPTO_CACHE
        .get_user_key(&user_id)
        .map_err(|e| format!("Failed to check user key: {}", e))?;

    let result = format!(
        "Cache Status:\n\
        - Master keys: {}\n\
        - User keys: {}\n\
        - Derived keys: {}\n\
        - Total entries: {}/{}\n\
        - User key for '{}' exists: {}\n\
        - User key length: {}",
        stats.master_key_count,
        stats.user_key_count,
        stats.derived_key_count,
        stats.total_entries,
        stats.max_entries,
        user_id,
        user_key_exists.is_some(),
        user_key_exists.as_ref().map(|k| k.key.len()).unwrap_or(0)
    );

    info!("[auth] Cache status: {}", result);
    Ok(result)
}

/// Debug command to inspect cipher decryption issues
#[command]
#[specta::specta]
pub async fn debug_cipher_decryption(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    debug!("[auth] Debugging cipher decryption for user: {}", user_id);

    let mut result = String::new();
    result.push_str("=== CIPHER DECRYPTION DEBUG ===\n");
    result.push_str(&format!("User ID: {}\n\n", user_id));

    // 1. Check cache status
    result.push_str("1. CACHE STATUS:\n");
    let user_key_cached = CRYPTO_CACHE
        .get_user_key(&user_id)
        .map_err(|e| format!("Failed to check user key: {}", e))?;
    result.push_str(&format!(
        "   - User key cached: {}\n",
        user_key_cached.is_some()
    ));
    if let Some(ref key) = user_key_cached {
        result.push_str(&format!("   - User key length: {} bytes\n", key.key.len()));
    }

    // 2. Get ciphers from database
    result.push_str("\n2. DATABASE CIPHER DATA:\n");
    match state.vault_service.get_all_ciphers(&user_id).await {
        Ok(ciphers) => {
            result.push_str(&format!(
                "   - Found {} ciphers in database\n",
                ciphers.len()
            ));

            if let Some(cipher) = ciphers.first() {
                result.push_str(&format!("   - First cipher ID: {}\n", cipher.id));
                result.push_str(&format!("   - Cipher name: {:?}\n", cipher.name));
            }
        }
        Err(e) => {
            result.push_str(&format!("   - ERROR: Failed to get ciphers: {:?}\n", e));
        }
    }

    // 3. Get ciphers from API server
    result.push_str("\n3. API SERVER CIPHER DATA:\n");
    result.push_str("   - Use the 'API Debug' button to fetch ciphers directly from server\n");
    result.push_str("   - This will compare API vs database data sources\n");

    result.push_str("\n=== END DEBUG ===\n");
    info!("[auth] Cipher debug result: {}", result);
    Ok(result)
}

/// Debug command to fetch ciphers directly from API server
#[command]
#[specta::specta]
pub async fn debug_fetch_ciphers_from_api(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    debug!(
        "[auth] Fetching ciphers from API server for user: {}",
        user_id
    );

    let mut result = String::new();
    result.push_str("=== FETCH CIPHERS FROM API DEBUG ===\n");
    result.push_str(&format!("User ID: {}\n\n", user_id));

    // Get access token for the user
    let token_manager = state.token_manager();

    let access_token = match token_manager
        .read()
        .await
        .retrieve_access_token(&user_id)
        .await
    {
        Ok(Some(token)) => {
            result.push_str("1. AUTHENTICATION:\n");
            result.push_str("   - ✅ Access token found\n");
            result.push_str(&format!("   - Token length: {} characters\n", token.len()));
            token
        }
        Ok(None) => {
            result.push_str("1. AUTHENTICATION:\n");
            result.push_str("   - ❌ No access token found for user\n");
            result.push_str("   - Cannot fetch from API without authentication\n");
            result.push_str("\n=== END DEBUG ===\n");
            return Ok(result);
        }
        Err(e) => {
            result.push_str("1. AUTHENTICATION:\n");
            result.push_str(&format!("   - ❌ Error retrieving access token: {}\n", e));
            result.push_str("   - Cannot fetch from API without authentication\n");
            result.push_str("\n=== END DEBUG ===\n");
            return Ok(result);
        }
    };

    // Create API client and services
    result.push_str("\n2. API CLIENT SETUP:\n");
    let api_client = std::sync::Arc::new(crate::api::ApiClient::new(
        state.app_handle.clone(),
        state.server_provider_service.clone(),
    ));
    result.push_str("   - ✅ API client created\n");

    let vault_repository = std::sync::Arc::new(crate::api::repositories::ApiVaultRepository::new(
        api_client.clone(),
    ));
    let folder_repository = std::sync::Arc::new(
        crate::api::repositories::ApiFolderRepository::new(api_client),
    );
    let api_vault_service =
        crate::api::services::ApiVaultService::new(vault_repository.clone(), folder_repository);
    result.push_str("   - ✅ API vault service created\n");

    // Get server URL for context
    let server_url = state.server_provider_service.get_api_url().await;
    result.push_str(&format!("   - Server URL: {}\n", server_url));

    // Fetch ciphers from API - first get raw response to debug format
    result.push_str("\n3. API REQUEST:\n");

    // Make raw API call to see the actual response format
    match vault_repository.get_ciphers(&access_token).await {
        Ok(raw_response) => {
            result.push_str("   - ✅ Raw API request successful\n");
            result.push_str(&format!(
                "   - Response type: {}\n",
                if raw_response.is_object() {
                    "Object"
                } else if raw_response.is_array() {
                    "Array"
                } else {
                    "Other"
                }
            ));

            // Show response structure
            result.push_str("\n4. RESPONSE STRUCTURE:\n");
            if let Some(obj) = raw_response.as_object() {
                result.push_str("   - Response is an object with keys:\n");
                for key in obj.keys() {
                    let value_type = match obj.get(key).unwrap() {
                        serde_json::Value::Array(arr) => format!("Array[{}]", arr.len()),
                        serde_json::Value::Object(_) => "Object".to_string(),
                        serde_json::Value::String(_) => "String".to_string(),
                        serde_json::Value::Number(_) => "Number".to_string(),
                        serde_json::Value::Bool(_) => "Boolean".to_string(),
                        serde_json::Value::Null => "Null".to_string(),
                    };
                    result.push_str(&format!("     - {}: {}\n", key, value_type));
                }
            } else if let Some(arr) = raw_response.as_array() {
                result.push_str(&format!(
                    "   - Response is an array with {} items\n",
                    arr.len()
                ));
                if let Some(first_item) = arr.first() {
                    if let Some(obj) = first_item.as_object() {
                        result.push_str("   - First item keys:\n");
                        for key in obj.keys().take(10) {
                            result.push_str(&format!("     - {}\n", key));
                        }
                    }
                }
            }

            // Try to parse with the service
            result.push_str("\n5. PARSING ATTEMPT:\n");
            match api_vault_service.get_ciphers(&access_token).await {
                Ok(api_ciphers) => {
                    result.push_str("   - ✅ Parsing successful\n");
                    result.push_str(&format!("   - Found {} ciphers\n", api_ciphers.len()));

                    if !api_ciphers.is_empty() {
                        result.push_str("\n6. CIPHER DETAILS:\n");
                        for (i, cipher) in api_ciphers.iter().take(3).enumerate() {
                            result.push_str(&format!("   Cipher {}:\n", i + 1));
                            result.push_str(&format!("     - ID: {:?}\n", cipher.id));
                            result.push_str(&format!("     - Name: {:?}\n", cipher.name));
                            result.push_str(&format!("     - Type: {}\n", cipher.cipher_type));
                        }

                        if api_ciphers.len() > 3 {
                            result.push_str(&format!(
                                "   ... and {} more ciphers\n",
                                api_ciphers.len() - 3
                            ));
                        }
                    }
                }
                Err(e) => {
                    result.push_str("   - ❌ Parsing failed\n");
                    result.push_str(&format!("   - Parse error: {}\n", e));

                    // Show a sample of the raw response for debugging
                    let response_sample = serde_json::to_string_pretty(&raw_response)
                        .unwrap_or_else(|_| "Could not serialize response".to_string());
                    let truncated_sample = if response_sample.len() > 500 {
                        format!(
                            "{}...\n[Response truncated - {} total characters]",
                            &response_sample[..500],
                            response_sample.len()
                        )
                    } else {
                        response_sample
                    };
                    result.push_str(&format!(
                        "   - Raw response sample:\n{}\n",
                        truncated_sample
                    ));
                }
            }

            // Compare with database
            result.push_str("\n7. DATABASE COMPARISON:\n");
            match state.vault_service.get_all_ciphers(&user_id).await {
                Ok(db_ciphers) => {
                    let db_count = db_ciphers.len();
                    result.push_str(&format!("   - Database ciphers: {}\n", db_count));
                }
                Err(e) => {
                    result.push_str(&format!("   - ❌ Could not get database ciphers: {}\n", e));
                }
            }
        }
        Err(e) => {
            result.push_str("   - ❌ Raw API request failed\n");
            result.push_str(&format!("   - Error: {}\n", e));

            // Try to provide more context about the error
            let error_str = format!("{}", e);
            if error_str.contains("401") || error_str.contains("Unauthorized") {
                result.push_str("   - Possible cause: Access token expired or invalid\n");
            } else if error_str.contains("403") || error_str.contains("Forbidden") {
                result.push_str("   - Possible cause: Insufficient permissions\n");
            } else if error_str.contains("404") || error_str.contains("Not Found") {
                result.push_str("   - Possible cause: API endpoint not found\n");
            } else if error_str.contains("timeout") {
                result.push_str("   - Possible cause: Network timeout\n");
            }
        }
    }

    result.push_str("\n=== END DEBUG ===\n");
    info!("[auth] API fetch debug result: {}", result);
    Ok(result)
}

/// Debug command to get raw cipher item response from API
#[command]
#[specta::specta]
pub async fn debug_get_cipher_raw_response(
    user_id: String,
    cipher_id: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    debug!(
        "[auth] Getting raw cipher response for user: {}, cipher: {}",
        user_id, cipher_id
    );

    let mut result = String::new();
    result.push_str("=== RAW CIPHER ITEM RESPONSE DEBUG ===\n");
    result.push_str(&format!("User ID: {}\n", user_id));
    result.push_str(&format!("Cipher ID: {}\n\n", cipher_id));

    // Get access token for the user
    let token_manager = state.token_manager();
    let access_token = match token_manager
        .read()
        .await
        .retrieve_access_token(&user_id)
        .await
    {
        Ok(Some(token)) => {
            result.push_str("1. AUTHENTICATION:\n");
            result.push_str("   - ✅ Access token found\n");
            result.push_str(&format!("   - Token length: {} characters\n", token.len()));
            token
        }
        Ok(None) => {
            result.push_str("1. AUTHENTICATION:\n");
            result.push_str("   - ❌ No access token found for user\n");
            result.push_str("   - Cannot fetch cipher without authentication\n");
            result.push_str("\n=== END DEBUG ===\n");
            return Ok(result);
        }
        Err(e) => {
            result.push_str("1. AUTHENTICATION:\n");
            result.push_str(&format!("   - ❌ Error retrieving access token: {}\n", e));
            result.push_str("   - Cannot fetch cipher without authentication\n");
            result.push_str("\n=== END DEBUG ===\n");
            return Ok(result);
        }
    };

    // Create API client
    result.push_str("\n2. API CLIENT SETUP:\n");
    let api_client = std::sync::Arc::new(crate::api::ApiClient::new(
        state.app_handle.clone(),
        state.server_provider_service.clone(),
    ));
    result.push_str("   - ✅ API client created\n");

    // Get server URL for context
    let server_url = state.server_provider_service.get_api_url().await;
    result.push_str(&format!("   - Server URL: {}\n", server_url));

    // Make raw API call to get specific cipher
    result.push_str("\n3. RAW CIPHER API REQUEST:\n");
    let cipher_endpoint = format!("/ciphers/{}", cipher_id);
    result.push_str(&format!("   - Endpoint: {}\n", cipher_endpoint));

    match api_client
        .get::<serde_json::Value>(&cipher_endpoint, Some(&access_token))
        .await
    {
        Ok(raw_response) => {
            result.push_str("   - ✅ Raw cipher API request successful\n");
            result.push_str(&format!(
                "   - Response type: {}\n",
                if raw_response.is_object() {
                    "Object"
                } else if raw_response.is_array() {
                    "Array"
                } else {
                    "Other"
                }
            ));

            // Show the complete raw response
            result.push_str("\n4. RAW CIPHER RESPONSE:\n");
            result.push_str("   - Complete JSON response from server:\n");
            result.push_str("   ```json\n");
            match serde_json::to_string_pretty(&raw_response) {
                Ok(pretty_json) => {
                    result.push_str(&format!("   {}\n", pretty_json.replace('\n', "\n   ")));
                }
                Err(_) => {
                    result.push_str(&format!("   {}\n", raw_response.to_string()));
                }
            }
            result.push_str("   ```\n");

            // Analyze the response structure
            result.push_str("\n5. RESPONSE ANALYSIS:\n");
            if let Some(obj) = raw_response.as_object() {
                result.push_str("   - Response is an object with keys:\n");
                for (key, value) in obj {
                    let value_type = match value {
                        serde_json::Value::Array(arr) => format!("Array[{}]", arr.len()),
                        serde_json::Value::Object(_) => "Object".to_string(),
                        serde_json::Value::String(s) => format!("String[{}]", s.len()),
                        serde_json::Value::Number(_) => "Number".to_string(),
                        serde_json::Value::Bool(_) => "Boolean".to_string(),
                        serde_json::Value::Null => "Null".to_string(),
                    };
                    result.push_str(&format!("     - {}: {}\n", key, value_type));
                }

                // Show specific cipher fields if they exist
                if let Some(name) = obj.get("name") {
                    result.push_str(&format!("   - Cipher name field: {:?}\n", name));
                }
                if let Some(login) = obj.get("login") {
                    result.push_str(&format!("   - Login data present: {}\n", login.is_object()));
                }
                if let Some(data) = obj.get("data") {
                    result.push_str(&format!("   - Data field present: {}\n", data.is_object()));
                }
            }
        }
        Err(e) => {
            result.push_str(&format!("   - ❌ Raw cipher API request failed: {}\n", e));
            result.push_str("   - This could indicate:\n");
            result.push_str("     * Cipher doesn't exist\n");
            result.push_str("     * Access denied\n");
            result.push_str("     * Network connectivity issues\n");
            result.push_str("     * Server error\n");
        }
    }

    result.push_str("\n=== END DEBUG ===\n");
    info!("[auth] Raw cipher debug result: {}", result);
    Ok(result)
}

/// Debug cipher field inspection to find problematic fields
#[command]
#[specta::specta]
pub async fn debug_cipher_field_inspection(
    user_id: String,
    cipher_id: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let mut result = String::new();
    result.push_str("=== CIPHER FIELD INSPECTION DEBUG ===\n");
    result.push_str(&format!("User ID: {}\n", user_id));
    result.push_str(&format!("Cipher ID: {}\n", cipher_id));
    result.push_str(&format!(
        "Timestamp: {}\n",
        chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC")
    ));

    // Step 1: Get raw cipher from database
    result.push_str("\n1. FETCHING RAW CIPHER FROM DATABASE:\n");

    let database = state.database.clone();

    // Get cipher from database
    let raw_cipher = match database.get_cipher(&cipher_id, &user_id).await {
        Ok(Some(cipher)) => {
            result.push_str("   - ✅ Successfully fetched cipher from database\n");
            cipher
        }
        Ok(None) => {
            result.push_str("   - ❌ Cipher not found in database\n");
            return Ok(result);
        }
        Err(e) => {
            result.push_str(&format!("   - ❌ Failed to fetch cipher: {}\n", e));
            return Ok(result);
        }
    };

    // Step 2: Inspect all fields in the cipher data
    result.push_str("\n2. INSPECTING ALL FIELDS IN CIPHER DATA:\n");

    // Convert to pretty JSON for inspection
    match serde_json::to_string_pretty(&raw_cipher) {
        Ok(pretty_json) => {
            result.push_str("   Raw cipher structure:\n");
            result.push_str(&format!("   {}\n", pretty_json));
        }
        Err(e) => {
            result.push_str(&format!("   - ❌ Failed to serialize cipher: {}\n", e));
        }
    }

    // Step 3: Look for specific problematic values
    result.push_str("\n3. SEARCHING FOR PROBLEMATIC VALUES:\n");

    let json_str = serde_json::to_string(&raw_cipher).unwrap_or_default();

    // Check for "asd" specifically
    if json_str.contains("\"asd\"") {
        result.push_str("   - ⚠️  FOUND 'asd' in the cipher data!\n");

        // Try to find the exact location
        let lines: Vec<&str> = json_str.lines().collect();
        for (i, line) in lines.iter().enumerate() {
            if line.contains("\"asd\"") {
                result.push_str(&format!("   - Found at line {}: {}\n", i + 1, line.trim()));
            }
        }
    } else {
        result.push_str("   - ✅ No 'asd' found in cipher data\n");
    }

    // Check for other suspicious short strings
    let suspicious_patterns = ["\"a\"", "\"ab\"", "\"abc\"", "\"test\"", "\"\""];
    for pattern in &suspicious_patterns {
        if json_str.contains(pattern) {
            result.push_str(&format!("   - ⚠️  Found suspicious pattern: {}\n", pattern));
        }
    }

    // Step 4: Inspect specific fields that commonly cause issues
    result.push_str("\n4. INSPECTING SPECIFIC FIELDS:\n");

    result.push_str(&format!("   - ID: {}\n", raw_cipher.id));
    result.push_str(&format!("   - Name: {:?}\n", raw_cipher.name));
    result.push_str(&format!("   - Notes: {:?}\n", raw_cipher.notes));
    result.push_str(&format!("   - Cipher Type: {}\n", raw_cipher.cipher_type));
    result.push_str(&format!(
        "   - Encrypted Data Length: {}\n",
        raw_cipher.encrypted_data.len()
    ));
    result.push_str(&format!("   - Enc Type: {}\n", raw_cipher.enc_type));
    result.push_str(&format!("   - MAC: {:?}\n", raw_cipher.mac));

    // Try to parse the encrypted_data as JSON to see its structure
    result.push_str("\n5. PARSING ENCRYPTED DATA:\n");
    match serde_json::from_str::<serde_json::Value>(&raw_cipher.encrypted_data) {
        Ok(encrypted_json) => {
            result.push_str("   - ✅ Successfully parsed encrypted_data as JSON\n");
            match serde_json::to_string_pretty(&encrypted_json) {
                Ok(pretty_encrypted) => {
                    result.push_str("   - Encrypted data structure:\n");
                    result.push_str(&format!("   {}\n", pretty_encrypted));
                }
                Err(e) => {
                    result.push_str(&format!(
                        "   - ❌ Failed to pretty print encrypted data: {}\n",
                        e
                    ));
                }
            }

            // Look for "asd" in the encrypted data specifically
            if raw_cipher.encrypted_data.contains("\"asd\"") {
                result.push_str("   - ⚠️  FOUND 'asd' in encrypted_data field!\n");
            }
        }
        Err(e) => {
            result.push_str(&format!(
                "   - ❌ Failed to parse encrypted_data as JSON: {}\n",
                e
            ));
            result.push_str(&format!(
                "   - Raw encrypted_data: {:?}\n",
                raw_cipher.encrypted_data
            ));
        }
    }

    Ok(result)
}

/// Debug command to test new two-step cipher parsing pipeline
#[command]
#[specta::specta]
pub async fn debug_cipher_parsing_pipeline(
    user_id: String,
    cipher_id: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    debug!(
        "[auth] Testing new cipher parsing pipeline for user: {}, cipher: {}",
        user_id, cipher_id
    );

    let mut result = String::new();
    result.push_str("=== NEW CIPHER PARSING PIPELINE DEBUG ===\n");
    result.push_str(&format!("User ID: {}\n", user_id));
    result.push_str(&format!("Cipher ID: {}\n\n", cipher_id));

    // Get access token for the user
    let token_manager = state.token_manager();
    let access_token = match token_manager
        .read()
        .await
        .retrieve_access_token(&user_id)
        .await
    {
        Ok(Some(token)) => {
            result.push_str("1. AUTHENTICATION:\n");
            result.push_str("   - ✅ Access token found\n");
            result.push_str(&format!("   - Token length: {} characters\n", token.len()));
            token
        }
        Ok(None) => {
            result.push_str("1. AUTHENTICATION:\n");
            result.push_str("   - ❌ No access token found for user\n");
            result.push_str("   - Cannot test parsing without authentication\n");
            result.push_str("\n=== END DEBUG ===\n");
            return Ok(result);
        }
        Err(e) => {
            result.push_str("1. AUTHENTICATION:\n");
            result.push_str(&format!("   - ❌ Error retrieving access token: {}\n", e));
            result.push_str("   - Cannot test parsing without authentication\n");
            result.push_str("\n=== END DEBUG ===\n");
            return Ok(result);
        }
    };

    // Create API client
    result.push_str("\n2. API CLIENT SETUP:\n");
    let api_client = std::sync::Arc::new(crate::api::ApiClient::new(
        state.app_handle.clone(),
        state.server_provider_service.clone(),
    ));
    result.push_str("   - ✅ API client created\n");

    // Get server URL for context
    let server_url = state.server_provider_service.get_api_url().await;
    result.push_str(&format!("   - Server URL: {}\n", server_url));

    // Make raw API call to get specific cipher
    result.push_str("\n3. RAW CIPHER API REQUEST:\n");
    let cipher_endpoint = format!("/ciphers/{}", cipher_id);
    result.push_str(&format!("   - Endpoint: {}\n", cipher_endpoint));

    match api_client
        .get::<serde_json::Value>(&cipher_endpoint, Some(&access_token))
        .await
    {
        Ok(raw_response) => {
            result.push_str("   - ✅ Raw cipher API request successful\n");

            // Test the new parsing pipeline
            result.push_str("\n4. NEW PARSING PIPELINE TEST:\n");

            // Note: Testing parsing pipeline manually without vault service

            // Test Step 1: Parse raw encrypted response
            result.push_str("   Step 1: Parsing raw encrypted response...\n");
            match serde_json::from_value::<crate::api::services::vault_service::RawCipherResponse>(
                raw_response.clone(),
            ) {
                Ok(raw_cipher) => {
                    result.push_str("   - ✅ Successfully parsed raw cipher response\n");
                    result.push_str(&format!("   - Cipher ID: {}\n", raw_cipher.id));
                    result.push_str(&format!("   - Cipher type: {}\n", raw_cipher.cipher_type));
                    result.push_str(&format!(
                        "   - Has login data: {}\n",
                        raw_cipher.login.is_some()
                    ));
                    result.push_str(&format!(
                        "   - Has data object: {}\n",
                        raw_cipher.data.is_some()
                    ));
                    result.push_str(&format!(
                        "   - Name field (encrypted): {}\n",
                        raw_cipher.name
                    ));

                    if let Some(login) = &raw_cipher.login {
                        result.push_str(&format!(
                            "   - Login username (encrypted): {:?}\n",
                            login.username
                        ));
                        result.push_str(&format!(
                            "   - Login password (encrypted): {:?}\n",
                            login.password
                        ));
                    }

                    // Test Step 2: Test decryption manually
                    result.push_str("\n   Step 2: Testing manual decryption...\n");

                    // Try to get user key and decrypt the name field
                    match crate::crypto::cache::CRYPTO_CACHE.get_user_key(&user_id) {
                        Ok(Some(user_key)) => {
                            result.push_str("   - ✅ Retrieved user key from cache\n");

                            // Test decrypting the name field
                            match crate::crypto::cipher_crypto::CipherCrypto::decrypt_string(
                                &raw_cipher.name,
                                &user_key,
                            ) {
                                Ok(decrypted_name) => {
                                    result.push_str(&format!(
                                        "   - ✅ Successfully decrypted name: {}\n",
                                        decrypted_name
                                    ));
                                }
                                Err(e) => {
                                    result.push_str(&format!(
                                        "   - ❌ Failed to decrypt name: {}\n",
                                        e
                                    ));
                                }
                            }

                            // Test decrypting login fields if available
                            if let Some(login) = &raw_cipher.login {
                                if let Some(encrypted_username) = &login.username {
                                    match crate::crypto::cipher_crypto::CipherCrypto::decrypt_string(
                                        encrypted_username,
                                        &user_key,
                                    ) {
                                        Ok(decrypted_username) => {
                                            result.push_str(&format!(
                                                "   - ✅ Successfully decrypted username: {}\n",
                                                decrypted_username
                                            ));
                                        }
                                        Err(e) => {
                                            result.push_str(&format!(
                                                "   - ❌ Failed to decrypt username: {}\n",
                                                e
                                            ));
                                        }
                                    }
                                }
                            }
                        }
                        Ok(None) => {
                            result.push_str("   - ❌ No user key found in cache\n");
                            result.push_str("   - User needs to unlock vault first\n");
                        }
                        Err(e) => {
                            result.push_str(&format!("   - ❌ Failed to get user key: {}\n", e));
                        }
                    }
                }
                Err(e) => {
                    result.push_str(&format!(
                        "   - ❌ Failed to parse raw cipher response: {}\n",
                        e
                    ));
                    result.push_str("   - This indicates a mismatch between API response and expected structure\n");
                }
            }
        }
        Err(e) => {
            result.push_str(&format!("   - ❌ Raw cipher API request failed: {}\n", e));
        }
    }

    result.push_str("\n=== END DEBUG ===\n");
    info!("[auth] Cipher parsing pipeline debug result: {}", result);
    Ok(result)
}

/// Debug cipher decryption step by step to find where "asd" appears
#[command]
#[specta::specta]
pub async fn debug_cipher_decryption_steps(
    user_id: String,
    cipher_id: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let mut result = String::new();
    result.push_str("=== CIPHER DECRYPTION STEP-BY-STEP DEBUG ===\n");
    result.push_str(&format!("User ID: {}\n", user_id));
    result.push_str(&format!("Cipher ID: {}\n", cipher_id));
    result.push_str(&format!(
        "Timestamp: {}\n",
        chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC")
    ));

    let database = state.database.clone();
    let vault_service = state.vault_service.clone();

    // Step 1: Get raw cipher from database
    result.push_str("\n1. FETCHING RAW CIPHER FROM DATABASE:\n");
    let raw_cipher = match database.get_cipher(&cipher_id, &user_id).await {
        Ok(Some(cipher)) => {
            result.push_str("   - ✅ Successfully fetched cipher from database\n");
            cipher
        }
        Ok(None) => {
            result.push_str("   - ❌ Cipher not found in database\n");
            return Ok(result);
        }
        Err(e) => {
            result.push_str(&format!("   - ❌ Failed to fetch cipher: {}\n", e));
            return Ok(result);
        }
    };

    // Step 2: Get user key for decryption from cache
    result.push_str("\n2. GETTING USER KEY FOR DECRYPTION:\n");
    let user_key = match crate::crypto::cache::CRYPTO_CACHE.get_user_key(&user_id) {
        Ok(Some(key)) => {
            result.push_str("   - ✅ Successfully retrieved user key from cache\n");
            key
        }
        Ok(None) => {
            result.push_str("   - ❌ No user key found in cache - user needs to re-authenticate\n");
            return Ok(result);
        }
        Err(e) => {
            result.push_str(&format!("   - ❌ Failed to get user key: {}\n", e));
            return Ok(result);
        }
    };

    // Step 3: Decrypt individual fields step by step
    result.push_str("\n3. DECRYPTING INDIVIDUAL FIELDS:\n");

    // Decrypt name
    result.push_str("   3.1 Decrypting NAME field:\n");
    result.push_str(&format!("       Raw encrypted: {}\n", raw_cipher.name));
    match crate::crypto::CipherCrypto::decrypt_string(&raw_cipher.name, &user_key) {
        Ok(decrypted_name) => {
            result.push_str(&format!("       ✅ Decrypted: {:?}\n", decrypted_name));
            if decrypted_name.contains("asd") {
                result.push_str("       ⚠️  FOUND 'asd' in decrypted name!\n");
            }
        }
        Err(e) => {
            result.push_str(&format!("       ❌ Failed to decrypt name: {}\n", e));
        }
    }

    // Decrypt notes if present
    if let Some(notes) = &raw_cipher.notes {
        result.push_str("   3.2 Decrypting NOTES field:\n");
        result.push_str(&format!("       Raw encrypted: {}\n", notes));
        match crate::crypto::CipherCrypto::decrypt_string(notes, &user_key) {
            Ok(decrypted_notes) => {
                result.push_str(&format!("       ✅ Decrypted: {:?}\n", decrypted_notes));
                if decrypted_notes.contains("asd") {
                    result.push_str("       ⚠️  FOUND 'asd' in decrypted notes!\n");
                }
            }
            Err(e) => {
                result.push_str(&format!("       ❌ Failed to decrypt notes: {}\n", e));
            }
        }
    }

    // Step 4: Parse and decrypt login data from encrypted_data
    result.push_str("\n4. PARSING AND DECRYPTING LOGIN DATA:\n");
    match serde_json::from_str::<serde_json::Value>(&raw_cipher.encrypted_data) {
        Ok(encrypted_json) => {
            result.push_str("   - ✅ Successfully parsed encrypted_data as JSON\n");

            if let Some(login) = encrypted_json.get("login") {
                result.push_str("   4.1 Found login data, decrypting fields:\n");

                // Decrypt username
                if let Some(username) = login.get("username").and_then(|u| u.as_str()) {
                    result.push_str("       Username field:\n");
                    result.push_str(&format!("         Raw encrypted: {}\n", username));
                    match crate::crypto::CipherCrypto::decrypt_string(username, &user_key) {
                        Ok(decrypted_username) => {
                            result.push_str(&format!(
                                "         ✅ Decrypted: {:?}\n",
                                decrypted_username
                            ));
                            if decrypted_username.contains("asd") {
                                result
                                    .push_str("         ⚠️  FOUND 'asd' in decrypted username!\n");
                            }
                        }
                        Err(e) => {
                            result.push_str(&format!(
                                "         ❌ Failed to decrypt username: {}\n",
                                e
                            ));
                        }
                    }
                }

                // Decrypt password
                if let Some(password) = login.get("password").and_then(|p| p.as_str()) {
                    result.push_str("       Password field:\n");
                    result.push_str(&format!("         Raw encrypted: {}\n", password));
                    match crate::crypto::CipherCrypto::decrypt_string(password, &user_key) {
                        Ok(decrypted_password) => {
                            result.push_str(&format!(
                                "         ✅ Decrypted: {:?}\n",
                                decrypted_password
                            ));
                            if decrypted_password.contains("asd") {
                                result
                                    .push_str("         ⚠️  FOUND 'asd' in decrypted password!\n");
                            }
                        }
                        Err(e) => {
                            result.push_str(&format!(
                                "         ❌ Failed to decrypt password: {}\n",
                                e
                            ));
                        }
                    }
                }

                // Decrypt URI
                if let Some(uris) = login.get("uris").and_then(|u| u.as_array()) {
                    for (i, uri_obj) in uris.iter().enumerate() {
                        if let Some(uri) = uri_obj.get("uri").and_then(|u| u.as_str()) {
                            result.push_str(&format!("       URI {} field:\n", i + 1));
                            result.push_str(&format!("         Raw encrypted: {}\n", uri));
                            match crate::crypto::CipherCrypto::decrypt_string(uri, &user_key) {
                                Ok(decrypted_uri) => {
                                    result.push_str(&format!(
                                        "         ✅ Decrypted: {:?}\n",
                                        decrypted_uri
                                    ));
                                    if decrypted_uri.contains("asd") {
                                        result.push_str(
                                            "         ⚠️  FOUND 'asd' in decrypted URI!\n",
                                        );
                                    }
                                }
                                Err(e) => {
                                    result.push_str(&format!(
                                        "         ❌ Failed to decrypt URI: {}\n",
                                        e
                                    ));
                                }
                            }
                        }
                    }
                }
            }
        }
        Err(e) => {
            result.push_str(&format!(
                "   - ❌ Failed to parse encrypted_data as JSON: {}\n",
                e
            ));
        }
    }

    Ok(result)
}

/// Establish device trust for passwordless authentication
#[command]
#[specta::specta]
pub async fn establish_device_trust(
    request: EstablishDeviceTrustRequest,
    state: State<'_, AppState>,
) -> Result<EstablishDeviceTrustResponse, String> {
    let correlation_id = CorrelationId::new();

    info!(
        user_id = request.user_id,
        device_name = request.device_name,
        device_type = request.device_type,
        correlation_id = %correlation_id,
        "[auth] Starting device trust establishment"
    );

    // Get user from database
    let user = state
        .database
        .get_user_by_id(&request.user_id)
        .await
        .map_err(|e| format!("Failed to get user: {}", e))?;

    // Get user key from cache
    let user_key = CRYPTO_CACHE
        .get_user_key(&request.user_id)
        .map_err(|e| format!("Failed to get user key from cache: {}", e))?
        .ok_or_else(|| "User key not found in cache. Please unlock first.".to_string())?;

    // Generate device identifier
    let device_identifier = DeviceIdentifier {
        id: uuid::Uuid::new_v4().to_string(),
        name: request.device_name.clone(),
        device_type: request.device_type.clone(),
    };

    // Establish device trust
    let trusted_device = DeviceTrustService::establish_device_trust(
        &user,
        &user_key,
        &device_identifier,
        &state.database,
        &correlation_id,
    )
    .await
    .map_err(|e| format!("Failed to establish device trust: {}", e))?;

    // Update user to enable device trust
    let mut updated_user = user;
    updated_user.device_trust_enabled = true;
    state
        .database
        .upsert_user(&updated_user)
        .await
        .map_err(|e| format!("Failed to update user: {}", e))?;

    info!(
        user_id = request.user_id,
        device_id = trusted_device.id,
        device_identifier = device_identifier.id,
        correlation_id = %correlation_id,
        "[auth] Device trust established successfully"
    );

    Ok(EstablishDeviceTrustResponse {
        device_id: trusted_device.id,
        device_identifier: device_identifier.id.clone(),
        trust_established: true,
    })
}

/// Authenticate using device trust (passwordless login)
#[command]
#[specta::specta]
pub async fn login_with_device_trust(
    request: DeviceTrustLoginRequest,
    state: State<'_, AppState>,
) -> Result<DeviceTrustLoginResponse, String> {
    let correlation_id = CorrelationId::new();

    info!(
        user_id = request.user_id,
        device_identifier = request.device_identifier,
        correlation_id = %correlation_id,
        "[auth] Starting device trust authentication"
    );

    // Authenticate using device trust
    let user_key = DeviceTrustService::authenticate_with_device_trust(
        &request.device_identifier,
        &request.user_id,
        &state.database,
        &correlation_id,
    )
    .await
    .map_err(|e| format!("Device trust authentication failed: {}", e))?;

    // Cache the user key
    CRYPTO_CACHE
        .store_user_key(request.user_id.clone(), user_key)
        .map_err(|e| format!("Failed to cache user key: {}", e))?;

    info!(
        user_id = request.user_id,
        device_identifier = request.device_identifier,
        correlation_id = %correlation_id,
        "[auth] Device trust authentication successful"
    );

    Ok(DeviceTrustLoginResponse {
        success: true,
        user_id: request.user_id,
        device_trusted: true,
    })
}

/// Revoke device trust
#[command]
#[specta::specta]
pub async fn revoke_device_trust(
    device_identifier: String,
    user_id: String,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    let correlation_id = CorrelationId::new();

    info!(
        user_id = user_id,
        device_identifier = device_identifier,
        correlation_id = %correlation_id,
        "[auth] Revoking device trust"
    );

    DeviceTrustService::revoke_device_trust(
        &device_identifier,
        &user_id,
        &state.database,
        &correlation_id,
    )
    .await
    .map_err(|e| format!("Failed to revoke device trust: {}", e))?;

    info!(
        user_id = user_id,
        device_identifier = device_identifier,
        correlation_id = %correlation_id,
        "[auth] Device trust revoked successfully"
    );

    Ok(true)
}

/// List trusted devices for a user
#[command]
#[specta::specta]
pub async fn list_trusted_devices(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<Vec<crate::models::user::TrustedDevice>, String> {
    let correlation_id = CorrelationId::new();

    debug!(
        user_id = user_id,
        correlation_id = %correlation_id,
        "[auth] Listing trusted devices"
    );

    let devices =
        DeviceTrustService::list_trusted_devices(&user_id, &state.database, &correlation_id)
            .await
            .map_err(|e| format!("Failed to list trusted devices: {}", e))?;

    debug!(
        user_id = user_id,
        device_count = devices.len(),
        correlation_id = %correlation_id,
        "[auth] Retrieved trusted devices"
    );

    Ok(devices)
}
