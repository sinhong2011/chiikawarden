use crate::error::{AppError, AppResult};
use crate::models::{
    ConnectivityStatus, ServerProvider, ServerProviderConfig, ServerProviderTrait,
    ServerProviderUrls,
};
use std::sync::Arc;
use std::time::Duration;
use tauri::AppHandle;
use tauri_plugin_http::reqwest;
use tauri_plugin_store::StoreExt;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

const SERVER_PROVIDERS_FILE: &str = "server-providers.json";
const SERVER_PROVIDERS_KEY: &str = "config";

/// Server provider service for managing Bitwarden server configurations
pub struct ServerProviderService {
    app_handle: AppHandle,
    config: Arc<RwLock<ServerProviderConfig>>,
    http_client: reqwest::Client,
}

impl ServerProviderService {
    /// Create a new server provider service
    pub async fn new(app_handle: AppHandle) -> AppResult<Self> {
        // Load configuration from store or create default
        let config = Self::load_or_create_default_config(&app_handle).await?;
        let config = Arc::new(RwLock::new(config));

        // Create HTTP client for connectivity testing
        let http_client = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .user_agent("Chiikawarden/1.0.0")
            .build()
            .map_err(|e| AppError::InternalError {
                message: format!("Failed to create HTTP client: {}", e),
            })?;

        Ok(Self {
            app_handle,
            config,
            http_client,
        })
    }

    /// Initialize the service by loading configuration
    pub async fn initialize(&self) -> AppResult<()> {
        debug!("Initializing server provider service");

        // Configuration is already loaded in new(), just log the current state
        let config = self.config.read().await;
        if let Some(current) = config.get_current_provider() {
            info!(
                provider_id = current.id,
                provider_label = current.label,
                provider_type = ?current.provider_type,
                "Server provider service initialized with current provider"
            );
        }

        Ok(())
    }

    /// Get the current active server provider
    pub async fn get_current_provider(&self) -> Option<ServerProvider> {
        let config = self.config.read().await;
        config.get_current_provider().cloned()
    }

    /// Set the current active server provider
    pub async fn set_current_provider(&self, provider_id: String) -> AppResult<()> {
        debug!(provider_id = provider_id, "Setting current server provider");

        {
            let mut config = self.config.write().await;
            config
                .set_current_provider(provider_id.clone())
                .map_err(|e| AppError::ValidationError {
                    field: "provider_id".to_string(),
                    message: e,
                })?;
        }

        // Save to store
        self.save_config().await?;

        info!(provider_id = provider_id, "Current server provider updated");
        Ok(())
    }

    /// Get all available server providers
    pub async fn get_all_providers(&self) -> Vec<ServerProvider> {
        let config = self.config.read().await;
        let providers = config.get_all_providers();
        debug!(
            provider_count = providers.len(),
            "Retrieved all server providers"
        );
        providers.into_iter().cloned().collect()
    }

    /// Get only preset providers
    pub async fn get_preset_providers(&self) -> Vec<ServerProvider> {
        let config = self.config.read().await;
        config.get_preset_providers().into_iter().cloned().collect()
    }

    /// Get only custom providers
    pub async fn get_custom_providers(&self) -> Vec<ServerProvider> {
        let config = self.config.read().await;
        config.get_custom_providers().into_iter().cloned().collect()
    }

    /// Add a new custom server provider
    pub async fn add_custom_provider(&self, label: String, base_url: String) -> AppResult<String> {
        debug!(
            label = %label,
            base_url = %base_url,
            "Adding custom server provider"
        );

        // Validate input parameters
        self.validate_provider_input(&label, &base_url)?;

        let provider_id = {
            let mut config = self.config.write().await;
            config.add_custom_provider(label.clone(), base_url)
        };

        // Save to store
        self.save_config().await?;

        info!(
            provider_id = provider_id,
            label = label,
            "Custom server provider added"
        );

        Ok(provider_id)
    }

    /// Add a new custom server provider with custom URLs
    pub async fn add_custom_provider_with_urls(
        &self,
        label: String,
        urls: ServerProviderUrls,
    ) -> AppResult<String> {
        debug!(
            label = %label,
            "Adding custom server provider with custom URLs"
        );

        // Validate label
        if label.trim().is_empty() {
            return Err(AppError::ValidationError {
                field: "label".to_string(),
                message: "Provider label cannot be empty".to_string(),
            });
        }

        if label.len() > 100 {
            return Err(AppError::ValidationError {
                field: "label".to_string(),
                message: "Provider label cannot exceed 100 characters".to_string(),
            });
        }

        // Validate URLs if provided
        self.validate_provider_urls(&urls)?;

        let provider_id = {
            let mut config = self.config.write().await;
            config.add_custom_provider_with_urls(label.clone(), urls)
        };

        // Save to store
        self.save_config().await?;

        info!(
            provider_id = provider_id,
            label = label,
            "Custom server provider with custom URLs added"
        );

        Ok(provider_id)
    }

