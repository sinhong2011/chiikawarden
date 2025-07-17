use serde::{Deserialize, Serialize};
use specta::Type;
use std::collections::HashMap;

/// Region enumeration for server providers
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Type)]
pub enum Region {
    US,
    EU,
    SelfHosted,
}

/// Server provider type
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Type)]
pub enum ServerProviderType {
    Preset,
    Custom,
}

/// Server provider URLs configuration
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct ServerProviderUrls {
    pub base: Option<String>,
    pub api: Option<String>,
    pub identity: Option<String>,
    pub icons: Option<String>,
    pub web_vault: Option<String>,
    pub notifications: Option<String>,
    pub events: Option<String>,
    pub key_connector: Option<String>,
    pub scim: Option<String>,
}

impl Default for ServerProviderUrls {
    fn default() -> Self {
        Self {
            base: None,
            api: None,
            identity: None,
            icons: None,
            web_vault: None,
            notifications: None,
            events: None,
            key_connector: None,
            scim: None,
        }
    }
}

/// Server provider model
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct ServerProvider {
    pub id: String,
    pub provider_type: ServerProviderType,
    pub label: String,
    pub region: Option<String>,
    pub urls: ServerProviderUrls,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

/// Server provider configuration
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct ServerProviderConfig {
    pub current_provider_id: String,
    pub providers: HashMap<String, ServerProvider>,
}

impl Default for ServerProviderConfig {
    fn default() -> Self {
        let mut providers = HashMap::new();
        let now = chrono::Utc::now();

        // Add default US cloud provider
        providers.insert(
            "us-cloud".to_string(),
            ServerProvider {
                id: "us-cloud".to_string(),
                provider_type: ServerProviderType::Preset,
                label: "Bitwarden US Cloud".to_string(),
                region: Some("US".to_string()),
                urls: ServerProviderUrls {
                    base: Some("https://bitwarden.com".to_string()),
                    api: Some("https://api.bitwarden.com".to_string()),
                    identity: Some("https://identity.bitwarden.com".to_string()),
                    icons: Some("https://icons.bitwarden.net".to_string()),
                    web_vault: Some("https://vault.bitwarden.com".to_string()),
                    notifications: Some("https://notifications.bitwarden.com".to_string()),
                    events: Some("https://events.bitwarden.com".to_string()),
                    key_connector: None,
                    scim: Some("https://scim.bitwarden.com".to_string()),
                },
                created_at: now,
                updated_at: now,
            },
        );

        // Add default EU cloud provider
        providers.insert(
            "eu-cloud".to_string(),
            ServerProvider {
                id: "eu-cloud".to_string(),
                provider_type: ServerProviderType::Preset,
                label: "Bitwarden EU Cloud".to_string(),
                region: Some("EU".to_string()),
                urls: ServerProviderUrls {
                    base: Some("https://bitwarden.eu".to_string()),
                    api: Some("https://api.bitwarden.eu".to_string()),
                    identity: Some("https://identity.bitwarden.eu".to_string()),
                    icons: Some("https://icons.bitwarden.eu".to_string()),
                    web_vault: Some("https://vault.bitwarden.eu".to_string()),
                    notifications: Some("https://notifications.bitwarden.eu".to_string()),
                    events: Some("https://events.bitwarden.eu".to_string()),
                    key_connector: None,
                    scim: Some("https://scim.bitwarden.eu".to_string()),
                },
                created_at: now,
                updated_at: now,
            },
        );

        Self {
            current_provider_id: "us-cloud".to_string(),
            providers,
        }
    }
}

impl ServerProviderConfig {
    /// Add a new custom server provider
    pub fn add_custom_provider(&mut self, label: String, base_url: String) -> String {
        let provider_id = format!("custom-{}", uuid::Uuid::new_v4());
        let now = chrono::Utc::now();

        let provider = ServerProvider {
            id: provider_id.clone(),
            provider_type: ServerProviderType::Custom,
            label,
            region: None,
            urls: ServerProviderUrls::from_base_url(base_url),
            created_at: now,
            updated_at: now,
        };

        self.providers.insert(provider_id.clone(), provider);
        provider_id
    }

    /// Add a new custom server provider with custom URLs
    pub fn add_custom_provider_with_urls(
        &mut self,
        label: String,
        urls: ServerProviderUrls,
    ) -> String {
        let provider_id = format!("custom-{}", uuid::Uuid::new_v4());
        let now = chrono::Utc::now();

        let provider = ServerProvider {
            id: provider_id.clone(),
            provider_type: ServerProviderType::Custom,
            label,
            region: None,
            urls,
            created_at: now,
            updated_at: now,
        };

        self.providers.insert(provider_id.clone(), provider);
        provider_id
    }

    /// Update an existing server provider
    pub fn update_provider(
        &mut self,
        provider_id: &str,
        label: Option<String>,
        urls: Option<ServerProviderUrls>,
    ) -> Result<(), String> {
        let provider = self
            .providers
            .get_mut(provider_id)
            .ok_or_else(|| "Provider not found".to_string())?;

        if let Some(new_label) = label {
            provider.label = new_label;
        }

        if let Some(new_urls) = urls {
            provider.urls = new_urls;
        }

        provider.updated_at = chrono::Utc::now();
        Ok(())
    }

    /// Remove a server provider
    pub fn remove_provider(&mut self, provider_id: &str) -> Result<(), String> {
        if provider_id == self.current_provider_id {
            return Err("Cannot remove the current active provider".to_string());
        }

        self.providers
            .remove(provider_id)
            .ok_or_else(|| "Provider not found".to_string())?;

        Ok(())
    }

    /// Set the current active provider
    pub fn set_current_provider(&mut self, provider_id: String) -> Result<(), String> {
        if !self.providers.contains_key(&provider_id) {
            return Err("Provider not found".to_string());
        }

        self.current_provider_id = provider_id;
        Ok(())
    }

    /// Get the current active provider
    pub fn get_current_provider(&self) -> Option<&ServerProvider> {
        self.providers.get(&self.current_provider_id)
    }

    /// Get all providers
    pub fn get_all_providers(&self) -> Vec<&ServerProvider> {
        self.providers.values().collect()
    }

    /// Get preset providers
    pub fn get_preset_providers(&self) -> Vec<&ServerProvider> {
        self.providers
            .values()
            .filter(|p| p.provider_type == ServerProviderType::Preset)
            .collect()
    }

    /// Get custom providers
    pub fn get_custom_providers(&self) -> Vec<&ServerProvider> {
        self.providers
            .values()
            .filter(|p| p.provider_type == ServerProviderType::Custom)
            .collect()
    }
}

impl ServerProviderUrls {
    /// Create URLs from a base URL
    pub fn from_base_url(base_url: String) -> Self {
        Self {
            base: Some(base_url.clone()),
            api: Some(format!("{}/api", base_url)),
            identity: Some(format!("{}/identity", base_url)),
            icons: Some(format!("{}/icons", base_url)),
            web_vault: Some(base_url.clone()),
            notifications: Some(format!("{}/notifications", base_url)),
            events: Some(format!("{}/events", base_url)),
            key_connector: None,
            scim: Some(format!("{}/scim", base_url)),
        }
    }
}

/// Server provider information for frontend
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct ServerProviderInfo {
    pub current_provider: Option<ServerProvider>,
    pub all_providers: Vec<ServerProvider>,
    pub preset_providers: Vec<ServerProvider>,
    pub custom_providers: Vec<ServerProvider>,
}

/// Trait for server provider functionality
pub trait ServerProviderTrait {
    fn get_id(&self) -> &str;
    fn get_label(&self) -> &str;
    fn get_urls(&self) -> &ServerProviderUrls;
    fn get_api_url(&self) -> String;
    fn get_identity_url(&self) -> String;
    fn get_web_vault_url(&self) -> String;
    fn get_icons_url(&self) -> String;
    fn get_notifications_url(&self) -> String;
    fn get_events_url(&self) -> String;
}

impl ServerProviderTrait for ServerProvider {
    fn get_id(&self) -> &str {
        &self.id
    }

    fn get_label(&self) -> &str {
        &self.label
    }

    fn get_urls(&self) -> &ServerProviderUrls {
        &self.urls
    }

    fn get_api_url(&self) -> String {
        self.urls.api.clone().unwrap_or_default()
    }

    fn get_identity_url(&self) -> String {
        self.urls.identity.clone().unwrap_or_default()
    }

    fn get_web_vault_url(&self) -> String {
        self.urls.web_vault.clone().unwrap_or_default()
    }

    fn get_icons_url(&self) -> String {
        self.urls.icons.clone().unwrap_or_default()
    }

    fn get_notifications_url(&self) -> String {
        self.urls.notifications.clone().unwrap_or_default()
    }

    fn get_events_url(&self) -> String {
        self.urls.events.clone().unwrap_or_default()
    }
}

/// Connectivity test results
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct ConnectivityStatus {
    pub api_reachable: bool,
    pub identity_reachable: bool,
    pub overall_status: bool,
}
