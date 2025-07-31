use crate::api::{ApiAuthRepository, ApiAuthService, ApiClient};
use crate::crypto::CryptoService;
use crate::error::{AppError, AppResult};
use crate::services::{
    AuthService, MigrationService, NetworkAwareSyncService, NetworkMonitorService,
    ServerProviderService, SessionService, SettingsStoreService, SyncService, SyncStateManager, VaultService,
    WebSocketService,
};
use crate::storage::{AppDatabase, MemoryCache, SecureKeyStore};
use std::path::PathBuf;
use std::sync::Arc;
use tauri::{AppHandle, Manager};
use tokio::sync::RwLock;
use tracing::{error, info, warn};

/// Global application state that holds all services and shared resources
#[derive(Clone)]
pub struct AppState {
    pub app_data_dir: PathBuf,
    pub database: Arc<AppDatabase>,
    pub memory_cache: Arc<MemoryCache>,
    pub secure_storage: Arc<SecureKeyStore>,
    pub token_manager: Arc<tokio::sync::RwLock<crate::crypto::token_manager::TokenManager>>,
    pub crypto_service: Arc<CryptoService>,
    pub auth_service: Arc<AuthService>,
    pub api_auth_service: Arc<ApiAuthService>,
    pub vault_service: Arc<VaultService>,
    pub sync_service: Arc<SyncService>,
    pub session_service: Arc<SessionService>,
    pub settings_store_service: Arc<SettingsStoreService>,

    // Network-aware services
    pub network_monitor: Arc<NetworkMonitorService>,
    pub sync_state_manager: Arc<SyncStateManager>,
    pub network_aware_sync_service: Arc<NetworkAwareSyncService>,
    pub websocket_service: Arc<WebSocketService>,

    pub server_provider_service: Arc<ServerProviderService>,
    pub migration_service: Arc<MigrationService>,
    pub app_handle: AppHandle,
    pub initialized: Arc<RwLock<bool>>,
}