    /// Update an existing server provider
    pub async fn update_provider(
        &self,
        provider_id: String,
        label: Option<String>,
        urls: Option<ServerProviderUrls>,
    ) -> AppResult<()> {
        debug!(
            provider_id = provider_id,
            has_label = label.is_some(),
            has_urls = urls.is_some(),
            "Updating server provider"
        );

        {
            let mut config = self.config.write().await;
            config
                .update_provider(&provider_id, label, urls)
                .map_err(|e| AppError::ValidationError {
                    field: "provider_id".to_string(),
                    message: e,
                })?;
        }

        // Save to store
        self.save_config().await?;

        info!(provider_id = provider_id, "Server provider updated");
        Ok(())
    }

    /// Remove a custom server provider
    pub async fn remove_provider(&self, provider_id: String) -> AppResult<()> {
        debug!(provider_id = provider_id, "Removing server provider");

        {
            let mut config = self.config.write().await;
            config
                .remove_provider(&provider_id)
                .map_err(|e| AppError::ValidationError {
                    field: "provider_id".to_string(),
                    message: e,
                })?;
        }

        // Save to store
        self.save_config().await?;

        info!(provider_id = provider_id, "Server provider removed");
        Ok(())
    }

    /// Get API URL for the current provider (prefers specific API URL over base URL)
    pub async fn get_api_url(&self) -> String {
        self.get_url_with_fallback(
            |urls| &urls.api,
            Some("api"),
            "https://api.bitwarden.com",
            "API",
        )
        .await
    }

    /// Get identity URL for the current provider (prefers specific identity URL over base URL)
    pub async fn get_identity_url(&self) -> String {
        self.get_url_with_fallback(
            |urls| &urls.identity,
            Some("identity"),
            "https://identity.bitwarden.com",
            "identity",
        )
        .await
    }

    /// Get web vault URL for the current provider (uses base URL as default)
    pub async fn get_web_vault_url(&self) -> String {
        if let Some(provider) = self.get_current_provider().await {
            // Use base URL as default if available, otherwise use specific web vault URL
            if let Some(base) = &provider.urls.base {
                base.trim_end_matches('/').to_string()
            } else {
                provider.get_web_vault_url()
            }
        } else {
            warn!("No current provider set, using default US web vault URL");
            "https://vault.bitwarden.com".to_string()
        }
    }

    /// Get icons URL for the current provider (uses base URL as default)
    pub async fn get_icons_url(&self) -> String {
        self.get_url_with_fallback(
            |urls| &urls.icons,
            Some("icons"),
            "https://icons.bitwarden.net",
            "icons",
        )
        .await
    }

    /// Get notifications URL for the current provider (uses base URL as default)
    pub async fn get_notifications_url(&self) -> String {
        self.get_url_with_fallback(
            |urls| &urls.notifications,
            Some("notifications"),
            "https://notifications.bitwarden.com",
            "notifications",
        )
        .await
    }

    /// Get events URL for the current provider (uses base URL as default)
    pub async fn get_events_url(&self) -> String {
        self.get_url_with_fallback(
            |urls| &urls.events,
            Some("events"),
            "https://events.bitwarden.com",
            "events",
        )
        .await
    }

    /// Test connectivity to the current provider
    pub async fn test_connectivity(&self) -> AppResult<ConnectivityStatus> {
        let provider =
            self.get_current_provider()
                .await
                .ok_or_else(|| AppError::ValidationError {
                    field: "provider".to_string(),
                    message: "No current provider set".to_string(),
                })?;

        debug!(
            provider_id = provider.id,
            "Testing connectivity to server provider"
        );

        // Test API endpoint
        let api_reachable = self.test_endpoint(&self.get_api_url().await).await;

        // Test identity endpoint
        let identity_reachable = self.test_endpoint(&self.get_identity_url().await).await;

        let overall_status = api_reachable && identity_reachable;

        info!(
            provider_id = provider.id,
            api_reachable = api_reachable,
            identity_reachable = identity_reachable,
            overall_status = overall_status,
            "Connectivity test completed"
        );

        Ok(ConnectivityStatus {
            api_reachable,
            identity_reachable,
            overall_status,
        })
    }

    // Private helper methods

