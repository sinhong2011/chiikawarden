use crate::api::{ApiAuthRepository, ApiAuthService, ApiClient};
use crate::crypto::CryptoService;
use crate::error::{AppError, AppResult};
use crate::services::{
    AuthService, MigrationService, ServerProviderService, SettingsStoreService, SyncService,
    VaultService,
};
use crate::storage::{AppDatabase, MemoryCache, SecureKeyStore};
use std::sync::Arc;
use tauri::AppHandle;
use tokio::sync::RwLock;
use tracing::{error, info};

/// Global application state that holds all services and shared resources
#[derive(Clone)]
pub struct AppState {
    pub database: Arc<AppDatabase>,
    pub memory_cache: Arc<MemoryCache>,
    pub secure_storage: Arc<SecureKeyStore>,
    pub crypto_service: Arc<CryptoService>,
    pub auth_service: Arc<AuthService>,
    pub api_auth_service: Arc<ApiAuthService>,
    pub vault_service: Arc<VaultService>,
    pub sync_service: Arc<SyncService>,
    pub settings_store_service: Arc<SettingsStoreService>,

    pub server_provider_service: Arc<ServerProviderService>,
    pub migration_service: Arc<MigrationService>,
    pub app_handle: AppHandle,
    pub initialized: Arc<RwLock<bool>>,
}

impl AppState {
    /// Initialize the application state with all services
    pub async fn new(app_handle: AppHandle) -> AppResult<Self> {
        info!("[app_state] Starting application state initialization");

        // Initialize core storage components
        info!("[app_state] Initializing core storage components");

        let database = Arc::new(AppDatabase::new(app_handle.clone()).map_err(|e| {
            error!("[app_state] Failed to initialize database: {}", e);
            AppError::DatabaseError {
                message: format!("Failed to initialize database: {}", e),
            }
        })?);
        info!("[app_state] Database component initialized");

        let memory_cache = Arc::new(MemoryCache::new(1000, 30)); // 1000 items, 30 min TTL
        info!("[app_state] Memory cache initialized (1000 items, 30min TTL)");

        let secure_storage = Arc::new(SecureKeyStore::new(&app_handle).await?);
        info!("[app_state] Secure storage initialized");

        // Initialize crypto service
        info!("[app_state] Initializing crypto service");
        let crypto_service = Arc::new(CryptoService::new());
        info!("[app_state] Crypto service initialized");

        // Initialize business services
        info!("[app_state] Initializing business services");

        let auth_service = Arc::new(AuthService::new(
            secure_storage.clone(),
            crypto_service.clone(),
        ));
        info!("[app_state] Auth service initialized");

        let vault_service = Arc::new(VaultService::new(
            database.clone(),
            memory_cache.clone(),
            crypto_service.clone(),
        ));
        info!("[app_state] Vault service initialized");

        // Initialize server provider service
        info!("[app_state] Initializing server provider service");
        let server_provider_service =
            Arc::new(ServerProviderService::new(app_handle.clone()).await?);
        info!("[app_state] Server provider service initialized");

        let sync_service = Arc::new(SyncService::new(
            app_handle.clone(),
            database.clone(),
            server_provider_service.clone(),
        ));
        info!("[app_state] Sync service initialized");

        let settings_store_service = Arc::new(
            SettingsStoreService::new(app_handle.clone())
                .await
                .map_err(|e| {
                    error!(
                        "[app_state] Failed to initialize settings store service: {}",
                        e
                    );
                    AppError::StorageError {
                        message: format!("Failed to initialize settings store service: {}", e),
                    }
                })?,
        );
        info!("[app_state] Settings store service initialized");

        // Initialize migration service
        let migration_service = Arc::new(MigrationService::new(app_handle.clone()));
        info!("[app_state] Migration service initialized");

        // Initialize API client and auth service
        info!("[app_state] Initializing API services");
        let api_client = Arc::new(ApiClient::new(
            app_handle.clone(),
            server_provider_service.clone(),
        ));
        let api_auth_repository = Arc::new(ApiAuthRepository::new(api_client));
        let api_auth_service = Arc::new(ApiAuthService::new(api_auth_repository));
        info!("[app_state] API services initialized");

        let state = Self {
            database,
            memory_cache,
            secure_storage,
            crypto_service,
            auth_service,
            api_auth_service,
            vault_service,
            sync_service,
            settings_store_service,

            server_provider_service,
            migration_service,
            app_handle,
            initialized: Arc::new(RwLock::new(false)),
        };

        // Initialize the database
        info!("[app_state] Initializing database");
        state.database.initialize().await.map_err(|e| {
            error!("[app_state] Database initialization failed: {}", e);
            AppError::DatabaseError {
                message: format!("Database initialization failed: {}", e),
            }
        })?;
        info!("[app_state] Database initialization completed");

        // Initialize the server provider service
        info!("[app_state] Initializing server provider service configuration");
        state
            .server_provider_service
            .initialize()
            .await
            .map_err(|e| {
                error!(
                    "[app_state] Server provider service initialization failed: {}",
                    e
                );
                AppError::ConfigurationError {
                    message: format!("Server provider service initialization failed: {}", e),
                }
            })?;
        info!("[app_state] Server provider service initialization completed");

        // Mark as initialized
        *state.initialized.write().await = true;

        info!("[app_state] Application state initialization completed successfully");

        Ok(state)
    }

    /// Check if the application state is fully initialized
    pub async fn is_initialized(&self) -> bool {
        *self.initialized.read().await
    }

    /// Get the database service
    pub fn database(&self) -> Arc<AppDatabase> {
        self.database.clone()
    }

    /// Get the memory cache
    pub fn memory_cache(&self) -> Arc<MemoryCache> {
        self.memory_cache.clone()
    }

    /// Get the secure storage
    pub fn secure_storage(&self) -> Arc<SecureKeyStore> {
        self.secure_storage.clone()
    }

    /// Get the crypto service
    pub fn crypto_service(&self) -> Arc<CryptoService> {
        self.crypto_service.clone()
    }

    /// Get the auth service
    pub fn auth_service(&self) -> Arc<AuthService> {
        self.auth_service.clone()
    }

    /// Get the API auth service
    pub fn api_auth_service(&self) -> Arc<ApiAuthService> {
        self.api_auth_service.clone()
    }

    /// Get the vault service
    pub fn vault_service(&self) -> Arc<VaultService> {
        self.vault_service.clone()
    }

    /// Get the sync service
    pub fn sync_service(&self) -> Arc<SyncService> {
        self.sync_service.clone()
    }

    /// Cleanup resources when shutting down
    pub async fn cleanup(&self) -> AppResult<()> {
        info!("[app_state] Starting application cleanup");

        // Clear memory cache
        self.memory_cache.clear_cache().await;
        info!("[app_state] Memory cache cleared");

        // Clear crypto cache if needed
        // self.crypto_service.clear_cache().await;

        info!("[app_state] Application cleanup completed");
        Ok(())
    }
}
