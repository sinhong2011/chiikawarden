use crate::logging::{log_http_request_with_context, log_http_response_with_details};
use std::time::Instant;
use tauri_plugin_http::reqwest::{self, Request, Response};
use tracing::{debug, error, warn};

/// HTTP logging middleware for automatic request/response logging
pub struct HttpLoggingMiddleware {
    log_request_body: bool,
    log_response_body: bool,
    max_body_size: usize,
}

impl HttpLoggingMiddleware {
    /// Create new HTTP logging middleware
    pub fn new() -> Self {
        Self {
            log_request_body: false,
            log_response_body: false,
            max_body_size: 1024, // 1KB default
        }
    }

    /// Enable request body logging (up to max_body_size)
    pub fn with_request_body_logging(mut self, enabled: bool) -> Self {
        self.log_request_body = enabled;
        self
    }

    /// Enable response body logging (up to max_body_size)
    pub fn with_response_body_logging(mut self, enabled: bool) -> Self {
        self.log_response_body = enabled;
        self
    }

    /// Set maximum body size to log
    pub fn with_max_body_size(mut self, size: usize) -> Self {
        self.max_body_size = size;
        self
    }

    /// Log request details
    pub fn log_request(&self, request: &Request) {
        let method = request.method().as_str();
        let url = request.url().as_str();
        let has_auth = request.headers().get("authorization").is_some();

        let user_agent = request
            .headers()
            .get("user-agent")
            .and_then(|v| v.to_str().ok());

        let content_type = request
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok());

        log_http_request_with_context(method, url, has_auth, user_agent, content_type);

        // Log additional request details in debug mode
        if cfg!(debug_assertions) {
            debug!(
                target: "chiikawarden::api::request::details",
                method = method,
                url = url,
                headers = ?request.headers(),
                "Request headers"
            );
        }
    }

    /// Log response details
    pub fn log_response(
        &self,
        request: &Request,
        response: &Response,
        duration: std::time::Duration,
    ) {
        let method = request.method().as_str();
        let url = request.url().as_str();
        let status = response.status().as_u16();
        let duration_ms = duration.as_millis() as u64;

        let content_length = response
            .headers()
            .get("content-length")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.parse::<u64>().ok());

        let content_type = response
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok());

        log_http_response_with_details(
            method,
            url,
            status,
            duration_ms,
            content_length,
            content_type,
        );

        // Log additional response details in debug mode
        if cfg!(debug_assertions) {
            debug!(
                target: "chiikawarden::api::response::details",
                method = method,
                url = url,
                status = status,
                headers = ?response.headers(),
                "Response headers"
            );
        }

        // Log slow requests as warnings
        if duration_ms > 5000 {
            warn!(
                target: "chiikawarden::api::performance",
                method = method,
                url = url,
                duration_ms = duration_ms,
                "[WARN] Slow HTTP request: {} {} took {}ms",
                method,
                url,
                duration_ms
            );
        }
    }

    /// Log request error
    pub fn log_request_error(
        &self,
        request: &Request,
        error: &reqwest::Error,
        duration: std::time::Duration,
    ) {
        let method = request.method().as_str();
        let url = request.url().as_str();
        let duration_ms = duration.as_millis() as u64;

        error!(
            target: "chiikawarden::api::error",
            method = method,
            url = url,
            duration_ms = duration_ms,
            error = %error,
            "[ERROR] HTTP request failed: {} {} after {}ms - {}",
            method,
            url,
            duration_ms,
            error
        );
    }
}

impl Default for HttpLoggingMiddleware {
    fn default() -> Self {
        Self::new()
    }
}

/// HTTP client wrapper with automatic logging
pub struct LoggingHttpClient {
    client: reqwest::Client,
    middleware: HttpLoggingMiddleware,
}

impl LoggingHttpClient {
    /// Create new logging HTTP client
    pub fn new(client: reqwest::Client) -> Self {
        Self {
            client,
            middleware: HttpLoggingMiddleware::new(),
        }
    }

    /// Create new logging HTTP client with custom middleware
    pub fn with_middleware(client: reqwest::Client, middleware: HttpLoggingMiddleware) -> Self {
        Self { client, middleware }
    }

    /// Execute request with automatic logging
    pub async fn execute(&self, request: Request) -> Result<Response, reqwest::Error> {
        let start_time = Instant::now();

        // Log the request
        self.middleware.log_request(&request);

        // Execute the request
        match self.client.execute(request.try_clone().unwrap()).await {
            Ok(response) => {
                let duration = start_time.elapsed();

                // Log the response
                self.middleware.log_response(&request, &response, duration);

                Ok(response)
            }
            Err(error) => {
                let duration = start_time.elapsed();

                // Log the error
                self.middleware
                    .log_request_error(&request, &error, duration);

                Err(error)
            }
        }
    }

    /// Get reference to underlying client
    pub fn client(&self) -> &reqwest::Client {
        &self.client
    }
}

/// Utility functions for HTTP logging
pub mod utils {
    use super::*;

    /// Extract client IP from request headers (for future WebSocket logging)
    pub fn extract_client_ip(headers: &reqwest::header::HeaderMap) -> Option<String> {
        // Try various headers that might contain client IP
        let ip_headers = [
            "x-forwarded-for",
            "x-real-ip",
            "cf-connecting-ip",
            "x-client-ip",
        ];

        for header_name in &ip_headers {
            if let Some(value) = headers.get(*header_name) {
                if let Ok(ip_str) = value.to_str() {
                    // Take the first IP if there are multiple (comma-separated)
                    let ip = ip_str.split(',').next().unwrap_or(ip_str).trim();
                    if !ip.is_empty() {
                        return Some(ip.to_string());
                    }
                }
            }
        }

        None
    }

    /// Check if request should be logged (filter out health checks, etc.)
    pub fn should_log_request(url: &str) -> bool {
        // Skip logging for certain endpoints
        let skip_patterns = ["/health", "/ping", "/metrics", "/.well-known"];

        !skip_patterns.iter().any(|pattern| url.contains(pattern))
    }

    /// Sanitize URL for logging (remove sensitive parameters)
    pub fn sanitize_url_for_logging(url: &str) -> String {
        let mut sanitized = url.to_string();

        // Remove common sensitive parameters
        let sensitive_params = ["password", "token", "key", "secret", "auth"];

        for param in &sensitive_params {
            // Simple regex-like replacement for query parameters
            if let Some(start) = sanitized.find(&format!("{}=", param)) {
                if let Some(end) = sanitized[start..].find('&') {
                    sanitized.replace_range(start..start + end, &format!("{}=***", param));
                } else {
                    // Last parameter
                    sanitized = format!("{}{}=***", &sanitized[..start], param);
                }
            }
        }

        sanitized
    }
}
