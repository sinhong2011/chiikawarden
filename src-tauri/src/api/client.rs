use crate::error::{AppError, AppResult};
use crate::logging::{log_http_request, log_http_response};
use crate::services::ServerProviderService;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;
use tauri::AppHandle;
use tauri_plugin_http::reqwest;
use tracing::{debug, error, info, warn};

/// HTTP client for making API requests with proper error handling and authentication
pub struct ApiClient {
    _app_handle: AppHandle,
    server_provider_service: Arc<ServerProviderService>,
    client: reqwest::Client,
}

impl ApiClient {
    /// Create API client with server provider service
    pub fn new(app_handle: AppHandle, server_provider_service: Arc<ServerProviderService>) -> Self {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .user_agent("Chiikawarden/1.0.0")
            .build()
            .expect("Failed to create HTTP client");

        Self {
            _app_handle: app_handle,
            server_provider_service,
            client,
        }
    }

    /// Get API URL from the server provider service
    async fn get_api_url(&self) -> String {
        self.server_provider_service.get_api_url().await
    }

    /// Get identity URL from the server provider service
    async fn get_identity_url(&self) -> String {
        self.server_provider_service.get_identity_url().await
    }

    /// Make a GET request to API endpoint
    pub async fn get<T>(&self, endpoint: &str, token: Option<&str>) -> AppResult<T>
    where
        T: for<'de> Deserialize<'de>,
    {
        let api_url = self.get_api_url().await;
        let url = format!("{}{}", api_url.trim_end_matches('/'), endpoint);
        let start_time = Instant::now();

        // Log the request
        log_http_request("GET", &url, token.is_some());
        info!(
            endpoint = endpoint,
            url = %url,
            has_token = token.is_some(),
            token_length = token.map(|t| t.len()).unwrap_or(0),
            "[api_client] Making HTTP GET request to Vaultwarden server"
        );

        let headers = self.build_headers(token).await?;
        let response = self
            .client
            .get(&url)
            .headers(self.build_header_map(&headers)?)
            .send()
            .await
            .map_err(|e| {
                let duration = start_time.elapsed().as_millis() as u64;
                error!(
                    method = "GET",
                    url = %url,
                    duration_ms = duration,
                    error = %e,
                    "HTTP request failed with network error"
                );
                AppError::NetworkError {
                    status: 0,
                    message: e.to_string(),
                }
            })?;

        let status = response.status().as_u16();
        let duration = start_time.elapsed().as_millis() as u64;

        // Log the response
        log_http_response("GET", &url, status, duration);

        if status == 200 {
            info!(
                endpoint = endpoint,
                url = %url,
                status = status,
                duration_ms = duration,
                "[api_client] HTTP GET request successful - received data from Vaultwarden server"
            );
        } else {
            error!(
                endpoint = endpoint,
                url = %url,
                status = status,
                duration_ms = duration,
                "[api_client] HTTP GET request failed with status {} - this will cause sync failures", status
            );
        }

        self.handle_response(response).await
    }

    /// Make a GET request to identity endpoint
    pub async fn get_identity<T>(&self, endpoint: &str, token: Option<&str>) -> AppResult<T>
    where
        T: for<'de> Deserialize<'de>,
    {
        let identity_url = self.server_provider_service.get_identity_url().await;
        let url = format!("{}{}", identity_url.trim_end_matches('/'), endpoint);
        let start_time = Instant::now();

        // Log the request
        log_http_request("GET", &url, token.is_some());
        debug!(
            endpoint = endpoint,
            has_token = token.is_some(),
            "Making GET request to identity endpoint"
        );

        let headers = self.build_headers(token).await?;
        let response = self
            .client
            .get(&url)
            .headers(self.build_header_map(&headers)?)
            .send()
            .await
            .map_err(|e| {
                let duration = start_time.elapsed().as_millis() as u64;
                error!(
                    method = "GET",
                    url = %url,
                    duration_ms = duration,
                    error = %e,
                    "Identity HTTP request failed with network error"
                );
                AppError::NetworkError {
                    status: 0,
                    message: e.to_string(),
                }
            })?;

        let status = response.status().as_u16();
        let duration = start_time.elapsed().as_millis() as u64;

        // Log the response
        log_http_response("GET", &url, status, duration);

        self.handle_response(response).await
    }

