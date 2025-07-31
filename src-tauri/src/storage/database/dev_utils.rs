use crate::crypto::{
    cipher_crypto::EncryptedString, encryption::EncryptionService, EncryptionType, UserKey,
};
use crate::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};
use serde_json::json;
use specta::Type;
use sqlx::{sqlite::SqlitePool, Row};
use std::collections::HashMap;
use tracing::{debug, info, warn};

/// Database development utilities
pub struct DatabaseDevUtils;

/// Schema information for inspection
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct SchemaInfo {
    pub tables: Vec<TableInfo>,
    pub indexes: Vec<IndexInfo>,
    pub triggers: Vec<TriggerInfo>,
    pub views: Vec<ViewInfo>,
}

/// Table information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct TableInfo {
    pub name: String,
    pub columns: Vec<ColumnInfo>,
    pub row_count: i32,
    pub size_estimate: String,
}

/// Column information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct ColumnInfo {
    pub name: String,
    pub data_type: String,
    pub nullable: bool,
    pub default_value: Option<String>,
    pub primary_key: bool,
}

/// Index information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct IndexInfo {
    pub name: String,
    pub table: String,
    pub columns: Vec<String>,
    pub unique: bool,
    pub sql: Option<String>,
}

/// Trigger information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct TriggerInfo {
    pub name: String,
    pub table: String,
    pub event: String,
    pub sql: String,
}

/// View information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct ViewInfo {
    pub name: String,
    pub sql: String,
}

/// Database statistics
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct DatabaseStats {
    pub total_size_mb: f64,
    pub page_count: i32,
    pub page_size: i32,
    pub table_stats: HashMap<String, TableStats>,
    pub index_stats: HashMap<String, IndexStats>,
}

/// Table statistics
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct TableStats {
    pub row_count: i32,
    pub size_estimate_mb: f64,
    pub last_analyzed: Option<String>,
}

/// Index statistics
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct IndexStats {
    pub size_estimate_mb: f64,
    pub usage_count: Option<i32>,
    pub last_used: Option<String>,
}

impl DatabaseDevUtils {
    /// Generate a test user key for development
    pub fn generate_test_user_key() -> AppResult<UserKey> {
        // Create a deterministic test key for consistent development data
        // The key needs to be 64 bytes for HMAC operations
        let test_key_bytes =
            b"test_user_key_64_bytes_long_data_for_hmac_operations_and_encrypt".to_vec();
        assert_eq!(
            test_key_bytes.len(),
            64,
            "Test key must be exactly 64 bytes"
        );
        Ok(UserKey::new(test_key_bytes))
    }

    /// Encrypt test data using the test user key
    pub fn encrypt_test_data(data: &str, user_key: &UserKey) -> AppResult<String> {
        let data_bytes = data.as_bytes();
        let encrypted_data = EncryptionService::encrypt(
            data_bytes,
            user_key.as_bytes(),
            EncryptionType::AesCbc256HmacSha256B64,
        )
        .map_err(|e| AppError::CryptographyError {
            operation: format!("encrypt_test_data: {}", e),
        })?;

        Ok(EncryptedString::from_encrypted_data(
            &encrypted_data,
            EncryptionType::AesCbc256HmacSha256B64,
        ))
    }

    /// Generate properly encrypted cipher data for testing
    pub fn generate_test_cipher_data(name: &str, user_key: &UserKey) -> AppResult<String> {
        // Create realistic login data
        let login_data = json!({
            "username": format!("user{}@example.com", name.chars().last().unwrap_or('1')),
            "password": "test_password_123",
            "uris": [
                {
                    "uri": format!("https://example{}.com", name.chars().last().unwrap_or('1')),
                    "match_type": 0
                }
            ],
            "totp": null
        });

        // Encrypt the JSON data
        let json_string = login_data.to_string();
        Self::encrypt_test_data(&json_string, user_key)
    }

