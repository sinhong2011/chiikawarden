use crate::error::{AppError, AppResult};
use crate::logging::log_database_operation;
use crate::models::{user::User, Cipher, Collection, Folder, SyncState};
use chrono::{DateTime, Utc};
use regex::Regex;
use serde_json::Value;
use sqlx::{sqlite::SqlitePool, Column, Row, ValueRef};
use std::sync::Arc;
use tauri::AppHandle;
use tauri::Manager;
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

/// Database service for managing app data using SQLx
pub struct AppDatabase {
    pool: Arc<SqlitePool>,
    initialized: Arc<RwLock<bool>>,
    db_path: String,
}

impl AppDatabase {
    pub fn new(app_handle: AppHandle) -> AppResult<Self> {
        let app_data_dir =
            app_handle
                .path()
                .app_data_dir()
                .map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to get app data directory: {}", e),
                })?;

        // Ensure the app data directory exists
        std::fs::create_dir_all(&app_data_dir).map_err(|e| AppError::DatabaseError {
            message: format!("Failed to create app data directory: {}", e),
        })?;

        let db_path = app_data_dir.join("chiikawarden.db");

        // Create the database file if it doesn't exist
        if !db_path.exists() {
            std::fs::File::create(&db_path).map_err(|e| AppError::DatabaseError {
                message: format!("Failed to create database file: {}", e),
            })?;
        }

        // Use proper SQLite connection string format
        let connection_string = format!("sqlite://{}?mode=rwc", db_path.display());

        // Configure connection pool for high concurrency
        let pool = sqlx::sqlite::SqlitePoolOptions::new()
            .max_connections(50) // Increase from default 10
            .min_connections(5) // Keep some connections warm
            .acquire_timeout(std::time::Duration::from_secs(30)) // Increase timeout
            .idle_timeout(std::time::Duration::from_secs(600)) // 10 minutes
            .max_lifetime(std::time::Duration::from_secs(1800)) // 30 minutes
            .connect_lazy(&connection_string)
            .map_err(|e| AppError::DatabaseError {
                message: format!("Failed to create database connection pool: {}", e),
            })?;

        Ok(Self {
            pool: Arc::new(pool),
            initialized: Arc::new(RwLock::new(false)),
            db_path: db_path.to_string_lossy().to_string(),
        })
    }

    /// Extract table name from SQL query for logging purposes
    fn extract_table_name(query: &str) -> String {
        // Normalize the query by removing extra whitespace and converting to lowercase
        let normalized = query.trim().to_lowercase();

        // Use regex patterns to extract table names from different SQL operations
        lazy_static::lazy_static! {
            static ref SELECT_REGEX: Regex = Regex::new(r"select\s+.*?\s+from\s+(\w+)").unwrap();
            static ref INSERT_REGEX: Regex = Regex::new(r"insert\s+(?:or\s+replace\s+)?into\s+(\w+)").unwrap();
            static ref UPDATE_REGEX: Regex = Regex::new(r"update\s+(\w+)\s+set").unwrap();
            static ref DELETE_REGEX: Regex = Regex::new(r"delete\s+from\s+(\w+)").unwrap();
        }

        // Try to match different SQL patterns
        if let Some(captures) = SELECT_REGEX.captures(&normalized) {
            if let Some(table) = captures.get(1) {
                return table.as_str().to_string();
            }
        }

        if let Some(captures) = INSERT_REGEX.captures(&normalized) {
            if let Some(table) = captures.get(1) {
                return table.as_str().to_string();
            }
        }

        if let Some(captures) = UPDATE_REGEX.captures(&normalized) {
            if let Some(table) = captures.get(1) {
                return table.as_str().to_string();
            }
        }

        if let Some(captures) = DELETE_REGEX.captures(&normalized) {
            if let Some(table) = captures.get(1) {
                return table.as_str().to_string();
            }
        }

        // If no pattern matches, return "unknown"
        "unknown".to_string()
    }

    #[cfg(test)]
    fn test_extract_table_name() {
        // Test SELECT queries
        assert_eq!(Self::extract_table_name("SELECT * FROM users"), "users");
        assert_eq!(
            Self::extract_table_name("select id, name from ciphers where user_id = ?"),
            "ciphers"
        );

        // Test INSERT queries
        assert_eq!(
            Self::extract_table_name("INSERT INTO users (name) VALUES (?)"),
            "users"
        );
        assert_eq!(
            Self::extract_table_name("INSERT OR REPLACE INTO ciphers (id, name) VALUES (?, ?)"),
            "ciphers"
        );

        // Test UPDATE queries
        assert_eq!(
            Self::extract_table_name("UPDATE users SET name = ? WHERE id = ?"),
            "users"
        );

        // Test DELETE queries
        assert_eq!(
            Self::extract_table_name("DELETE FROM ciphers WHERE id = ?"),
            "ciphers"
        );

        // Test unknown patterns
        assert_eq!(
            Self::extract_table_name("PRAGMA table_info(users)"),
            "unknown"
        );
        assert_eq!(
            Self::extract_table_name("CREATE TABLE test (id INTEGER)"),
            "unknown"
        );
    }

    /// Initialize the database with proper setup
    pub async fn initialize(&self) -> AppResult<()> {
        use std::time::Instant;

        let start_time = Instant::now();
        info!(db_path = %self.db_path, "Starting database initialization");

        let mut initialized = self.initialized.write().await;
        if *initialized {
            debug!("Database already initialized");
            return Ok(());
        }

        // Test basic connection
        debug!("Testing database connection");
        self.check_connection().await.map_err(|e| {
            error!(error = %e, "Database connection test failed");
            AppError::DatabaseError {
                message: format!("Database connection test failed: {}", e),
            }
        })?;
        debug!("Database connection test passed");

        // Check if we can migrate safely (in production)
        #[cfg(not(debug_assertions))]
        {
            debug!("Checking migration safety");
            let migration_runner = super::migrations::MigrationRunner::new();
            let can_migrate = migration_runner.can_migrate_safely(&*self.pool).await?;

            if !can_migrate {
                error!("Database migration safety check failed");
                return Err(AppError::DatabaseError {
                    message:
                        "Database migration safety check failed. Manual intervention required."
                            .to_string(),
                });
            }
            debug!("Migration safety check passed");
        }

        // Run migrations with enhanced logging
        debug!("Running database migrations");
        self.run_migrations().await.map_err(|e| {
            error!(error = %e, "Database migration failed");
            AppError::DatabaseError {
                message: format!("Migration failed: {}", e),
            }
        })?;

        // Perform post-migration health check
        debug!("Performing post-migration health check");
        match self.check_health().await {
            Ok(health) => match health.overall_status {
                super::health::HealthStatus::Healthy => {
                    debug!("Database health check passed");
                }
                super::health::HealthStatus::Warning => {
                    warn!(
                        recommendations = ?health.recommendations,
                        "Database health check completed with warnings"
                    );
                }
                _ => {
                    error!(
                        status = ?health.overall_status,
                        recommendations = ?health.recommendations,
                        "Database health check failed"
                    );
                    return Err(AppError::DatabaseError {
                        message: "Database health check failed after initialization".to_string(),
                    });
                }
            },
            Err(e) => {
                warn!(error = %e, "Failed to run health check, continuing with initialization");
            }
        }

        // Apply SQLite performance optimizations
        debug!("Applying SQLite performance optimizations");
        self.apply_performance_optimizations().await?;

        // Settings initialization is now handled by SettingsStoreService

        *initialized = true;
        let duration = start_time.elapsed();
        info!(
            db_path = %self.db_path,
            duration_ms = duration.as_millis(),
            "Database initialized successfully"
        );
        Ok(())
    }

    /// Run database migrations using the MigrationRunner
    async fn run_migrations(&self) -> AppResult<()> {
        let migration_runner = super::migrations::MigrationRunner::new();
        migration_runner.run_migrations(&*self.pool).await
    }

    /// Apply SQLite performance optimizations
    async fn apply_performance_optimizations(&self) -> AppResult<()> {
        debug!("Applying SQLite performance optimizations");

        // Set optimized PRAGMA settings for high concurrency
        let optimizations = vec![
            "PRAGMA synchronous = NORMAL",      // Balance safety and performance
            "PRAGMA journal_mode = WAL",        // Write-Ahead Logging for better concurrency
            "PRAGMA cache_size = -64000",       // 64MB cache (negative = KB)
            "PRAGMA temp_store = MEMORY",       // Store temp tables in memory
            "PRAGMA mmap_size = 268435456",     // 256MB memory-mapped I/O
            "PRAGMA busy_timeout = 30000",      // 30 second busy timeout
            "PRAGMA wal_autocheckpoint = 1000", // Checkpoint every 1000 pages
        ];

        for pragma in optimizations {
            sqlx::query(pragma)
                .execute(&*self.pool)
                .await
                .map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to apply optimization '{}': {}", pragma, e),
                })?;
            debug!("Applied: {}", pragma);
        }

        info!("SQLite performance optimizations applied successfully");
        Ok(())
    }

    /// Execute a query using SQLx
    pub async fn execute_query(&self, query: &str, params: Vec<Value>) -> AppResult<Value> {
        debug!(
            query = query,
            params_count = params.len(),
            "Executing database query"
        );

        let mut query_builder = sqlx::query(query);

        for param in params {
            query_builder = match param {
                Value::Null => query_builder.bind(None::<String>),
                Value::Bool(b) => query_builder.bind(b),
                Value::Number(n) => {
                    if let Some(i) = n.as_i64() {
                        query_builder.bind(i)
                    } else if let Some(f) = n.as_f64() {
                        query_builder.bind(f)
                    } else {
                        query_builder.bind(None::<String>)
                    }
                }
                Value::String(s) => query_builder.bind(s),
                _ => query_builder.bind(param.to_string()),
            };
        }

        let table_name = Self::extract_table_name(query);

        let result = query_builder.execute(&*self.pool).await.map_err(|e| {
            error!(
                query = query,
                error = %e,
                "Database execute query failed"
            );
            log_database_operation("execute", &table_name, false, Some(&e.to_string()));
            AppError::DatabaseError {
                message: format!("Database execute failed: {}", e),
            }
        })?;

        let rows_affected = result.rows_affected();
        let last_insert_id = result.last_insert_rowid();

        debug!(
            query = query,
            rows_affected = rows_affected,
            last_insert_id = last_insert_id,
            "Database query executed successfully"
        );

        log_database_operation("execute", &table_name, true, None);

        Ok(serde_json::json!({
            "rows_affected": rows_affected,
            "last_insert_id": last_insert_id
        }))
    }

    /// Execute a select query using SQLx
    pub async fn select_query(&self, query: &str, params: Vec<Value>) -> AppResult<Value> {
        debug!(
            query = query,
            params_count = params.len(),
            "Executing database select query"
        );

        let mut query_builder = sqlx::query(query);

        for param in params {
            query_builder = match param {
                Value::Null => query_builder.bind(None::<String>),
                Value::Bool(b) => query_builder.bind(b),
                Value::Number(n) => {
                    if let Some(i) = n.as_i64() {
                        query_builder.bind(i)
                    } else if let Some(f) = n.as_f64() {
                        query_builder.bind(f)
                    } else {
                        query_builder.bind(None::<String>)
                    }
                }
                Value::String(s) => query_builder.bind(s),
                _ => query_builder.bind(param.to_string()),
            };
        }

        let table_name = Self::extract_table_name(query);

        let rows = query_builder.fetch_all(&*self.pool).await.map_err(|e| {
            error!(
                query = query,
                error = %e,
                "Database select query failed"
            );
            log_database_operation("select", &table_name, false, Some(&e.to_string()));
            AppError::DatabaseError {
                message: format!("Database select failed: {}", e),
            }
        })?;

        let mut json_rows = Vec::new();
        for row in rows {
            let mut row_map = serde_json::Map::new();
            for (i, column) in row.columns().iter().enumerate() {
                let column_name = column.name();
                let value = self.extract_column_value(&row, i, column.type_info())?;
                row_map.insert(column_name.to_string(), value);
            }
            json_rows.push(Value::Object(row_map));
        }

        debug!(
            query = query,
            rows_returned = json_rows.len(),
            "Database select query executed successfully"
        );

        log_database_operation("select", &table_name, true, None);

        Ok(Value::Array(json_rows))
    }

    /// Extract column value from SQLx row
    fn extract_column_value(
        &self,
        row: &sqlx::sqlite::SqliteRow,
        index: usize,
        type_info: &sqlx::sqlite::SqliteTypeInfo,
    ) -> AppResult<Value> {
        use sqlx::TypeInfo;

        if row
            .try_get_raw(index)
            .map_err(|e| AppError::DatabaseError {
                message: format!("Failed to get raw value: {}", e),
            })?
            .is_null()
        {
            return Ok(Value::Null);
        }

        match type_info.name() {
            "BOOLEAN" => {
                let val: bool = row.try_get(index).map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to get boolean value: {}", e),
                })?;
                Ok(Value::Bool(val))
            }
            "INTEGER" => {
                let val: i64 = row.try_get(index).map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to get integer value: {}", e),
                })?;
                Ok(Value::Number(val.into()))
            }
            "REAL" => {
                let val: f64 = row.try_get(index).map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to get real value: {}", e),
                })?;
                Ok(Value::Number(
                    serde_json::Number::from_f64(val).unwrap_or(0.into()),
                ))
            }
            "TEXT" => {
                let val: String = row.try_get(index).map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to get text value: {}", e),
                })?;
                Ok(Value::String(val))
            }
            "DATETIME" => {
                let val: String = row.try_get(index).map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to get datetime value: {}", e),
                })?;
                Ok(Value::String(val))
            }
            _ => {
                // Default to string for unknown types
                let val: String = row.try_get(index).map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to get value as string: {}", e),
                })?;
                Ok(Value::String(val))
            }
        }
    }

    /// Check if database is initialized
    pub async fn is_initialized(&self) -> bool {
        *self.initialized.read().await
    }

    /// Perform comprehensive database health check
    pub async fn check_health(&self) -> AppResult<super::health::DatabaseHealth> {
        super::health::DatabaseHealthChecker::check_health(&*self.pool).await
    }

    /// Development utilities (only available in debug builds)
    #[cfg(debug_assertions)]
    pub async fn reset_database(&self) -> AppResult<()> {
        super::dev_utils::DatabaseDevUtils::reset_database(&*self.pool).await
    }

    #[cfg(debug_assertions)]
    pub async fn inspect_schema(&self) -> AppResult<super::dev_utils::SchemaInfo> {
        super::dev_utils::DatabaseDevUtils::inspect_schema(&*self.pool).await
    }

    #[cfg(debug_assertions)]
    pub async fn collect_statistics(&self) -> AppResult<super::dev_utils::DatabaseStats> {
        super::dev_utils::DatabaseDevUtils::collect_statistics(&*self.pool).await
    }

    #[cfg(debug_assertions)]
    pub async fn optimize_database(&self) -> AppResult<()> {
        super::dev_utils::DatabaseDevUtils::optimize_database(&*self.pool).await
    }

    #[cfg(debug_assertions)]
    pub async fn generate_sample_data(&self) -> AppResult<()> {
        super::dev_utils::DatabaseDevUtils::generate_sample_data(&*self.pool).await
    }

    /// Get database file path
    pub fn get_db_path(&self) -> &str {
        &self.db_path
    }

    // Helper method to parse result arrays
    fn parse_result_array<T, F>(&self, result: Value, parser: F) -> AppResult<Vec<T>>
    where
        F: Fn(&Value) -> AppResult<T>,
    {
        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Invalid result format".to_string(),
        })?;

        let mut items = Vec::new();
        for row in rows {
            let item = parser(row)?;
            items.push(item);
        }
        Ok(items)
    }

    // Database maintenance methods
    async fn check_connection(&self) -> AppResult<()> {
        // Test basic SQLite connection and functionality
        let result = sqlx::query_scalar::<_, i32>("SELECT 1")
            .fetch_one(&*self.pool)
            .await
            .map_err(|e| AppError::DatabaseError {
                message: format!("Database connection test failed: {}", e),
            })?;

        if result != 1 {
            return Err(AppError::DatabaseError {
                message: "Database connection test returned unexpected result".to_string(),
            });
        }

        Ok(())
    }

    // Settings functionality has been moved to SettingsStoreService using tauri-plugin-store
    // Legacy methods removed to avoid confusion

    /// User management
    pub async fn create_user(&self, user: &User) -> AppResult<()> {
        use crate::storage::database::queries::sql;

        self.execute_query(
            sql::CREATE_USER,
            vec![
                Value::String(user.id.clone()),
                Value::String(user.email.clone()),
                user.master_key_hash
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                user.encrypted_private_key_new
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                user.encrypted_user_key_new
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                Value::String(user.key_derivation_method.clone()),
                Value::Number((if user.device_trust_enabled { 1 } else { 0 }).into()),
                Value::Number((if user.webauthn_enabled { 1 } else { 0 }).into()),
                Value::String(user.server_provider_id.clone()),
                Value::Number(user.kdf_type.into()),
                Value::Number(user.kdf_iterations.into()),
                user.kdf_memory
                    .map(|n| Value::Number(n.into()))
                    .unwrap_or(Value::Null),
                user.kdf_parallelism
                    .map(|n| Value::Number(n.into()))
                    .unwrap_or(Value::Null),
                Value::String(user.created_date.to_rfc3339()),
                Value::String(user.revision_date.to_rfc3339()),
            ],
        )
        .await?;
        Ok(())
    }

    pub async fn get_user_by_email(&self, email: &str) -> AppResult<User> {
        use crate::storage::database::queries::sql;

        let result = self
            .select_query(
                sql::GET_USER_BY_EMAIL,
                vec![Value::String(email.to_string())],
            )
            .await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Invalid result format".to_string(),
        })?;

        if rows.is_empty() {
            return Err(AppError::DatabaseError {
                message: format!("User with email '{}' not found", email),
            });
        }

        let row = &rows[0];
        User::from_database_row(row)
    }

    pub async fn get_user_by_id(&self, user_id: &str) -> AppResult<User> {
        use crate::storage::database::queries::sql;

        let result = self
            .select_query(
                sql::GET_USER_BY_ID,
                vec![Value::String(user_id.to_string())],
            )
            .await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Invalid result format".to_string(),
        })?;

        if rows.is_empty() {
            return Err(AppError::DatabaseError {
                message: format!("User with ID '{}' not found", user_id),
            });
        }

        let row = &rows[0];
        User::from_database_row(row)
    }

    pub async fn get_all_users(&self) -> AppResult<Vec<User>> {
        use crate::storage::database::queries::sql;

        let result = self.select_query(sql::GET_ALL_USERS, vec![]).await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Invalid result format".to_string(),
        })?;

        let mut users = Vec::new();
        for row in rows {
            users.push(User::from_database_row(row)?);
        }

        Ok(users)
    }

    pub async fn update_user(&self, user: &User) -> AppResult<()> {
        use crate::storage::database::queries::sql;

        self.execute_query(
            sql::UPDATE_USER,
            vec![
                Value::String(user.email.clone()),
                user.master_key_hash
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                user.encrypted_private_key_new
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                user.encrypted_user_key_new
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                Value::String(user.key_derivation_method.clone()),
                Value::Number((if user.device_trust_enabled { 1 } else { 0 }).into()),
                Value::Number((if user.webauthn_enabled { 1 } else { 0 }).into()),
                Value::String(user.server_provider_id.clone()),
                Value::Number(user.kdf_type.into()),
                Value::Number(user.kdf_iterations.into()),
                user.kdf_memory
                    .map(|n| Value::Number(n.into()))
                    .unwrap_or(Value::Null),
                user.kdf_parallelism
                    .map(|n| Value::Number(n.into()))
                    .unwrap_or(Value::Null),
                Value::String(user.revision_date.to_rfc3339()),
                Value::String(user.id.clone()),
            ],
        )
        .await?;
        Ok(())
    }

    pub async fn upsert_user(&self, user: &User) -> AppResult<()> {
        use crate::storage::database::queries::sql;

        self.execute_query(
            sql::UPSERT_USER,
            vec![
                Value::String(user.id.clone()),
                Value::String(user.email.clone()),
                user.master_key_hash
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                user.encrypted_private_key_new
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                user.encrypted_user_key_new
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                Value::String(user.key_derivation_method.clone()),
                Value::Number((if user.device_trust_enabled { 1 } else { 0 }).into()),
                Value::Number((if user.webauthn_enabled { 1 } else { 0 }).into()),
                Value::String(user.server_provider_id.clone()),
                Value::Number(user.kdf_type.into()),
                Value::Number(user.kdf_iterations.into()),
                user.kdf_memory
                    .map(|n| Value::Number(n.into()))
                    .unwrap_or(Value::Null),
                user.kdf_parallelism
                    .map(|n| Value::Number(n.into()))
                    .unwrap_or(Value::Null),
                Value::String(user.created_date.to_rfc3339()),
                Value::String(user.revision_date.to_rfc3339()),
            ],
        )
        .await?;
        Ok(())
    }

    /// Sync state management
    pub async fn get_sync_state(&self, user_id: &str) -> AppResult<Option<SyncState>> {
        let query = r#"
            SELECT
                user_id, last_sync, revision_date, is_syncing,
                last_websocket_connection, websocket_connected,
                background_sync_enabled, sync_interval_hours,
                last_server_notification, server_revision_date,
                last_online_sync, cached_items_count, network_state
            FROM sync_state
            WHERE user_id = ?
        "#;
        let result = self
            .select_query(query, vec![Value::String(user_id.to_string())])
            .await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Invalid result format".to_string(),
        })?;

        if rows.is_empty() {
            return Ok(None);
        }

        let row = &rows[0];
        SyncState::from_database_row(row).map(Some)
    }

    pub async fn save_sync_state(&self, sync_state: &SyncState) -> AppResult<()> {
        let last_sync = sync_state.last_sync.map(|dt| dt.to_rfc3339());
        let revision_date = sync_state.revision_date.map(|dt| dt.to_rfc3339());
        let last_websocket_connection = sync_state
            .last_websocket_connection
            .map(|dt| dt.to_rfc3339());
        let last_server_notification = sync_state
            .last_server_notification
            .map(|dt| dt.to_rfc3339());
        let server_revision_date = sync_state.server_revision_date.map(|dt| dt.to_rfc3339());
        let last_online_sync = sync_state.last_online_sync.map(|dt| dt.to_rfc3339());

        let query = r#"
            INSERT OR REPLACE INTO sync_state (
                user_id, last_sync, revision_date, is_syncing,
                last_websocket_connection, websocket_connected,
                background_sync_enabled, sync_interval_hours,
                last_server_notification, server_revision_date,
                last_online_sync, cached_items_count, network_state
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        "#;

        self.execute_query(
            query,
            vec![
                Value::String(sync_state.user_id.clone()),
                last_sync.map(Value::String).unwrap_or(Value::Null),
                revision_date.map(Value::String).unwrap_or(Value::Null),
                Value::Bool(sync_state.is_syncing),
                last_websocket_connection
                    .map(Value::String)
                    .unwrap_or(Value::Null),
                Value::Bool(sync_state.websocket_connected),
                Value::Bool(sync_state.background_sync_enabled),
                Value::Number(serde_json::Number::from(sync_state.sync_interval_hours)),
                last_server_notification
                    .map(Value::String)
                    .unwrap_or(Value::Null),
                server_revision_date
                    .map(Value::String)
                    .unwrap_or(Value::Null),
                last_online_sync.map(Value::String).unwrap_or(Value::Null),
                Value::Number(serde_json::Number::from(sync_state.cached_items_count)),
                Value::String(sync_state.network_state.clone()),
            ],
        )
        .await?;
        Ok(())
    }

    pub async fn clear_sync_state(&self, user_id: &str) -> AppResult<()> {
        let query = "DELETE FROM sync_state WHERE user_id = ?";
        self.execute_query(query, vec![Value::String(user_id.to_string())])
            .await?;
        Ok(())
    }

    /// Clear all sessions for a user (for logout)
    pub async fn clear_user_session(&self, user_id: &str) -> AppResult<()> {
        use tracing::{debug, info};

        debug!(user_id = user_id, "Clearing all sessions for user");

        let query = "DELETE FROM sessions WHERE user_id = ?";
        let _rows_affected = self
            .execute_query(query, vec![Value::String(user_id.to_string())])
            .await?;

        info!(user_id = user_id, "Cleared user sessions from database");

        Ok(())
    }

    /// Trusted device management
    pub async fn create_trusted_device(
        &self,
        device: &crate::models::user::TrustedDevice,
    ) -> AppResult<()> {
        let query = r#"
            INSERT INTO trusted_devices
            (id, user_id, device_identifier, device_name, device_type, encrypted_device_public_key,
             encrypted_device_private_key, encrypted_user_key, device_key_encrypted, trust_established_at,
             last_used_at, is_active)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        "#;

        self.execute_query(
            query,
            vec![
                Value::String(device.id.clone()),
                Value::String(device.user_id.clone()),
                Value::String(device.device_identifier.clone()),
                device
                    .device_name
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                Value::String(device.device_type.clone()),
                Value::String(device.encrypted_device_public_key.clone()),
                Value::String(device.encrypted_device_private_key.clone()),
                Value::String(device.encrypted_user_key.clone()),
                Value::String(device.device_key_encrypted.clone()),
                Value::String(device.trust_established_at.to_rfc3339()),
                device
                    .last_used_at
                    .as_ref()
                    .map(|dt| Value::String(dt.to_rfc3339()))
                    .unwrap_or(Value::Null),
                Value::Number((if device.is_active { 1 } else { 0 }).into()),
            ],
        )
        .await?;

        Ok(())
    }

    pub async fn get_trusted_device_by_identifier(
        &self,
        device_identifier: &str,
        user_id: &str,
    ) -> AppResult<Option<crate::models::user::TrustedDevice>> {
        let query = r#"
            SELECT id, user_id, device_identifier, device_name, device_type, encrypted_device_public_key,
                   encrypted_device_private_key, encrypted_user_key, device_key_encrypted, trust_established_at,
                   last_used_at, is_active
            FROM trusted_devices
            WHERE device_identifier = ? AND user_id = ? AND is_active = 1
        "#;

        let result = self
            .select_query(
                query,
                vec![
                    Value::String(device_identifier.to_string()),
                    Value::String(user_id.to_string()),
                ],
            )
            .await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Expected array result from trusted device query".to_string(),
        })?;

        if rows.is_empty() {
            return Ok(None);
        }

        let device = crate::models::user::TrustedDevice::from_database_row(&rows[0])?;
        Ok(Some(device))
    }

    pub async fn get_trusted_devices_for_user(
        &self,
        user_id: &str,
    ) -> AppResult<Vec<crate::models::user::TrustedDevice>> {
        let query = r#"
            SELECT id, user_id, device_identifier, device_name, device_type, encrypted_device_public_key,
                   encrypted_device_private_key, encrypted_user_key, device_key_encrypted, trust_established_at,
                   last_used_at, is_active
            FROM trusted_devices
            WHERE user_id = ?
            ORDER BY trust_established_at DESC
        "#;

        let result = self
            .select_query(query, vec![Value::String(user_id.to_string())])
            .await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Expected array result from trusted devices query".to_string(),
        })?;

        let mut devices = Vec::new();
        for row in rows {
            devices.push(crate::models::user::TrustedDevice::from_database_row(row)?);
        }

        Ok(devices)
    }

    pub async fn update_trusted_device_last_used(&self, device_id: &str) -> AppResult<()> {
        let query = "UPDATE trusted_devices SET last_used_at = ? WHERE id = ?";

        self.execute_query(
            query,
            vec![
                Value::String(chrono::Utc::now().to_rfc3339()),
                Value::String(device_id.to_string()),
            ],
        )
        .await?;

        Ok(())
    }

    pub async fn revoke_trusted_device(
        &self,
        device_identifier: &str,
        user_id: &str,
    ) -> AppResult<()> {
        let query =
            "UPDATE trusted_devices SET is_active = 0 WHERE device_identifier = ? AND user_id = ?";

        self.execute_query(
            query,
            vec![
                Value::String(device_identifier.to_string()),
                Value::String(user_id.to_string()),
            ],
        )
        .await?;

        Ok(())
    }

    /// Cipher management
    /// Get sample ciphers for user key validation
    pub async fn get_sample_ciphers_for_user(
        &self,
        user_id: &str,
        limit: usize,
    ) -> AppResult<Vec<Cipher>> {
        let query = "SELECT id, user_id, organization_id, folder_id, name, notes,
                           cipher_type, encrypted_data, favorite, reprompt,
                           revision_date, created_date, deleted_date, enc_type, mac
                    FROM ciphers WHERE user_id = ? AND deleted_date IS NULL ORDER BY revision_date DESC LIMIT ?";

        let result = self
            .select_query(
                &query,
                vec![
                    Value::String(user_id.to_string()),
                    Value::Number((limit as i64).into()),
                ],
            )
            .await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Expected array result from cipher query".to_string(),
        })?;

        let mut ciphers = Vec::new();
        for row in rows {
            ciphers.push(Cipher::from_database_row(row)?);
        }

        Ok(ciphers)
    }

    /// Get sample organization ciphers for organization key validation
    pub async fn get_sample_organization_ciphers(
        &self,
        organization_id: &str,
        limit: usize,
    ) -> AppResult<Vec<Cipher>> {
        let query = "SELECT id, user_id, organization_id, folder_id, name, notes,
                           cipher_type, encrypted_data, favorite, reprompt,
                           revision_date, created_date, deleted_date, enc_type, mac
                    FROM ciphers WHERE organization_id = ? AND deleted_date IS NULL ORDER BY revision_date DESC LIMIT ?";

        let result = self
            .select_query(
                &query,
                vec![
                    Value::String(organization_id.to_string()),
                    Value::Number((limit as i64).into()),
                ],
            )
            .await?;

        let rows = result.as_array().ok_or_else(|| AppError::DatabaseError {
            message: "Expected array result from organization cipher query".to_string(),
        })?;

        let mut ciphers = Vec::new();
        for row in rows {
            ciphers.push(Cipher::from_database_row(row)?);
        }

        Ok(ciphers)
    }

    /// Get a single cipher by ID and user ID
    pub async fn get_cipher(&self, cipher_id: &str, user_id: &str) -> AppResult<Option<Cipher>> {
        let query = "SELECT id, user_id, organization_id, folder_id, name, notes,
                           cipher_type, encrypted_data, favorite, reprompt,
                           revision_date, created_date, deleted_date, enc_type, mac
                    FROM ciphers
                    WHERE id = ? AND user_id = ? AND deleted_date IS NULL";

        let row = sqlx::query(query)
            .bind(cipher_id)
            .bind(user_id)
            .fetch_optional(&*self.pool)
            .await?;

        if let Some(row) = row {
            let cipher = Cipher {
                id: row.get("id"),
                user_id: row.get("user_id"),
                organization_id: row.get("organization_id"),
                folder_id: row.get("folder_id"),
                name: row.get("name"),
                notes: row.get("notes"),
                cipher_type: row.get("cipher_type"),
                encrypted_data: row.get("encrypted_data"),
                favorite: row.get("favorite"),
                reprompt: row.get("reprompt"),
                revision_date: row.get("revision_date"),
                created_date: row.get("created_date"),
                deleted_date: row.get("deleted_date"),
                enc_type: row.get("enc_type"),
                mac: row.get("mac"),
            };
            Ok(Some(cipher))
        } else {
            Ok(None)
        }
    }

    pub async fn get_all_ciphers(&self, user_id: &str) -> AppResult<Vec<Cipher>> {
        let query = "SELECT id, user_id, organization_id, folder_id, name, notes,
                           cipher_type, encrypted_data, favorite, reprompt,
                           revision_date, created_date, deleted_date, enc_type, mac
                    FROM ciphers
                    WHERE user_id = ? AND deleted_date IS NULL
                    ORDER BY name";
        let result = self
            .select_query(query, vec![Value::String(user_id.to_string())])
            .await?;

        self.parse_result_array(result, |row| {
            let cipher = Cipher {
                id: row
                    .get("id")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                user_id: row
                    .get("user_id")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                organization_id: row
                    .get("organization_id")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                folder_id: row
                    .get("folder_id")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                name: row
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                notes: row
                    .get("notes")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                cipher_type: row.get("cipher_type").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
                encrypted_data: row
                    .get("encrypted_data")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                favorite: row
                    .get("favorite")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false),
                reprompt: row
                    .get("reprompt")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false),
                revision_date: row
                    .get("revision_date")
                    .and_then(|v| v.as_str())
                    .map(|s| {
                        DateTime::parse_from_rfc3339(s)
                            .map(|dt| dt.with_timezone(&Utc))
                            .unwrap_or_else(|_| Utc::now())
                    })
                    .unwrap_or_else(|| Utc::now()),
                created_date: row
                    .get("created_date")
                    .and_then(|v| v.as_str())
                    .map(|s| {
                        DateTime::parse_from_rfc3339(s)
                            .map(|dt| dt.with_timezone(&Utc))
                            .unwrap_or_else(|_| Utc::now())
                    })
                    .unwrap_or_else(|| Utc::now()),
                deleted_date: row.get("deleted_date").and_then(|v| v.as_str()).map(|s| {
                    DateTime::parse_from_rfc3339(s)
                        .map(|dt| dt.with_timezone(&Utc))
                        .unwrap_or_else(|_| Utc::now())
                }),
                enc_type: row.get("enc_type").and_then(|v| v.as_i64()).unwrap_or(2) as i32,
                mac: row
                    .get("mac")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
            };
            Ok(cipher)
        })
    }

    /// Get a sample of user ciphers for validation (limited number)
    pub async fn get_user_ciphers_sample(
        &self,
        user_id: &str,
        limit: usize,
    ) -> AppResult<Vec<Cipher>> {
        let query = "SELECT id, user_id, organization_id, folder_id, name, notes,
                           cipher_type, encrypted_data, favorite, reprompt,
                           revision_date, created_date, deleted_date, enc_type, mac
                    FROM ciphers
                    WHERE user_id = ? AND deleted_date IS NULL AND name IS NOT NULL AND name != ''
                    ORDER BY created_date DESC
                    LIMIT ?";
        let result = self
            .select_query(
                query,
                vec![
                    Value::String(user_id.to_string()),
                    Value::Number(limit.into()),
                ],
            )
            .await?;

        self.parse_result_array(result, |row| {
            let cipher = Cipher {
                id: row
                    .get("id")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                user_id: row
                    .get("user_id")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                organization_id: row
                    .get("organization_id")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                folder_id: row
                    .get("folder_id")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                name: row
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                notes: row
                    .get("notes")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                cipher_type: row.get("cipher_type").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
                encrypted_data: row
                    .get("encrypted_data")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                favorite: row
                    .get("favorite")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false),
                reprompt: row
                    .get("reprompt")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false),
                revision_date: row
                    .get("revision_date")
                    .and_then(|v| v.as_str())
                    .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                    .map(|dt| dt.with_timezone(&chrono::Utc))
                    .unwrap_or_else(chrono::Utc::now),
                created_date: row
                    .get("created_date")
                    .and_then(|v| v.as_str())
                    .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                    .map(|dt| dt.with_timezone(&chrono::Utc))
                    .unwrap_or_else(chrono::Utc::now),
                deleted_date: row
                    .get("deleted_date")
                    .and_then(|v| v.as_str())
                    .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                    .map(|dt| dt.with_timezone(&chrono::Utc)),
                enc_type: row.get("enc_type").and_then(|v| v.as_i64()).unwrap_or(2) as i32,
                mac: row
                    .get("mac")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
            };
            Ok(cipher)
        })
    }

    pub async fn save_cipher(&self, user_id: &str, cipher: &Cipher) -> AppResult<()> {
        let query = "INSERT OR REPLACE INTO ciphers
                     (id, user_id, organization_id, folder_id, name, notes, cipher_type, encrypted_data, favorite, reprompt,
                      revision_date, created_date, deleted_date, enc_type, mac)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

        self.execute_query(
            query,
            vec![
                Value::String(cipher.id.clone()),
                Value::String(user_id.to_string()),
                cipher
                    .organization_id
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                cipher
                    .folder_id
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                Value::String(cipher.name.clone()),
                cipher
                    .notes
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
                Value::Number(cipher.cipher_type.into()),
                Value::String(cipher.encrypted_data.clone()),
                Value::Bool(cipher.favorite),
                Value::Bool(cipher.reprompt),
                Value::String(cipher.revision_date.to_rfc3339()),
                Value::String(cipher.created_date.to_rfc3339()),
                cipher
                    .deleted_date
                    .map(|dt| Value::String(dt.to_rfc3339()))
                    .unwrap_or(Value::Null),
                Value::Number(cipher.enc_type.into()),
                cipher
                    .mac
                    .as_ref()
                    .map(|s| Value::String(s.clone()))
                    .unwrap_or(Value::Null),
            ],
        )
        .await?;
        Ok(())
    }

    pub async fn delete_cipher(&self, cipher_id: &str, user_id: &str) -> AppResult<()> {
        let query =
            "UPDATE ciphers SET deleted_date = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ?";
        self.execute_query(
            query,
            vec![
                Value::String(cipher_id.to_string()),
                Value::String(user_id.to_string()),
            ],
        )
        .await?;
        Ok(())
    }

    /// Folder management
    pub async fn get_folders(&self, user_id: &str) -> AppResult<Vec<Folder>> {
        let query = "SELECT id, user_id, name, revision_date FROM folders WHERE user_id = ?";
        let result = self
            .select_query(query, vec![Value::String(user_id.to_string())])
            .await?;

        self.parse_result_array(result, |row| {
            let folder = Folder {
                id: row
                    .get("id")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                user_id: row
                    .get("user_id")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                name: row
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                revision_date: row
                    .get("revision_date")
                    .and_then(|v| v.as_str())
                    .map(|s| {
                        DateTime::parse_from_rfc3339(s)
                            .map(|dt| dt.with_timezone(&Utc))
                            .unwrap_or_else(|_| Utc::now())
                    })
                    .unwrap_or_else(|| Utc::now()),
            };
            Ok(folder)
        })
    }

    pub async fn save_folder(&self, folder: &Folder) -> AppResult<()> {
        let query =
            "INSERT OR REPLACE INTO folders (id, user_id, name, revision_date) VALUES (?, ?, ?, ?)";
        self.execute_query(
            query,
            vec![
                Value::String(folder.id.clone()),
                Value::String(folder.user_id.clone()),
                Value::String(folder.name.clone()),
                Value::String(folder.revision_date.to_rfc3339()),
            ],
        )
        .await?;
        Ok(())
    }

    pub async fn delete_folder(&self, folder_id: &str, user_id: &str) -> AppResult<()> {
        let query = "DELETE FROM folders WHERE id = ? AND user_id = ?";
        self.execute_query(
            query,
            vec![
                Value::String(folder_id.to_string()),
                Value::String(user_id.to_string()),
            ],
        )
        .await?;
        Ok(())
    }

    /// Collection management
    pub async fn get_collections(&self, organization_id: &str) -> AppResult<Vec<Collection>> {
        let query = "SELECT id, organization_id, name, external_id, revision_date FROM collections WHERE organization_id = ?";
        let result = self
            .select_query(query, vec![Value::String(organization_id.to_string())])
            .await?;

        self.parse_result_array(result, |row| {
            let collection = Collection {
                id: row
                    .get("id")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                organization_id: row
                    .get("organization_id")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                name: row
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                external_id: row
                    .get("external_id")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                revision_date: row
                    .get("revision_date")
                    .and_then(|v| v.as_str())
                    .map(|s| {
                        DateTime::parse_from_rfc3339(s)
                            .map(|dt| dt.with_timezone(&Utc))
                            .unwrap_or_else(|_| Utc::now())
                    })
                    .unwrap_or_else(|| Utc::now()),
            };
            Ok(collection)
        })
    }
}

// TODO: Database operations will be implemented as extension traits
// For now, operations are accessed through separate modules in the storage layer

// For now, operations are accessed through separate modules in the storage layer