    /// Make a POST request to API endpoint
    pub async fn post<T, B>(&self, endpoint: &str, body: &B, token: Option<&str>) -> AppResult<T>
    where
        T: for<'de> Deserialize<'de>,
        B: Serialize,
    {
        let api_url = self.get_api_url().await;
        let url = format!("{}{}", api_url.trim_end_matches('/'), endpoint);
        let start_time = Instant::now();

        // Log the request
        log_http_request("POST", &url, token.is_some());
        debug!(
            endpoint = endpoint,
            api_url = %api_url,
            final_url = %url,
            has_token = token.is_some(),
            "Making POST request"
        );

        let headers = self.build_headers(token).await?;
        let response = self
            .client
            .post(&url)
            .headers(self.build_header_map(&headers)?)
            .json(body)
            .send()
            .await
            .map_err(|e| {
                let duration = start_time.elapsed().as_millis() as u64;
                error!(
                    method = "POST",
                    url = %url,
                    duration_ms = duration,
                    error = %e,
                    "HTTP POST request failed with network error"
                );
                AppError::NetworkError {
                    status: 0,
                    message: e.to_string(),
                }
            })?;

        let status = response.status().as_u16();
        let duration = start_time.elapsed().as_millis() as u64;

        // Log the response
        log_http_response("POST", &url, status, duration);

        self.handle_response(response).await
    }

    /// Make a POST request to identity endpoint
    pub async fn post_identity<T, B>(
        &self,
        endpoint: &str,
        body: &B,
        token: Option<&str>,
    ) -> AppResult<T>
    where
        T: for<'de> Deserialize<'de>,
        B: Serialize,
    {
        let identity_url = self.server_provider_service.get_identity_url().await;
        let url = format!("{}{}", identity_url.trim_end_matches('/'), endpoint);
        let start_time = Instant::now();

        // Log the request
        log_http_request("POST", &url, token.is_some());
        debug!(
            endpoint = endpoint,
            has_token = token.is_some(),
            "Making POST request to identity endpoint"
        );

        let headers = self.build_headers(token).await?;
        let response = self
            .client
            .post(&url)
            .headers(self.build_header_map(&headers)?)
            .json(body)
            .send()
            .await
            .map_err(|e| {
                let duration = start_time.elapsed().as_millis() as u64;
                error!(
                    method = "POST",
                    url = %url,
                    duration_ms = duration,
                    error = %e,
                    "Identity HTTP POST request failed with network error"
                );
                AppError::NetworkError {
                    status: 0,
                    message: e.to_string(),
                }
            })?;

        let status = response.status().as_u16();
        let duration = start_time.elapsed().as_millis() as u64;

        // Log the response
        log_http_response("POST", &url, status, duration);

        self.handle_response(response).await
    }

    /// Make a POST request with form data to identity endpoint (for authentication)
    pub async fn post_form_identity<T>(
        &self,
        endpoint: &str,
        form: &HashMap<String, String>,
        token: Option<&str>,
    ) -> AppResult<T>
    where
        T: for<'de> Deserialize<'de>,
    {
        debug!("post_form_identity: {:?}", form);
        let identity_url = self.get_identity_url().await;
        let url = format!("{}{}", identity_url.trim_end_matches('/'), endpoint);
        let start_time = Instant::now();

        // Log the request (don't log form data for security)
        log_http_request("POST", &url, token.is_some());
        debug!(
            endpoint = endpoint,
            has_token = token.is_some(),
            form_fields = form.len(),
            "Making POST form request to identity endpoint"
        );

        let mut headers = self.build_headers(token).await?;
        headers.insert(
            "Content-Type".to_string(),
            "application/x-www-form-urlencoded".to_string(),
        );

        let response = self
            .client
            .post(&url)
            .headers(self.build_header_map(&headers)?)
            .form(form)
            .send()
            .await
            .map_err(|e| {
                let duration = start_time.elapsed().as_millis() as u64;
                error!(
                    method = "POST",
                    url = %url,
                    duration_ms = duration,
                    error = %e,
                    "Identity HTTP POST form request failed with network error"
                );
                AppError::NetworkError {
                    status: 0,
                    message: e.to_string(),
                }
            })?;

        let status = response.status().as_u16();
        let duration = start_time.elapsed().as_millis() as u64;

        // Log the response
        log_http_response("POST", &url, status, duration);

        self.handle_response(response).await
    }