    /// Reset database to initial state (development only)
    pub async fn reset_database(pool: &SqlitePool) -> AppResult<()> {
        warn!("Resetting database - all data will be lost!");

        // Get all user tables (excluding system tables)
        let tables: Vec<String> = sqlx::query_scalar(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        )
        .fetch_all(pool)
        .await?;

        // Drop all tables
        for table in tables {
            info!(table = %table, "Dropping table");
            sqlx::query(&format!("DROP TABLE IF EXISTS {}", table))
                .execute(pool)
                .await?;
        }

        // Drop all views
        let views: Vec<String> =
            sqlx::query_scalar("SELECT name FROM sqlite_master WHERE type='view'")
                .fetch_all(pool)
                .await?;

        for view in views {
            info!(view = %view, "Dropping view");
            sqlx::query(&format!("DROP VIEW IF EXISTS {}", view))
                .execute(pool)
                .await?;
        }

        // Drop all triggers
        let triggers: Vec<String> =
            sqlx::query_scalar("SELECT name FROM sqlite_master WHERE type='trigger'")
                .fetch_all(pool)
                .await?;

        for trigger in triggers {
            info!(trigger = %trigger, "Dropping trigger");
            sqlx::query(&format!("DROP TRIGGER IF EXISTS {}", trigger))
                .execute(pool)
                .await?;
        }

        // Vacuum to reclaim space
        sqlx::query("VACUUM").execute(pool).await?;

        info!("Database reset completed");
        Ok(())
    }

    /// Inspect database schema
    pub async fn inspect_schema(pool: &SqlitePool) -> AppResult<SchemaInfo> {
        debug!("Inspecting database schema");

        let tables = Self::get_table_info(pool).await?;
        let indexes = Self::get_index_info(pool).await?;
        let triggers = Self::get_trigger_info(pool).await?;
        let views = Self::get_view_info(pool).await?;

        Ok(SchemaInfo {
            tables,
            indexes,
            triggers,
            views,
        })
    }

    /// Get detailed table information
    async fn get_table_info(pool: &SqlitePool) -> AppResult<Vec<TableInfo>> {
        let table_names: Vec<String> = sqlx::query_scalar(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        )
        .fetch_all(pool)
        .await?;

        let mut tables = Vec::new();

        for table_name in table_names {
            let columns = Self::get_column_info(pool, &table_name).await?;

            let row_count =
                sqlx::query_scalar::<_, i64>(&format!("SELECT COUNT(*) FROM {}", table_name))
                    .fetch_one(pool)
                    .await
                    .unwrap_or(0) as i32;

            tables.push(TableInfo {
                name: table_name,
                columns,
                row_count,
                size_estimate: "Unknown".to_string(), // SQLite doesn't provide easy size estimates
            });
        }

        Ok(tables)
    }

    /// Get column information for a table
    async fn get_column_info(pool: &SqlitePool, table_name: &str) -> AppResult<Vec<ColumnInfo>> {
        let rows = sqlx::query(&format!("PRAGMA table_info({})", table_name))
            .fetch_all(pool)
            .await?;

        let mut columns = Vec::new();

        for row in rows {
            columns.push(ColumnInfo {
                name: row.get::<String, _>(1),
                data_type: row.get::<String, _>(2),
                nullable: row.get::<i32, _>(3) == 0,
                default_value: row.get::<Option<String>, _>(4),
                primary_key: row.get::<i32, _>(5) == 1,
            });
        }

        Ok(columns)
    }

    /// Get index information
    async fn get_index_info(pool: &SqlitePool) -> AppResult<Vec<IndexInfo>> {
        let rows = sqlx::query(
            "SELECT name, tbl_name, sql FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
        )
        .fetch_all(pool)
        .await?;

        let mut indexes = Vec::new();

        for row in rows {
            let name: String = row.get(0);
            let table: String = row.get(1);
            let sql: Option<String> = row.get(2);

            // Get index columns
            let columns = Self::get_index_columns(pool, &name).await?;

            indexes.push(IndexInfo {
                name,
                table,
                columns,
                unique: sql.as_ref().map_or(false, |s| s.contains("UNIQUE")),
                sql,
            });
        }

        Ok(indexes)
    }

