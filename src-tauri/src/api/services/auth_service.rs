use crate::api::repositories::traits::AuthRepository;
use crate::error::{AppError, AppResult};
use crate::logging::{log_auth_event_detailed, log_token_event};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;
use tracing::{debug, error, info};

#[derive(Debug, Serialize, Deserialize)]
pub struct PreloginRequest {
    pub email: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PreloginResponse {
    pub kdf: u32,
    #[serde(rename = "kdfIterations")]
    pub kdf_iterations: u32,
    #[serde(rename = "kdfMemory")]
    pub kdf_memory: Option<u32>,
    #[serde(rename = "kdfParallelism")]
    pub kdf_parallelism: Option<u32>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password_hash: String,
    pub two_factor_token: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: u64,
    pub user_id: String,
    pub encrypted_user_key: Option<String>, // The "Key" field from API response
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UserProfile {
    pub id: String,
    pub email: String,
    pub name: Option<String>,
    pub premium: bool,
    pub organizations: Vec<Organization>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Organization {
    pub id: String,
    pub name: String,
    pub status: u8,
    pub r#type: u8,
}

/// API authentication service for handling complex authentication business logic
pub struct ApiAuthService {
    auth_repository: Arc<dyn AuthRepository + Send + Sync>,
}

impl ApiAuthService {
    pub fn new(auth_repository: Arc<dyn AuthRepository + Send + Sync>) -> Self {
        Self { auth_repository }
    }

    /// Get KDF settings for user before login (prelogin)
    pub async fn prelogin(&self, email: &str) -> AppResult<PreloginResponse> {
        debug!(email = email, "Starting prelogin request");

        let response = self.auth_repository.prelogin(email).await.map_err(|e| {
            error!(email = email, error = %e, "Prelogin request failed");
            log_auth_event_detailed(
                "prelogin",
                None,
                Some(email),
                false,
                None, // No timing information
                None,
                Some(&e.to_string()),
            );
            e
        })?;

        debug!(email = email, "Prelogin response received, parsing");
        let result = self.parse_prelogin_response(response).await;

        match &result {
            Ok(prelogin_resp) => {
                info!(
                    email = email,
                    kdf = prelogin_resp.kdf,
                    kdf_iterations = prelogin_resp.kdf_iterations,
                    "Prelogin successful"
                );
                log_auth_event_detailed(
                    "prelogin",
                    None,
                    Some(email),
                    true,
                    None, // No timing information
                    None,
                    None,
                );
            }
            Err(e) => {
                error!(email = email, error = %e, "Prelogin parsing failed");
                log_auth_event_detailed(
                    "prelogin",
                    None,
                    Some(email),
                    false,
                    None, // No timing information
                    None,
                    Some(&e.to_string()),
                );
            }
        }

        result
    }

    /// Authenticate user with email and password
    pub async fn authenticate(&self, request: LoginRequest) -> AppResult<LoginResponse> {
        debug!(
            email = request.email,
            has_2fa = request.two_factor_token.is_some(),
            "Starting authentication request"
        );

        let response = self
            .auth_repository
            .login(
                &request.email,
                &request.password_hash,
                request.two_factor_token.as_deref(),
            )
            .await
            .map_err(|e| {
                error!(email = request.email, error = %e, "Authentication request failed");
                let _elapsed = 0;
                log_auth_event_detailed(
                    "login",
                    None,
                    Some(&request.email),
                    false,
                    None,
                    None,
                    Some(&e.to_string()),
                );
                e
            })?;

        debug!(
            email = request.email,
            "Authentication response received, parsing"
        );

        // Parse the response and extract token information
        let result = self.parse_login_response(response).await;

        match &result {
            Ok(login_resp) => {
                info!(
                    email = request.email,
                    user_id = login_resp.user_id,
                    token_type = login_resp.token_type,
                    expires_in = login_resp.expires_in,
                    "Authentication successful"
                );
                let _elapsed = 0;
                log_auth_event_detailed(
                    "login",
                    Some(&login_resp.user_id),
                    Some(&request.email),
                    true,
                    None,
                    None,
                    None,
                );
                log_token_event(
                    "issued",
                    &login_resp.token_type,
                    Some(&login_resp.user_id),
                    Some(login_resp.expires_in),
                    true,
                );
            }
            Err(e) => {
                error!(email = request.email, error = %e, "Authentication parsing failed");
                let _elapsed = 0;
                log_auth_event_detailed(
                    "login",
                    None,
                    Some(&request.email),
                    false,
                    None,
                    None,
                    Some(&e.to_string()),
                );
            }
        }

        result
    }

    /// Refresh access token using refresh token
    pub async fn refresh_token(&self, refresh_token: &str) -> AppResult<LoginResponse> {
        debug!("Starting token refresh request");

        let response = self
            .auth_repository
            .refresh_access_token(refresh_token)
            .await
            .map_err(|e| {
                error!(error = %e, "Token refresh request failed");
                let _elapsed = 0;
                log_auth_event_detailed(
                    "token_refresh",
                    None,
                    None,
                    false,
                    None,
                    None,
                    Some(&e.to_string()),
                );
                e
            })?;

        debug!("Token refresh response received, parsing");
        let result = self.parse_login_response(response).await;

        match &result {
            Ok(login_resp) => {
                info!(
                    user_id = login_resp.user_id,
                    token_type = login_resp.token_type,
                    expires_in = login_resp.expires_in,
                    "Token refresh successful"
                );
                let _elapsed = 0;
                log_auth_event_detailed(
                    "token_refresh",
                    Some(&login_resp.user_id),
                    None,
                    true,
                    None,
                    None,
                    None,
                );
                log_token_event(
                    "refreshed",
                    &login_resp.token_type,
                    Some(&login_resp.user_id),
                    Some(login_resp.expires_in),
                    true,
                );
            }
            Err(e) => {
                error!(error = %e, "Token refresh parsing failed");
                let _elapsed = 0;
                log_auth_event_detailed(
                    "token_refresh",
                    None,
                    None,
                    false,
                    None,
                    None,
                    Some(&e.to_string()),
                );
            }
        }

        result
    }

    /// Get user profile information
    pub async fn get_user_profile(&self, access_token: &str) -> AppResult<UserProfile> {
        debug!("Starting get user profile request");

        let response = self
            .auth_repository
            .get_profile(access_token)
            .await
            .map_err(|e| {
                error!(error = %e, "Get user profile request failed");
                e
            })?;

        debug!("User profile response received, parsing");
        let result = self.parse_user_profile(response).await;

        match &result {
            Ok(profile) => {
                info!(
                    user_id = profile.id,
                    email = profile.email,
                    premium = profile.premium,
                    organizations_count = profile.organizations.len(),
                    "User profile retrieved successfully"
                );
            }
            Err(e) => {
                error!(error = %e, "User profile parsing failed");
            }
        }

        result
    }

    /// Logout user by revoking tokens
    pub async fn logout(&self, access_token: &str) -> AppResult<()> {
        debug!("Starting logout request");

        let result = self.auth_repository.logout(access_token).await;

        match &result {
            Ok(_) => {
                info!("Logout successful");
                let _elapsed = 0;
                log_auth_event_detailed("logout", None, None, true, None, None, None);
            }
            Err(e) => {
                error!(error = %e, "Logout failed");
                let _elapsed = 0;
                log_auth_event_detailed(
                    "logout",
                    None,
                    None,
                    false,
                    None,
                    None,
                    Some(&e.to_string()),
                );
            }
        }

        result
    }

    /// Validate access token by attempting to get user profile
    pub async fn validate_token(&self, access_token: &str) -> AppResult<bool> {
        match self.auth_repository.get_profile(access_token).await {
            Ok(_) => Ok(true),
            Err(AppError::NetworkError { status: 401, .. }) => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// Parse login response from API
    async fn parse_login_response(&self, response: Value) -> AppResult<LoginResponse> {
        // Log the complete response for debugging
        debug!(
            response_body = %response,
            "Complete authentication response received"
        );

        let access_token = response
            .get("access_token")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AppError::AuthenticationError {
                message: "Missing access_token in response".to_string(),
            })?;

        let refresh_token = response
            .get("refresh_token")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AppError::AuthenticationError {
                message: "Missing refresh_token in response".to_string(),
            })?;

        let token_type = response
            .get("token_type")
            .and_then(|v| v.as_str())
            .unwrap_or("Bearer");

        let expires_in = response
            .get("expires_in")
            .and_then(|v| v.as_u64())
            .unwrap_or(3600);

        // Log available fields in response for debugging
        debug!(
            available_fields = ?response.as_object().map(|obj| obj.keys().collect::<Vec<_>>()),
            "Available fields in authentication response"
        );

        // Extract user ID from the response - try multiple possible field names
        let user_id = response
            .get("user_id")
            .or_else(|| response.get("UserId"))
            .or_else(|| response.get("sub"))
            .and_then(|v| v.as_str())
            .map(|s| {
                debug!(user_id = s, "Found user_id in response");
                s.to_string()
            })
            .unwrap_or_else(|| {
                // If no user_id field found, try to decode from JWT token
                debug!("No user_id field found in response, attempting to decode from JWT token");
                self.extract_user_id_from_jwt(access_token)
                    .unwrap_or_else(|e| {
                        error!(
                            error = %e,
                            "Failed to extract user_id from JWT token, using 'unknown'"
                        );
                        "unknown".to_string()
                    })
            });

        // Extract encrypted user key from the "Key" field
        let encrypted_user_key = response
            .get("Key")
            .and_then(|v| v.as_str())
            .map(|s| {
                debug!(key_length = s.len(), "Found encrypted user key in response");
                s.to_string()
            });

        debug!(
            user_id = user_id,
            token_type = token_type,
            expires_in = expires_in,
            has_encrypted_user_key = encrypted_user_key.is_some(),
            "Parsed authentication response successfully"
        );

        Ok(LoginResponse {
            access_token: access_token.to_string(),
            refresh_token: refresh_token.to_string(),
            token_type: token_type.to_string(),
            expires_in,
            user_id,
            encrypted_user_key,
        })
    }

    /// Parse user profile response from API
    async fn parse_user_profile(&self, response: Value) -> AppResult<UserProfile> {
        let id = response.get("Id").and_then(|v| v.as_str()).ok_or_else(|| {
            AppError::AuthenticationError {
                message: "Missing user ID in profile response".to_string(),
            }
        })?;

        let email = response
            .get("Email")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AppError::AuthenticationError {
                message: "Missing email in profile response".to_string(),
            })?;

        let name = response
            .get("Name")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        let premium = response
            .get("Premium")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        let organizations = response
            .get("Organizations")
            .and_then(|v| v.as_array())
            .map(|orgs| {
                orgs.iter()
                    .filter_map(|org| {
                        let id = org.get("Id")?.as_str()?.to_string();
                        let name = org.get("Name")?.as_str()?.to_string();
                        let status = org.get("Status")?.as_u64()? as u8;
                        let r#type = org.get("Type")?.as_u64()? as u8;

                        Some(Organization {
                            id,
                            name,
                            status,
                            r#type,
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();

        Ok(UserProfile {
            id: id.to_string(),
            email: email.to_string(),
            name,
            premium,
            organizations,
        })
    }

    /// Parse prelogin response from API
    async fn parse_prelogin_response(&self, response: Value) -> AppResult<PreloginResponse> {
        let kdf = response
            .get("kdf")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AppError::AuthenticationError {
                message: "Missing kdf in prelogin response".to_string(),
            })? as u32;

        let kdf_iterations = response
            .get("kdfIterations")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AppError::AuthenticationError {
                message: "Missing kdfIterations in prelogin response".to_string(),
            })? as u32;

        let kdf_memory = response
            .get("kdfMemory")
            .and_then(|v| v.as_u64())
            .map(|v| v as u32);

        let kdf_parallelism = response
            .get("kdfParallelism")
            .and_then(|v| v.as_u64())
            .map(|v| v as u32);

        Ok(PreloginResponse {
            kdf,
            kdf_iterations,
            kdf_memory,
            kdf_parallelism,
        })
    }

    /// Extract user ID from JWT access token
    fn extract_user_id_from_jwt(&self, access_token: &str) -> AppResult<String> {
        use base64::{engine::general_purpose, Engine as _};

        debug!(
            token_prefix = &access_token[..std::cmp::min(20, access_token.len())],
            "Attempting to decode JWT token for user_id"
        );

        // Split JWT token into parts
        let parts: Vec<&str> = access_token.split('.').collect();
        if parts.len() != 3 {
            return Err(AppError::AuthenticationError {
                message: "Invalid JWT token format".to_string(),
            });
        }

        // Decode the payload (second part)
        let payload_b64 = parts[1];

        // Add padding if needed for base64 decoding
        let padded_payload = match payload_b64.len() % 4 {
            0 => payload_b64.to_string(),
            n => format!("{}{}", payload_b64, "=".repeat(4 - n)),
        };

        let payload_bytes = general_purpose::STANDARD
            .decode(&padded_payload)
            .map_err(|e| {
                error!(
                    error = %e,
                    payload_b64 = payload_b64,
                    "Failed to decode JWT payload from base64"
                );
                AppError::AuthenticationError {
                    message: format!("Failed to decode JWT payload: {}", e),
                }
            })?;

        let payload_str = String::from_utf8(payload_bytes).map_err(|e| {
            error!(error = %e, "Failed to convert JWT payload to UTF-8");
            AppError::AuthenticationError {
                message: format!("Failed to convert JWT payload to string: {}", e),
            }
        })?;

        debug!(payload = payload_str, "Decoded JWT payload");

        // Parse JSON payload
        let payload: serde_json::Value = serde_json::from_str(&payload_str).map_err(|e| {
            error!(
                error = %e,
                payload = payload_str,
                "Failed to parse JWT payload as JSON"
            );
            AppError::AuthenticationError {
                message: format!("Failed to parse JWT payload: {}", e),
            }
        })?;

        // Log all available claims for debugging
        debug!(
            available_claims = ?payload.as_object().map(|obj| obj.keys().collect::<Vec<_>>()),
            "Available claims in JWT payload"
        );

        // Try to extract user ID from various possible claim names
        let user_id = payload
            .get("sub")
            .or_else(|| payload.get("user_id"))
            .or_else(|| payload.get("uid"))
            .or_else(|| payload.get("nameid"))
            .and_then(|v| v.as_str())
            .ok_or_else(|| {
                error!(
                    payload = %payload,
                    "No user identifier found in JWT claims"
                );
                AppError::AuthenticationError {
                    message: "No user identifier found in JWT token".to_string(),
                }
            })?;

        debug!(
            user_id = user_id,
            "Successfully extracted user_id from JWT token"
        );
        Ok(user_id.to_string())
    }
}