    /// Make a PUT request to API endpoint
    pub async fn put<T, B>(&self, endpoint: &str, body: &B, token: Option<&str>) -> AppResult<T>
    where
        T: for<'de> Deserialize<'de>,
        B: Serialize,
    {
        let api_url = self.server_provider_service.get_api_url().await;
        let url = format!("{}{}", api_url.trim_end_matches('/'), endpoint);

        let headers = self.build_headers(token).await?;
        let response = self
            .client
            .put(&url)
            .headers(self.build_header_map(&headers)?)
            .json(body)
            .send()
            .await
            .map_err(|e| AppError::NetworkError {
                status: 0,
                message: e.to_string(),
            })?;

        self.handle_response(response).await
    }

    /// Make a DELETE request to API endpoint
    pub async fn delete<T>(&self, endpoint: &str, token: Option<&str>) -> AppResult<T>
    where
        T: for<'de> Deserialize<'de>,
    {
        let api_url = self.server_provider_service.get_api_url().await;
        let url = format!("{}{}", api_url.trim_end_matches('/'), endpoint);

        let headers = self.build_headers(token).await?;
        let response = self
            .client
            .delete(&url)
            .headers(self.build_header_map(&headers)?)
            .send()
            .await
            .map_err(|e| AppError::NetworkError {
                status: 0,
                message: e.to_string(),
            })?;

        self.handle_response(response).await
    }

    /// Build standard headers for requests
    async fn build_headers(&self, token: Option<&str>) -> AppResult<HashMap<String, String>> {
        let mut headers = HashMap::new();

        // Standard headers
        headers.insert("Content-Type".to_string(), "application/json".to_string());
        headers.insert("Accept".to_string(), "application/json".to_string());
        headers.insert("User-Agent".to_string(), "Chiikawarden/1.0.0".to_string());

        // Add client identification headers (similar to Bitwarden)
        headers.insert(
            "Bitwarden-Client-Name".to_string(),
            "Chiikawarden".to_string(),
        );
        headers.insert("Bitwarden-Client-Version".to_string(), "1.0.0".to_string());

        // Add authorization header if token provided
        if let Some(token) = token {
            headers.insert("Authorization".to_string(), format!("Bearer {}", token));
        }

        // Add cache control for GET requests
        headers.insert("Cache-Control".to_string(), "no-store".to_string());
        headers.insert("Pragma".to_string(), "no-cache".to_string());

        Ok(headers)
    }

    /// Build header map from HashMap
    fn build_header_map(
        &self,
        headers: &HashMap<String, String>,
    ) -> AppResult<reqwest::header::HeaderMap> {
        let mut header_map = reqwest::header::HeaderMap::new();

        for (key, value) in headers {
            let header_name =
                reqwest::header::HeaderName::from_bytes(key.as_bytes()).map_err(|_| {
                    AppError::NetworkError {
                        status: 0,
                        message: format!("Invalid header name: {}", key),
                    }
                })?;

            let header_value = reqwest::header::HeaderValue::from_str(value).map_err(|_| {
                AppError::NetworkError {
                    status: 0,
                    message: format!("Invalid header value: {}", value),
                }
            })?;

            header_map.insert(header_name, header_value);
        }

        Ok(header_map)
    }

    /// Handle HTTP response and deserialize JSON
    async fn handle_response<T>(&self, response: reqwest::Response) -> AppResult<T>
    where
        T: for<'de> Deserialize<'de>,
    {
        let status = response.status();
        let status_code = status.as_u16();

        if status.is_success() {
            debug!(status = status_code, "Reading successful response body");

            let body = response.text().await.map_err(|e| {
                error!(
                    status = status_code,
                    error = %e,
                    "Failed to read response body"
                );
                AppError::NetworkError {
                    status: status_code,
                    message: format!("Failed to read response body: {}", e),
                }
            })?;

            debug!(
                status = status_code,
                body_length = body.len(),
                "Response body read successfully, parsing JSON"
            );

            // Log complete response body for authentication endpoints (for debugging user_id issue)
            if body.contains("access_token") || body.contains("refresh_token") {
                debug!(
                    target: "chiikawarden::api::auth_response",
                    status = status_code,
                    response_body = %body,
                    "Complete authentication response body for debugging"
                );
            }

            serde_json::from_str(&body).map_err(|e| {
                error!(
                    status = status_code,
                    error = %e,
                    body_preview = &body[..std::cmp::min(200, body.len())],
                    "Failed to parse JSON response"
                );
                AppError::NetworkError {
                    status: status_code,
                    message: format!("Failed to parse JSON response: {}", e),
                }
            })
        } else {
            warn!(
                status = status_code,
                "HTTP request failed, reading error response"
            );

            let error_body = response
                .text()
                .await
                .unwrap_or_else(|_| "Unknown error".to_string());

            error!(
                status = status_code,
                error_body = %error_body,
                "HTTP request failed"
            );

            Err(AppError::NetworkError {
                status: status_code,
                message: format!("HTTP {} - {}", status, error_body),
            })
        }
    }