    /// Get columns for an index
    async fn get_index_columns(pool: &SqlitePool, index_name: &str) -> AppResult<Vec<String>> {
        let rows = sqlx::query(&format!("PRAGMA index_info({})", index_name))
            .fetch_all(pool)
            .await?;

        let mut columns = Vec::new();
        for row in rows {
            columns.push(row.get::<String, _>(2));
        }

        Ok(columns)
    }

    /// Get trigger information
    async fn get_trigger_info(pool: &SqlitePool) -> AppResult<Vec<TriggerInfo>> {
        let rows =
            sqlx::query("SELECT name, tbl_name, sql FROM sqlite_master WHERE type='trigger'")
                .fetch_all(pool)
                .await?;

        let mut triggers = Vec::new();

        for row in rows {
            let name: String = row.get(0);
            let table: String = row.get(1);
            let sql: String = row.get(2);

            // Extract event type from SQL
            let event = if sql.to_uppercase().contains("AFTER UPDATE") {
                "AFTER UPDATE".to_string()
            } else if sql.to_uppercase().contains("BEFORE UPDATE") {
                "BEFORE UPDATE".to_string()
            } else if sql.to_uppercase().contains("AFTER INSERT") {
                "AFTER INSERT".to_string()
            } else if sql.to_uppercase().contains("BEFORE INSERT") {
                "BEFORE INSERT".to_string()
            } else if sql.to_uppercase().contains("AFTER DELETE") {
                "AFTER DELETE".to_string()
            } else if sql.to_uppercase().contains("BEFORE DELETE") {
                "BEFORE DELETE".to_string()
            } else {
                "UNKNOWN".to_string()
            };

            triggers.push(TriggerInfo {
                name,
                table,
                event,
                sql,
            });
        }

        Ok(triggers)
    }

    /// Get view information
    async fn get_view_info(pool: &SqlitePool) -> AppResult<Vec<ViewInfo>> {
        let rows = sqlx::query("SELECT name, sql FROM sqlite_master WHERE type='view'")
            .fetch_all(pool)
            .await?;

        let mut views = Vec::new();

        for row in rows {
            views.push(ViewInfo {
                name: row.get(0),
                sql: row.get(1),
            });
        }

        Ok(views)
    }

    /// Collect database statistics
    pub async fn collect_statistics(pool: &SqlitePool) -> AppResult<DatabaseStats> {
        debug!("Collecting database statistics");

        let page_count = sqlx::query_scalar::<_, i64>("PRAGMA page_count")
            .fetch_one(pool)
            .await
            .unwrap_or(0) as i32;

        let page_size = sqlx::query_scalar::<_, i64>("PRAGMA page_size")
            .fetch_one(pool)
            .await
            .unwrap_or(4096) as i32;

        let total_size_mb = (page_count as i64 * page_size as i64) as f64 / (1024.0 * 1024.0);

        let table_stats = Self::collect_table_stats(pool).await?;
        let index_stats = HashMap::new(); // SQLite doesn't provide detailed index stats easily

        Ok(DatabaseStats {
            total_size_mb,
            page_count,
            page_size,
            table_stats,
            index_stats,
        })
    }

    /// Collect table statistics
    async fn collect_table_stats(pool: &SqlitePool) -> AppResult<HashMap<String, TableStats>> {
        let table_names: Vec<String> = sqlx::query_scalar(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        )
        .fetch_all(pool)
        .await?;

        let mut stats = HashMap::new();

        for table_name in table_names {
            let row_count =
                sqlx::query_scalar::<_, i64>(&format!("SELECT COUNT(*) FROM {}", table_name))
                    .fetch_one(pool)
                    .await
                    .unwrap_or(0) as i32;

            stats.insert(
                table_name,
                TableStats {
                    row_count,
                    size_estimate_mb: 0.0, // SQLite doesn't provide easy table size estimates
                    last_analyzed: None,
                },
            );
        }

        Ok(stats)
    }

