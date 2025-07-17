use crate::error::{AppError, AppResult};
use crate::models::{
    Region, ServerProvider, ServerProviderConfig, ServerProviderType, ServerProviderUrls,
};
use crate::services::ServerProviderService;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tauri::AppHandle;
use tauri_plugin_store::StoreExt;
use tracing::{debug, info, warn};

/// Legacy environment state from database
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LegacyEnvironmentState {
    pub region: Region,
    pub custom_environment_urls: Option<LegacyEnvironmentUrls>,
}

/// Legacy environment URLs from database
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LegacyEnvironmentUrls {
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

/// Migration service for converting legacy environment data to server provider format
pub struct MigrationService {
    app_handle: AppHandle,
}

impl MigrationService {
    /// Create a new migration service
    pub fn new(app_handle: AppHandle) -> Self {
        Self { app_handle }
    }

    /// Migrate legacy environment data to server provider format
    pub async fn migrate_environment_to_server_provider(
        &self,
        server_provider_service: Arc<ServerProviderService>,
    ) -> AppResult<()> {
        info!("Starting migration from legacy environment to server provider format");

        // Check if migration has already been completed
        if self.is_migration_completed().await? {
            debug!("Migration already completed, skipping");
            return Ok(());
        }

        // Load legacy environment data from database
        let legacy_data = self.load_legacy_environment_data().await?;

        if let Some(legacy_state) = legacy_data {
            info!("Found legacy environment data, migrating...");

            // Convert legacy data to server provider format
            let migration_result = self.convert_legacy_to_server_provider(legacy_state).await?;

            // Apply migration to server provider service
            self.apply_migration(server_provider_service, migration_result)
                .await?;

            // Mark migration as completed
            self.mark_migration_completed().await?;

            info!("Migration completed successfully");
        } else {
            debug!("No legacy environment data found, migration not needed");
            // Still mark as completed to avoid future checks
            self.mark_migration_completed().await?;
        }

        Ok(())
    }

    /// Check if migration has already been completed
    async fn is_migration_completed(&self) -> AppResult<bool> {
        let store = self
            .app_handle
            .store("migration-status.json")
            .map_err(|e| AppError::DatabaseError {
                message: format!("Failed to initialize migration status store: {}", e),
            })?;

        match store.get("environment_to_server_provider_completed") {
            Some(value) => Ok(value.as_bool().unwrap_or(false)),
            None => Ok(false),
        }
    }

    /// Mark migration as completed
    async fn mark_migration_completed(&self) -> AppResult<()> {
        let store = self
            .app_handle
            .store("migration-status.json")
            .map_err(|e| AppError::DatabaseError {
                message: format!("Failed to initialize migration status store: {}", e),
            })?;

        store.set(
            "environment_to_server_provider_completed",
            serde_json::Value::Bool(true),
        );
        store.save().map_err(|e| AppError::DatabaseError {
            message: format!("Failed to save migration status: {}", e),
        })?;

        Ok(())
    }

    /// Load legacy environment data from database
    async fn load_legacy_environment_data(&self) -> AppResult<Option<LegacyEnvironmentState>> {
        // This would typically query the SQLite database for environment_state table
        // For now, we'll return None since we don't have access to the database here
        // In a real implementation, you would:
        // 1. Connect to the SQLite database
        // 2. Query the environment_state table
        // 3. Deserialize the data into LegacyEnvironmentState

        warn!("Legacy environment data loading not implemented - would query SQLite database");
        Ok(None)
    }

    /// Convert legacy environment state to server provider format
    async fn convert_legacy_to_server_provider(
        &self,
        legacy_state: LegacyEnvironmentState,
    ) -> AppResult<ServerProviderConfig> {
        debug!("Converting legacy environment state to server provider format");

        let mut config = ServerProviderConfig::default();
        let now = chrono::Utc::now();

        match legacy_state.region {
            Region::US => {
                // Already have US provider in default config
                config.current_provider_id = "us-cloud".to_string();
            }
            Region::EU => {
                // Already have EU provider in default config
                config.current_provider_id = "eu-cloud".to_string();
            }
            Region::SelfHosted => {
                // Create custom provider from legacy URLs
                if let Some(legacy_urls) = legacy_state.custom_environment_urls {
                    let custom_provider = ServerProvider {
                        id: "migrated-custom".to_string(),
                        provider_type: ServerProviderType::Custom,
                        label: "Migrated Custom Server".to_string(),
                        region: None,
                        urls: ServerProviderUrls {
                            base: legacy_urls.base,
                            api: legacy_urls.api,
                            identity: legacy_urls.identity,
                            icons: legacy_urls.icons,
                            web_vault: legacy_urls.web_vault,
                            notifications: legacy_urls.notifications,
                            events: legacy_urls.events,
                            key_connector: legacy_urls.key_connector,
                            scim: legacy_urls.scim,
                        },
                        created_at: now,
                        updated_at: now,
                    };

                    config
                        .providers
                        .insert("migrated-custom".to_string(), custom_provider);
                    config.current_provider_id = "migrated-custom".to_string();
                } else {
                    warn!("Self-hosted region found but no custom URLs, defaulting to US");
                    config.current_provider_id = "us-cloud".to_string();
                }
            }
        }

        Ok(config)
    }

    /// Apply migration result to server provider service
    async fn apply_migration(
        &self,
        server_provider_service: Arc<ServerProviderService>,
        migration_config: ServerProviderConfig,
    ) -> AppResult<()> {
        debug!("Applying migration to server provider service");

        // Add any custom providers from migration
        for (provider_id, provider) in migration_config.providers.iter() {
            if provider.provider_type == ServerProviderType::Custom {
                info!(
                    provider_id = provider_id,
                    provider_label = provider.label,
                    "Adding migrated custom provider"
                );

                // Add the custom provider
                let new_provider_id = server_provider_service
                    .add_custom_provider_with_urls(provider.label.clone(), provider.urls.clone())
                    .await?;

                // If this was the current provider, set it as current
                if migration_config.current_provider_id == *provider_id {
                    server_provider_service
                        .set_current_provider(new_provider_id)
                        .await?;
                }
            }
        }

        // Set current provider if it's a preset provider
        if migration_config
            .providers
            .get(&migration_config.current_provider_id)
            .map(|p| p.provider_type == ServerProviderType::Preset)
            .unwrap_or(false)
        {
            server_provider_service
                .set_current_provider(migration_config.current_provider_id)
                .await?;
        }

        Ok(())
    }

    /// Get migration status for debugging
    pub async fn get_migration_status(&self) -> AppResult<MigrationStatus> {
        let is_completed = self.is_migration_completed().await?;

        Ok(MigrationStatus {
            environment_to_server_provider_completed: is_completed,
        })
    }
}

/// Migration status information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MigrationStatus {
    pub environment_to_server_provider_completed: bool,
}