    /// Load configuration from store or create default
    async fn load_or_create_default_config(
        app_handle: &AppHandle,
    ) -> AppResult<ServerProviderConfig> {
        let store =
            app_handle
                .store(SERVER_PROVIDERS_FILE)
                .map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to initialize server provider store: {}", e),
                })?;

        match store.get(SERVER_PROVIDERS_KEY) {
            Some(value) => {
                // Try to deserialize existing config
                match serde_json::from_value::<ServerProviderConfig>(value.clone()) {
                    Ok(config) => {
                        debug!("Loaded server provider configuration from store");
                        Ok(config)
                    }
                    Err(e) => {
                        warn!(
                            error = %e,
                            "Failed to deserialize server provider config, using default"
                        );
                        Ok(ServerProviderConfig::default())
                    }
                }
            }
            None => {
                debug!("No existing server provider configuration, using default");
                Ok(ServerProviderConfig::default())
            }
        }
    }

    /// Save current configuration to store
    async fn save_config(&self) -> AppResult<()> {
        let config = self.config.read().await;
        let config_value = serde_json::to_value(&*config).map_err(|e| AppError::DatabaseError {
            message: format!("Failed to serialize server provider config: {}", e),
        })?;

        let store =
            self.app_handle
                .store(SERVER_PROVIDERS_FILE)
                .map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to initialize server provider store: {}", e),
                })?;

        store.set(SERVER_PROVIDERS_KEY, config_value);

        store.save().map_err(|e| AppError::DatabaseError {
            message: format!("Failed to persist server provider config: {}", e),
        })?;

        debug!("Server provider configuration saved to store");
        Ok(())
    }

    /// Validate URL format
    fn is_valid_url(&self, url: &str) -> bool {
        url::Url::parse(url).is_ok()
    }

    /// Validate provider input parameters
    fn validate_provider_input(&self, label: &str, base_url: &str) -> AppResult<()> {
        // Validate label
        if label.trim().is_empty() {
            return Err(AppError::ValidationError {
                field: "label".to_string(),
                message: "Provider label cannot be empty".to_string(),
            });
        }

        if label.len() > 100 {
            return Err(AppError::ValidationError {
                field: "label".to_string(),
                message: "Provider label cannot exceed 100 characters".to_string(),
            });
        }

        // Validate URL format
        if !self.is_valid_url(base_url) {
            return Err(AppError::ValidationError {
                field: "base_url".to_string(),
                message: format!("Invalid URL format: {}", base_url),
            });
        }

        // Validate URL scheme
        if let Ok(parsed_url) = url::Url::parse(base_url) {
            if !matches!(parsed_url.scheme(), "http" | "https") {
                return Err(AppError::ValidationError {
                    field: "base_url".to_string(),
                    message: "URL must use HTTP or HTTPS scheme".to_string(),
                });
            }
        }

        Ok(())
    }

    /// Validate provider URLs
    fn validate_provider_urls(&self, urls: &ServerProviderUrls) -> AppResult<()> {
        let url_fields = [
            ("base", &urls.base),
            ("api", &urls.api),
            ("identity", &urls.identity),
            ("icons", &urls.icons),
            ("web_vault", &urls.web_vault),
            ("notifications", &urls.notifications),
            ("events", &urls.events),
            ("key_connector", &urls.key_connector),
            ("scim", &urls.scim),
        ];

        for (field_name, url_option) in url_fields {
            if let Some(url) = url_option {
                if !self.is_valid_url(url) {
                    return Err(AppError::ValidationError {
                        field: field_name.to_string(),
                        message: format!("Invalid URL format: {}", url),
                    });
                }

                // Validate URL scheme
                if let Ok(parsed_url) = url::Url::parse(url) {
                    if !matches!(parsed_url.scheme(), "http" | "https") {
                        return Err(AppError::ValidationError {
                            field: field_name.to_string(),
                            message: "URL must use HTTP or HTTPS scheme".to_string(),
                        });
                    }
                }
            }
        }

        Ok(())
    }

    /// Test if an endpoint is reachable using HTTP HEAD request
    async fn test_endpoint(&self, url: &str) -> bool {
        // First validate URL format
        if !self.is_valid_url(url) {
            debug!(url = %url, "Invalid URL format for connectivity test");
            return false;
        }

        debug!(url = %url, "Testing endpoint connectivity");

        // Perform HTTP HEAD request to test connectivity
        match self.http_client.head(url).send().await {
            Ok(response) => {
                let status = response.status();
                let is_reachable = status.is_success() || status.is_redirection();

                debug!(
                    url = %url,
                    status = status.as_u16(),
                    is_reachable = is_reachable,
                    "Connectivity test completed"
                );

                is_reachable
            }
            Err(e) => {
                debug!(
                    url = %url,
                    error = %e,
                    "Connectivity test failed"
                );
                false
            }
        }
    }

    /// Helper method to get URL with fallback logic
    async fn get_url_with_fallback(
        &self,
        specific_url_getter: impl Fn(&ServerProviderUrls) -> &Option<String>,
        path_suffix: Option<&str>,
        default_url: &str,
        url_type: &str,
    ) -> String {
        if let Some(provider) = self.get_current_provider().await {
            // Try specific URL first
            if let Some(url) = specific_url_getter(&provider.urls) {
                return url.clone();
            }

            // Fall back to base URL with path suffix
            if let Some(path) = path_suffix {
                if let Some(base) = &provider.urls.base {
                    return format!("{}/{}", base.trim_end_matches('/'), path);
                }
            }

            warn!(
                provider_id = provider.id,
                url_type = url_type,
                "No specific or base URL configured for provider, using default"
            );
        } else {
            warn!(
                url_type = url_type,
                "No current provider set, using default URL"
            );
        }

        default_url.to_string()
    }
}