    /// Optimize database (VACUUM and ANALYZE)
    pub async fn optimize_database(pool: &SqlitePool) -> AppResult<()> {
        info!("Starting database optimization");

        // Run ANALYZE to update statistics
        info!("Running ANALYZE to update query planner statistics");
        sqlx::query("ANALYZE").execute(pool).await?;

        // Run VACUUM to reclaim space and defragment
        info!("Running VACUUM to reclaim space and defragment database");
        sqlx::query("VACUUM").execute(pool).await?;

        info!("Database optimization completed");
        Ok(())
    }

    /// Generate sample data for testing (development only)
    pub async fn generate_sample_data(pool: &SqlitePool) -> AppResult<()> {
        warn!("Generating sample data for development testing");

        // Generate test user key for encryption
        let test_user_key = Self::generate_test_user_key()?;

        // Create a test master key and encrypt the user key for storage
        let test_master_key_bytes = b"test_master_key_32_bytes_long!!!".to_vec();
        let test_master_key = crate::crypto::MasterKey::new(test_master_key_bytes);

        // Encrypt the user key with the master key
        let encrypted_user_key =
            EncryptionService::encrypt_user_key(&test_user_key, &test_master_key)?;
        let encrypted_user_key_string = EncryptedString::from_encrypted_data(
            &encrypted_user_key,
            EncryptionType::AesCbc256HmacSha256B64,
        );

        // Create a test user with the encrypted user key
        sqlx::query(
            "INSERT OR REPLACE INTO users (id, email, master_key_hash, encrypted_user_key_new, kdf_type, kdf_iterations, created_date, revision_date)
             VALUES ('test-user-1', 'test@example.com', 'test-hash', ?, 0, 600000, datetime('now'), datetime('now'))"
        )
        .bind(encrypted_user_key_string)
        .execute(pool)
        .await?;

        // Create sample folders
        sqlx::query(
            "INSERT OR REPLACE INTO folders (id, user_id, name, revision_date) 
             VALUES ('folder-1', 'test-user-1', 'Personal', datetime('now'))",
        )
        .execute(pool)
        .await?;

        sqlx::query(
            "INSERT OR REPLACE INTO folders (id, user_id, name, revision_date) 
             VALUES ('folder-2', 'test-user-1', 'Work', datetime('now'))",
        )
        .execute(pool)
        .await?;

        // Create sample ciphers with properly encrypted data
        for i in 1..=5 {
            let cipher_name = format!("Test Login {}", i);

            // Generate properly encrypted cipher data
            let encrypted_data = match Self::generate_test_cipher_data(&cipher_name, &test_user_key)
            {
                Ok(data) => data,
                Err(e) => {
                    warn!(
                        "Failed to encrypt test cipher data for {}: {}",
                        cipher_name, e
                    );
                    // Fallback to a valid encrypted string format (empty data)
                    let empty_data = json!({
                        "username": "",
                        "password": "",
                        "uris": [],
                        "totp": null
                    });
                    Self::encrypt_test_data(&empty_data.to_string(), &test_user_key)?
                }
            };

            // Encrypt the cipher name as well
            let encrypted_name = Self::encrypt_test_data(&cipher_name, &test_user_key)?;

            sqlx::query(
                "INSERT OR REPLACE INTO ciphers (id, user_id, folder_id, name, cipher_type, encrypted_data, enc_type, created_date, revision_date)
                 VALUES (?, 'test-user-1', 'folder-1', ?, 1, ?, 2, datetime('now'), datetime('now'))"
            )
            .bind(format!("cipher-{}", i))
            .bind(encrypted_name)
            .bind(encrypted_data)
            .execute(pool)
            .await?;
        }

        info!("Sample data generated successfully");
        Ok(())
    }
}
