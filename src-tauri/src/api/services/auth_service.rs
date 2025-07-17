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

        // Extract user ID from the response or decode from token
        let user_id = response
            .get("user_id")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        Ok(LoginResponse {
            access_token: access_token.to_string(),
            refresh_token: refresh_token.to_string(),
            token_type: token_type.to_string(),
            expires_in,
            user_id,
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
}
