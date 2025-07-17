use serde::{Deserialize, Serialize};

/// Authentication response from Bitwarden API
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: u32,
    pub key: Option<String>,
    pub private_key: Option<String>,
}

/// Login request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
    pub two_factor_token: Option<String>,
    pub two_factor_provider: Option<i32>,
    pub two_factor_remember: Option<bool>,
}
