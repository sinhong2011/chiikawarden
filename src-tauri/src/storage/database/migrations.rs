use crate::error::{AppError, AppResult};
use sqlx::SqlitePool;

/// Migration definition
#[derive(Clone)]
pub struct Migration {
    pub version: i32,
    pub description: String,
    pub sql: String,
}

/// Migration runner for database schema management using SQLx
pub struct MigrationRunner {
    migrations: Vec<Migration>,
}

impl MigrationRunner {
    /// Create a new migration runner with all migrations
    pub fn new() -> Self {
        let migrations = vec![
            Migration {
                version: 1,
                description: "create_initial_schema".to_string(),
                sql: include_str!("../../../migrations/001_initial_schema.sql").to_string(),
            },
            Migration {
                version: 2,
                description: "add_encryption_metadata".to_string(),
                sql: include_str!("../../../migrations/002_encryption_metadata.sql").to_string(),
            },
            Migration {
                version: 3,
                description: "performance_optimizations".to_string(),
                sql: include_str!("../../../migrations/004_performance_optimizations.sql")
                    .to_string(),
            },
        ];

        Self { migrations }
    }

    /// Get all migrations
    pub fn get_migrations(&self) -> &[Migration] {
        &self.migrations
    }

    /// Get migration by version
    pub fn get_migration(&self, version: i32) -> Option<&Migration> {
        self.migrations.iter().find(|m| m.version == version)
    }

    /// Get latest migration version
    pub fn get_latest_version(&self) -> i32 {
        self.migrations.iter().map(|m| m.version).max().unwrap_or(0)
    }

    /// Run all pending migrations
    pub async fn run_migrations(&self, pool: &SqlitePool) -> AppResult<()> {
        // Ensure migrations table exists
        self.ensure_migrations_table(pool).await?;

        // Run each migration if not already applied
        for migration in &self.migrations {
            if !self.is_migration_applied(pool, migration.version).await? {
                self.apply_migration(pool, migration).await?;
            }
        }

        Ok(())
    }

    /// Ensure the migrations table exists
    async fn ensure_migrations_table(&self, pool: &SqlitePool) -> AppResult<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS __migrations (
                version INTEGER PRIMARY KEY,
                description TEXT NOT NULL,
                applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
            "#,
        )
        .execute(pool)
        .await
        .map_err(|e| AppError::DatabaseError {
            message: format!("Failed to create migrations table: {}", e),
        })?;