impl AppState {
    /// Initialize the application state with all services
    pub async fn new(app_handle: AppHandle) -> AppResult<Self> {
        info!("[app_state] Starting application state initialization");

        // Get app data directory
        let app_data_dir = app_handle.path().app_data_dir().map_err(|e| {
            error!("[app_state] Failed to get app data directory: {}", e);
            AppError::InternalError {
                message: format!("Failed to get app data directory: {}", e),
            }
        })?;

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

        let secure_storage = Arc::new(SecureKeyStore::new("chiikawarden".to_string(), app_data_dir.clone()));
        info!("[app_state] Secure storage initialized");

        // Initialize crypto service
        info!("[app_state] Initializing crypto service");
        let crypto_service = Arc::new(CryptoService::new());
        info!("[app_state] Crypto service initialized");

        // Initialize server provider service first (needed for API client)
        info!("[app_state] Initializing server provider service");
        let server_provider_service =
            Arc::new(ServerProviderService::new(app_handle.clone()).await?);
        info!("[app_state] Server provider service initialized");

        // Initialize API client (needed for auth service)
        info!("[app_state] Initializing API client");
        let api_client = Arc::new(ApiClient::new(
            app_handle.clone(),
            server_provider_service.clone(),
        ));
        info!("[app_state] API client initialized");

        // Initialize business services
        info!("[app_state] Initializing  business services");

        let auth_service = Arc::new(AuthService::new(
            secure_storage.clone(),
            crypto_service.clone(),
            database.clone(),
            api_client.clone(),
            server_provider_service.clone(),
        ));
        info!("[app_state] Auth service initialized");

        let vault_service = Arc::new(VaultService::new(
            database.clone(),
            memory_cache.clone(),
            crypto_service.clone(),
        ));
        info!("[app_state] Vault service initialized");

        // Initialize API auth service (using existing API client)
        info!("[app_state] Initializing API auth service");
        let api_auth_repository = Arc::new(ApiAuthRepository::new(
            api_client.clone(),
            app_handle.clone(),
        ));
        let api_auth_service = Arc::new(ApiAuthService::new(api_auth_repository));
        info!("[app_state] API auth service initialized");

        // Initialize token manager with stronghold storage
        info!("[app_state] Initializing token manager");
        let mut token_manager = crate::crypto::token_manager::TokenManager::new(app_handle.clone());
        token_manager.set_auth_service(api_auth_service.clone());
        let token_manager = Arc::new(tokio::sync::RwLock::new(token_manager));
        info!("[app_state] Token manager initialized");

        let sync_service = Arc::new(SyncService::new(
            app_handle.clone(),
            database.clone(),
            server_provider_service.clone(),
            token_manager.clone(),
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



        // Initialize session service
        let session_service = Arc::new(SessionService::new(database.clone()));
        info!("[app_state] Session service initialized");

        // Initialize network-aware services
        info!("[app_state] Initializing network-aware services");

        let network_monitor = Arc::new(
            NetworkMonitorService::new(app_handle.clone(), server_provider_service.clone())
                .await
                .map_err(|e| {
                    error!("[app_state] Failed to initialize network monitor: {}", e);
                    AppError::InternalError {
                        message: format!("Failed to initialize network monitor: {}", e),
                    }
                })?,
        );
        info!("[app_state] Network monitor service initialized");

        let sync_state_manager = Arc::new(SyncStateManager::new(
            app_handle.clone(),
            database.clone(),
            network_monitor.clone(),
        ));
        info!("[app_state] Sync state manager initialized");

        let network_aware_sync_service = Arc::new(NetworkAwareSyncService::new(
            app_handle.clone(),
            database.clone(),
            server_provider_service.clone(),
            network_monitor.clone(),
            sync_state_manager.clone(),
            token_manager.clone(),
        ));
        info!("[app_state] Network-aware sync service initialized");

        let websocket_service = Arc::new(WebSocketService::new(
            app_handle.clone(),
            server_provider_service.clone(),
            network_monitor.clone(),
            sync_state_manager.clone(),
        ));
        info!("[app_state] WebSocket service initialized");

        let state = Self {
            app_data_dir,
            database,
            memory_cache,
            secure_storage,
            token_manager,
            crypto_service,
            auth_service,
            api_auth_service,
            vault_service,
            sync_service,
            session_service,
            settings_store_service,

            // Network-aware services
            network_monitor,
            sync_state_manager,
            network_aware_sync_service,
            websocket_service,

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

        // Initialize network-aware services
        info!("[app_state] Starting network monitoring");
        state
            .network_monitor
            .start_monitoring()
            .await
            .map_err(|e| {
                error!("[app_state] Failed to start network monitoring: {}", e);
                AppError::InternalError {
                    message: format!("Failed to start network monitoring: {}", e),
                }
            })?;
        info!("[app_state] Network monitoring started");

        info!("[app_state] Initializing sync state manager");
        state.sync_state_manager.initialize().await.map_err(|e| {
            error!("[app_state] Failed to initialize sync state manager: {}", e);
            AppError::InternalError {
                message: format!("Failed to initialize sync state manager: {}", e),
            }
        })?;
        info!("[app_state] Sync state manager initialized");

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

    /// Get the token manager
    pub fn token_manager(&self) -> Arc<tokio::sync::RwLock<crate::crypto::token_manager::TokenManager>> {
        self.token_manager.clone()
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

    /// Get the session service
    pub fn session_service(&self) -> Arc<SessionService> {
        self.session_service.clone()
    }

    /// Get the network monitor service
    pub fn network_monitor(&self) -> Arc<NetworkMonitorService> {
        self.network_monitor.clone()
    }

    /// Get the sync state manager
    pub fn sync_state_manager(&self) -> Arc<SyncStateManager> {
        self.sync_state_manager.clone()
    }

    /// Get the network-aware sync service
    pub fn network_aware_sync_service(&self) -> Arc<NetworkAwareSyncService> {
        self.network_aware_sync_service.clone()
    }

    /// Get the WebSocket service
    pub fn websocket_service(&self) -> Arc<WebSocketService> {
        self.websocket_service.clone()
    }

    /// Cleanup resources when shutting down
    pub async fn cleanup(&self) -> AppResult<()> {
        info!("[app_state] Starting application cleanup");

        // Stop network monitoring
        self.network_monitor.stop_monitoring().await;
        info!("[app_state] Network monitoring stopped");

        // Disconnect WebSocket
        if let Err(e) = self.websocket_service.disconnect().await {
            warn!(
                "[app_state] Failed to disconnect WebSocket during cleanup: {}",
                e
            );
        }
        info!("[app_state] WebSocket disconnected");

        // Clear sync state cache
        self.sync_state_manager.clear_all_cache().await;
        info!("[app_state] Sync state cache cleared");

        // Clear memory cache
        self.memory_cache.clear_cache().await;
        info!("[app_state] Memory cache cleared");

        // Clear crypto cache if needed
        // self.crypto_service.clear_cache().await;

        info!("[app_state] Application cleanup completed");
        Ok(())
    }
}