    /// Make a GET request with automatic token refresh on 401 errors
    pub async fn get_with_auto_refresh<T>(
        &self,
        endpoint: &str,
        user_id: &str,
        token_manager: &Arc<tokio::sync::RwLock<crate::crypto::token_manager::TokenManager>>,
    ) -> AppResult<T>
    where
        T: for<'de> Deserialize<'de>,
    {
        use crate::debug_config::CorrelationId;
        use crate::debug_token_op;

        let correlation_id = CorrelationId::new();

        info!(
            user_id = user_id,
            endpoint = endpoint,
            operation = "get_with_auto_refresh",
            correlation_id = %correlation_id,
            "[api_client] Starting GET request with auto-refresh - this is the actual API call to server"
        );

        // First attempt: Get current access token and try the request
        info!(
            user_id = user_id,
            endpoint = endpoint,
            operation = "get_with_auto_refresh",
            correlation_id = %correlation_id,
            "[api_client] Retrieving access token for API authentication"
        );

        let token_manager_guard = token_manager.read().await;
        let access_token = match token_manager_guard
            .retrieve_access_token_with_correlation(user_id, Some(&correlation_id))
            .await
        {
            Ok(Some(token)) => {
                info!(
                    user_id = user_id,
                    endpoint = endpoint,
                    operation = "get_with_auto_refresh",
                    correlation_id = %correlation_id,
                    token_length = token.len(),
                    "[api_client] Access token retrieved successfully - proceeding with API call"
                );
                token
            }
            Ok(None) => {
                error!(
                    user_id = user_id,
                    endpoint = endpoint,
                    operation = "get_with_auto_refresh",
                    correlation_id = %correlation_id,
                    "[api_client] CRITICAL: No access token available - API call will fail"
                );
                return Err(AppError::AuthenticationError {
                    message: "No access token available".to_string(),
                });
            }
            Err(e) => {
                error!(
                    user_id = user_id,
                    endpoint = endpoint,
                    error = %e,
                    correlation_id = %correlation_id,
                    "[api_client] Failed to retrieve access token"
                );
                return Err(AppError::AuthenticationError {
                    message: format!("Failed to retrieve access token: {}", e),
                });
            }
        };
        drop(token_manager_guard); // Release the lock

        // Try the request with current token
        match self.get(endpoint, Some(&access_token)).await {
            Ok(response) => {
                debug_token_op!(
                    user_id = user_id,
                    endpoint = endpoint,
                    operation = "get_with_auto_refresh",
                    correlation_id = %correlation_id,
                    "[api_client] GET request succeeded with current token"
                );
                Ok(response)
            }
            Err(AppError::NetworkError { status: 401, .. }) => {
                debug_token_op!(
                    user_id = user_id,
                    endpoint = endpoint,
                    operation = "get_with_auto_refresh",
                    correlation_id = %correlation_id,
                    "[api_client] Got 401, attempting token refresh"
                );

                // Token expired, try to refresh
                let token_manager_guard = token_manager.read().await;
                if let Err(e) = token_manager_guard
                    .refresh_access_token_with_correlation(user_id, Some(&correlation_id))
                    .await
                {
                    error!(
                        user_id = user_id,
                        endpoint = endpoint,
                        error = %e,
                        correlation_id = %correlation_id,
                        "[api_client] Token refresh failed"
                    );
                    return Err(AppError::AuthenticationError {
                        message: format!("Token refresh failed: {}", e),
                    });
                }

                // Get the new token and retry
                let new_token = match token_manager_guard
                    .retrieve_access_token_with_correlation(user_id, Some(&correlation_id))
                    .await
                {
                    Ok(Some(token)) => token,
                    Ok(None) => {
                        return Err(AppError::AuthenticationError {
                            message: "No access token available after refresh".to_string(),
                        });
                    }
                    Err(e) => {
                        return Err(AppError::AuthenticationError {
                            message: format!("Failed to retrieve refreshed access token: {}", e),
                        });
                    }
                };
                drop(token_manager_guard); // Release the lock

                debug_token_op!(
                    user_id = user_id,
                    endpoint = endpoint,
                    operation = "get_with_auto_refresh",
                    correlation_id = %correlation_id,
                    "[api_client] Retrying GET request with refreshed token"
                );

                // Retry with new token
                self.get(endpoint, Some(&new_token)).await
            }
            Err(e) => Err(e), // Other errors, don't retry
        }
    }

