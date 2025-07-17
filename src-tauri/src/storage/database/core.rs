use crate::error::{AppError, AppResult};
use crate::logging::log_database_operation;
use crate::models::{Cipher, Collection, Folder, SyncState};
use chrono::{DateTime, Utc};
use serde_json::Value;
use sqlx::{sqlite::SqlitePool, Column, Row, ValueRef};
use std::sync::Arc;
use tauri::AppHandle;
use tauri::Manager;
use tokio::sync::RwLock;
use tracing::{debug, error, info};

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
        let pool =
            SqlitePool::connect_lazy(&connection_string).map_err(|e| AppError::DatabaseError {
                message: format!("Failed to create database connection pool: {}", e),
            })?;

        Ok(Self {
            pool: Arc::new(pool),
            initialized: Arc::new(RwLock::new(false)),
            db_path: db_path.to_string_lossy().to_string(),
        })
    }

    /// Initialize the database with proper setup
    pub async fn initialize(&self) -> AppResult<()> {
        debug!(db_path = %self.db_path, "Initializing database");

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

        // Run migrations
        debug!("Running database migrations");
        self.run_migrations().await.map_err(|e| {
            error!(error = %e, "Database migration failed");
            AppError::DatabaseError {
                message: format!("Migration failed: {}", e),
            }
        })?;

        // Settings initialization is now handled by SettingsStoreService

        *initialized = true;
        info!(db_path = %self.db_path, "Database initialized successfully");
        Ok(())
    }

    /// Run database migrations using the MigrationRunner
    async fn run_migrations(&self) -> AppResult<()> {
        let migration_runner = super::migrations::MigrationRunner::new();
        migration_runner.run_migrations(&*self.pool).await
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

        let result = query_builder.execute(&*self.pool).await.map_err(|e| {
            error!(
                query = query,
                error = %e,
                "Database execute query failed"
            );
            log_database_operation("execute", "unknown", false, Some(&e.to_string()));
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

        log_database_operation("execute", "unknown", true, None);

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

        let rows = query_builder.fetch_all(&*self.pool).await.map_err(|e| {
            error!(
                query = query,
                error = %e,
                "Database select query failed"
            );
            log_database_operation("select", "unknown", false, Some(&e.to_string()));
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

        log_database_operation("select", "unknown", true, None);

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

    /// Sync state management
    pub async fn get_sync_state(&self, user_id: &str) -> AppResult<Option<SyncState>> {
        let query = "SELECT user_id, last_sync, revision_date FROM sync_state WHERE user_id = ?";
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
        let last_sync = row.get("last_sync").and_then(|v| v.as_str()).map(|s| {
            DateTime::parse_from_rfc3339(s)
                .map(|dt| dt.with_timezone(&Utc))
                .unwrap_or_else(|_| Utc::now())
        });

        let revision_date = row.get("revision_date").and_then(|v| v.as_str()).map(|s| {
            DateTime::parse_from_rfc3339(s)
                .map(|dt| dt.with_timezone(&Utc))
                .unwrap_or_else(|_| Utc::now())
        });

        Ok(Some(SyncState {
            user_id: user_id.to_string(),
            last_sync,
            revision_date,
        }))
    }

    pub async fn save_sync_state(&self, sync_state: &SyncState) -> AppResult<()> {
        let last_sync = sync_state.last_sync.map(|dt| dt.to_rfc3339());
        let revision_date = sync_state.revision_date.map(|dt| dt.to_rfc3339());

        let query = "INSERT OR REPLACE INTO sync_state (user_id, last_sync, revision_date) VALUES (?, ?, ?)";
        self.execute_query(
            query,
            vec![
                Value::String(sync_state.user_id.clone()),
                last_sync.map(Value::String).unwrap_or(Value::Null),
                revision_date.map(Value::String).unwrap_or(Value::Null),
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

    /// Cipher management
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
