use crate::api::client::ApiClient;
use crate::api::repositories::traits::AuthRepository;
use crate::error::AppResult;
use async_trait::async_trait;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;
use tracing::{debug, error};

/// API-based authentication repository implementation
pub struct ApiAuthRepository {
    client: Arc<ApiClient>,
}

impl ApiAuthRepository {
    pub fn new(client: Arc<ApiClient>) -> Self {
        Self { client }
    }
}

#[async_trait]
impl AuthRepository for ApiAuthRepository {
    async fn prelogin(&self, email: &str) -> AppResult<Value> {
        debug!(email = email, "Repository: Making prelogin API call");

        // Create JSON request body instead of form data
        let request_body = json!({
            "email": email
        });

        debug!(
            email = email,
            request_body = %request_body,
            "Repository: Sending prelogin request with JSON body"
        );

        // Use post (JSON) to API endpoint instead of post_form_identity
        let result = self
            .client
            .post("/accounts/prelogin", &request_body, None)
            .await;

        match &result {
            Ok(response) => {
                debug!(
                    email = email,
                    response = %response,
                    "Repository: Prelogin API call successful"
                );
            }
            Err(e) => {
                error!(
                    email = email,
                    error = %e,
                    "Repository: Prelogin API call failed"
                );
            }
        }

        result
    }

    async fn login(
        &self,
        email: &str,
        password_hash: &str,
        two_factor_token: Option<&str>,
    ) -> AppResult<Value> {
        debug!(
            email = email,
            has_2fa = two_factor_token.is_some(),
            "Repository: Making login API call"
        );

        let mut form_data = HashMap::new();
        form_data.insert("grant_type".to_string(), "password".to_string());
        form_data.insert("username".to_string(), email.to_string());
        form_data.insert("password".to_string(), password_hash.to_string());
        form_data.insert("scope".to_string(), "api offline_access".to_string());
        form_data.insert("client_id".to_string(), "desktop".to_string());

        if let Some(token) = two_factor_token {
            form_data.insert("twoFactorToken".to_string(), token.to_string());
            form_data.insert("twoFactorProvider".to_string(), "0".to_string()); // Authenticator app
        }

        let result = self
            .client
            .post_form_identity("/identity/connect/token", &form_data, None)
            .await;

        match &result {
            Ok(_) => debug!(email = email, "Repository: Login API call successful"),
            Err(e) => error!(email = email, error = %e, "Repository: Login API call failed"),
        }

        result
    }

    async fn refresh_access_token(&self, refresh_token: &str) -> AppResult<Value> {
        debug!("Repository: Making token refresh API call");

        let mut form_data = HashMap::new();
        form_data.insert("grant_type".to_string(), "refresh_token".to_string());
        form_data.insert("refresh_token".to_string(), refresh_token.to_string());

        let result = self
            .client
            .post_form_identity("/identity/connect/token", &form_data, None)
            .await;

        match &result {
            Ok(_) => debug!("Repository: Token refresh API call successful"),
            Err(e) => error!(error = %e, "Repository: Token refresh API call failed"),
        }

        result
    }

    async fn get_profile(&self, access_token: &str) -> AppResult<Value> {
        debug!("Repository: Making get profile API call");

        let result = self
            .client
            .get("/accounts/profile", Some(access_token))
            .await;

        match &result {
            Ok(_) => debug!("Repository: Get profile API call successful"),
            Err(e) => error!(error = %e, "Repository: Get profile API call failed"),
        }

        result
    }

    async fn logout(&self, access_token: &str) -> AppResult<()> {
        debug!("Repository: Making logout API call");

        // For Bitwarden, logout is typically handled client-side by clearing tokens
        // Some implementations might call a revoke endpoint
        let result: Result<Value, _> = self
            .client
            .post_identity(
                "/identity/connect/revoke",
                &serde_json::json!({}),
                Some(access_token),
            )
            .await;

        match &result {
            Ok(_) => {
                debug!("Repository: Logout API call successful");
                Ok(())
            }
            Err(e) => {
                error!(error = %e, "Repository: Logout API call failed");
                Err(e.clone())
            }
        }
    }
}