        Ok(())
    }

    /// Check if a migration is already applied
    async fn is_migration_applied(&self, pool: &SqlitePool, version: i32) -> AppResult<bool> {
        let count =
            sqlx::query_scalar::<_, i32>("SELECT COUNT(*) FROM __migrations WHERE version = ?")
                .bind(version)
                .fetch_one(pool)
                .await
                .map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to check migration status: {}", e),
                })?;

        Ok(count > 0)
    }

    /// Apply a single migration
    async fn apply_migration(&self, pool: &SqlitePool, migration: &Migration) -> AppResult<()> {
        // Split migration SQL into PRAGMA statements and regular SQL
        let (pragma_statements, regular_sql) = self.split_pragma_statements(&migration.sql);

        // Execute PRAGMA statements outside of transaction (they don't support transactions)
        for pragma in pragma_statements {
            sqlx::query(&pragma)
                .execute(pool)
                .await
                .map_err(|e| AppError::DatabaseError {
                    message: format!(
                        "Failed to execute PRAGMA in migration {}: {}",
                        migration.version, e
                    ),
                })?;
        }

        // Start a transaction for regular SQL
        let mut tx = pool.begin().await.map_err(|e| AppError::DatabaseError {
            message: format!("Failed to start transaction: {}", e),
        })?;

        // Execute the regular migration SQL
        if !regular_sql.trim().is_empty() {
            sqlx::query(&regular_sql)
                .execute(&mut *tx)
                .await
                .map_err(|e| AppError::DatabaseError {
                    message: format!("Failed to execute migration {}: {}", migration.version, e),
                })?;
        }

        // Record the migration as applied
        sqlx::query("INSERT INTO __migrations (version, description) VALUES (?, ?)")
            .bind(migration.version)
            .bind(&migration.description)
            .execute(&mut *tx)
            .await
            .map_err(|e| AppError::DatabaseError {
                message: format!("Failed to record migration: {}", e),
            })?;

        // Commit the transaction
        tx.commit().await.map_err(|e| AppError::DatabaseError {
            message: format!("Failed to commit migration transaction: {}", e),
        })?;

        Ok(())
    }

    /// Split SQL into PRAGMA statements and regular SQL
    fn split_pragma_statements(&self, sql: &str) -> (Vec<String>, String) {
        let mut pragma_statements = Vec::new();
        let mut regular_lines = Vec::new();

        for line in sql.lines() {
            let trimmed = line.trim();
            if trimmed.to_uppercase().starts_with("PRAGMA ") && !trimmed.starts_with("--") {
                pragma_statements.push(trimmed.to_string());
            } else {
                regular_lines.push(line);
            }
        }

        (pragma_statements, regular_lines.join("\n"))
    }

    /// Get applied migrations
    pub async fn get_applied_migrations(&self, pool: &SqlitePool) -> AppResult<Vec<(i32, String)>> {
        let rows = sqlx::query_as::<_, (i32, String)>(
            "SELECT version, description FROM __migrations ORDER BY version",
        )
        .fetch_all(pool)
        .await
        .map_err(|e| AppError::DatabaseError {
            message: format!("Failed to get applied migrations: {}", e),
        })?;

        Ok(rows)
    }

    /// Rollback a migration (if supported)
    pub async fn rollback_migration(&self, _pool: &SqlitePool, _version: i32) -> AppResult<()> {
        // For now, we don't support rollbacks since SQLite doesn't support them well
        // This would require having down migrations defined
        Err(AppError::DatabaseError {
            message: "Migration rollback is not supported".to_string(),
        })
    }

    /// Validate migration SQL for common issues
    pub fn validate_migration(&self, migration: &Migration) -> Vec<String> {
        let mut warnings = Vec::new();
        let sql = migration.sql.to_lowercase();

        // Check for potentially dangerous operations
        if sql.contains("drop table") && !sql.contains("if exists") {
            warnings.push("DROP TABLE without IF EXISTS clause detected".to_string());
        }

        if sql.contains("alter table") && sql.contains("drop column") {
            warnings.push("ALTER TABLE DROP COLUMN detected - may cause data loss".to_string());
        }

        if sql.contains("truncate") {
            warnings.push("TRUNCATE statement detected - will delete all data".to_string());
        }

        // Check for missing transaction handling (already handled by our apply_migration)
        if !sql.contains("begin")
            && !sql.contains("commit")
            && (sql.contains("insert") || sql.contains("update") || sql.contains("delete"))
        {
            warnings.push("Migration contains DML without explicit transaction (will be wrapped automatically)".to_string());
        }

        warnings
    }

    /// Validate all migrations
    pub fn validate_all_migrations(&self) -> Vec<(i32, Vec<String>)> {
        self.migrations
            .iter()
            .map(|m| (m.version, self.validate_migration(m)))
            .filter(|(_, warnings)| !warnings.is_empty())
            .collect()
    }

    /// Get migration status
    pub async fn get_migration_status(&self, pool: &SqlitePool) -> AppResult<MigrationStatus> {
        let applied = self.get_applied_migrations(pool).await?;
        let latest_version = self.get_latest_version();
        let applied_versions: Vec<i32> = applied.iter().map(|(v, _)| *v).collect();
        let pending_versions: Vec<i32> = self
            .migrations
            .iter()
            .map(|m| m.version)
            .filter(|v| !applied_versions.contains(v))
            .collect();

        Ok(MigrationStatus {
            latest_version,
            applied_migrations: applied,
            pending_migrations: pending_versions,
        })
    }
}

/// Migration status information
#[derive(Debug, Clone)]
pub struct MigrationStatus {
    pub latest_version: i32,
    pub applied_migrations: Vec<(i32, String)>,
    pub pending_migrations: Vec<i32>,
}

impl Default for MigrationRunner {
    fn default() -> Self {
        Self::new()
    }
}

impl MigrationStatus {
    /// Check if all migrations are applied
    pub fn is_up_to_date(&self) -> bool {
        self.pending_migrations.is_empty()
    }

    /// Get the current database version
    pub fn current_version(&self) -> i32 {
        self.applied_migrations
            .iter()
            .map(|(v, _)| *v)
            .max()
            .unwrap_or(0)
    }
}