    /// Make a POST request with automatic token refresh on 401 errors
    pub async fn post_with_auto_refresh<T, B>(
        &self,
        endpoint: &str,
        body: &B,
        user_id: &str,
        token_manager: &Arc<tokio::sync::RwLock<crate::crypto::token_manager::TokenManager>>,
    ) -> AppResult<T>
    where
        T: for<'de> Deserialize<'de>,
        B: Serialize,
    {
        use crate::debug_config::CorrelationId;
        use crate::debug_token_op;

        let correlation_id = CorrelationId::new();

        debug_token_op!(
            user_id = user_id,
            endpoint = endpoint,
            operation = "post_with_auto_refresh",
            correlation_id = %correlation_id,
            "[api_client] Starting POST request with auto-refresh"
        );

        // First attempt: Get current access token and try the request
        let token_manager_guard = token_manager.read().await;
        let access_token = match token_manager_guard
            .retrieve_access_token_with_correlation(user_id, Some(&correlation_id))
            .await
        {
            Ok(Some(token)) => token,
            Ok(None) => {
                debug_token_op!(
                    user_id = user_id,
                    endpoint = endpoint,
                    operation = "post_with_auto_refresh",
                    correlation_id = %correlation_id,
                    "[api_client] No access token available"
                );
                return Err(AppError::AuthenticationError {
                    message: "No access token available".to_string(),
                });
            }
            Err(e) => {
                error!(
                    user_id = user_id,
                    endpoint = endpoint,
                    error = %e,
                    correlation_id = %correlation_id,
                    "[api_client] Failed to retrieve access token"
                );
                return Err(AppError::AuthenticationError {
                    message: format!("Failed to retrieve access token: {}", e),
                });
            }
        };
        drop(token_manager_guard); // Release the lock

        // Try the request with current token
        match self.post(endpoint, body, Some(&access_token)).await {
            Ok(response) => {
                debug_token_op!(
                    user_id = user_id,
                    endpoint = endpoint,
                    operation = "post_with_auto_refresh",
                    correlation_id = %correlation_id,
                    "[api_client] POST request succeeded with current token"
                );
                Ok(response)
            }
            Err(AppError::NetworkError { status: 401, .. }) => {
                debug_token_op!(
                    user_id = user_id,
                    endpoint = endpoint,
                    operation = "post_with_auto_refresh",
                    correlation_id = %correlation_id,
                    "[api_client] Got 401, attempting token refresh"
                );

                // Token expired, try to refresh
                let token_manager_guard = token_manager.read().await;
                if let Err(e) = token_manager_guard
                    .refresh_access_token_with_correlation(user_id, Some(&correlation_id))
                    .await
                {
                    error!(
                        user_id = user_id,
                        endpoint = endpoint,
                        error = %e,
                        correlation_id = %correlation_id,
                        "[api_client] Token refresh failed"
                    );
                    return Err(AppError::AuthenticationError {
                        message: format!("Token refresh failed: {}", e),
                    });
                }

                // Get the new token and retry
                let new_token = match token_manager_guard
                    .retrieve_access_token_with_correlation(user_id, Some(&correlation_id))
                    .await
                {
                    Ok(Some(token)) => token,
                    Ok(None) => {
                        return Err(AppError::AuthenticationError {
                            message: "No access token available after refresh".to_string(),
                        });
                    }
                    Err(e) => {
                        return Err(AppError::AuthenticationError {
                            message: format!("Failed to retrieve refreshed access token: {}", e),
                        });
                    }
                };
                drop(token_manager_guard); // Release the lock

                debug_token_op!(
                    user_id = user_id,
                    endpoint = endpoint,
                    operation = "post_with_auto_refresh",
                    correlation_id = %correlation_id,
                    "[api_client] Retrying POST request with refreshed token"
                );

                // Retry with new token
                self.post(endpoint, body, Some(&new_token)).await
            }
            Err(e) => Err(e), // Other errors, don't retry
        }
    }
}

// Note: Default implementation removed since ApiClient requires AppHandle
