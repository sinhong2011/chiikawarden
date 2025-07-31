use crate::error::{AppError, AppResult};
use sqlx::SqlitePool;
use std::path::Path;
use tracing::{debug, info, warn};

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
    /// Create a new migration runner with consolidated schema
    /// This consolidated migration includes all database structure from the original
    /// migrations (001, 002, 003) combined into a single comprehensive schema
    /// for pre-release development phase to eliminate migration inconsistencies
    pub fn new() -> Self {
        let migrations = vec![
            Migration {
                version: 1,
                description: "consolidated_complete_schema".to_string(),
                sql: include_str!("../../../migrations/001_initial_schema.sql").to_string(),
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
        use tracing::{debug, info};

        info!("Starting database migration process");
        debug!("Total migrations available: {}", self.migrations.len());

        // Ensure migrations table exists
        self.ensure_migrations_table(pool).await?;
        debug!("Migration tracking table ensured");

        // Check current migration status
        let applied_migrations = self.get_applied_migrations(pool).await?;
        info!("Applied migrations: {}", applied_migrations.len());

        let mut migrations_applied = 0;
        let mut migrations_skipped = 0;

        // Run each migration if not already applied
        for migration in &self.migrations {
            if !self.is_migration_applied(pool, migration.version).await? {
                info!(
                    version = migration.version,
                    description = %migration.description,
                    "Applying migration"
                );
                self.apply_migration(pool, migration).await?;
                migrations_applied += 1;
                info!(
                    version = migration.version,
                    description = %migration.description,
                    "Migration applied successfully"
                );
            } else {
                debug!(
                    version = migration.version,
                    description = %migration.description,
                    "Migration already applied, skipping"
                );
                migrations_skipped += 1;
            }
        }

        if migrations_applied > 0 {
            info!(
                applied = migrations_applied,
                skipped = migrations_skipped,
                "Database migration process completed"
            );
        } else {
            info!("Database schema is up to date, no migrations needed");
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
        use std::time::Instant;
        use tracing::{debug, info};

        let start_time = Instant::now();
        debug!(
            version = migration.version,
            description = %migration.description,
            "Starting migration application"
        );

        // Split migration SQL into PRAGMA statements and regular SQL
        let (pragma_statements, regular_sql) = self.split_pragma_statements(&migration.sql);

        debug!(
            version = migration.version,
            pragma_count = pragma_statements.len(),
            has_regular_sql = !regular_sql.trim().is_empty(),
            "Migration SQL analyzed"
        );

        // Execute PRAGMA statements outside of transaction (they don't support transactions)
        if !pragma_statements.is_empty() {
            debug!(
                version = migration.version,
                count = pragma_statements.len(),
                "Executing PRAGMA statements"
            );

            for (i, pragma) in pragma_statements.iter().enumerate() {
                debug!(
                    version = migration.version,
                    pragma_index = i + 1,
                    pragma = %pragma,
                    "Executing PRAGMA statement"
                );

                sqlx::query(pragma)
                    .execute(pool)
                    .await
                    .map_err(|e| AppError::DatabaseError {
                        message: format!(
                            "Failed to execute PRAGMA '{}' in migration {}: {}",
                            pragma, migration.version, e
                        ),
                    })?;
            }

            debug!(
                version = migration.version,
                count = pragma_statements.len(),
                "All PRAGMA statements executed successfully"
            );
        }

        // Start a transaction for regular SQL
        let mut tx = pool.begin().await.map_err(|e| AppError::DatabaseError {
            message: format!(
                "Failed to start transaction for migration {}: {}",
                migration.version, e
            ),
        })?;

        debug!(
            version = migration.version,
            "Transaction started for regular SQL execution"
        );

        // Execute the regular migration SQL
        if !regular_sql.trim().is_empty() {
            debug!(
                version = migration.version,
                sql_length = regular_sql.len(),
                "Executing regular migration SQL"
            );

            sqlx::query(&regular_sql)
                .execute(&mut *tx)
                .await
                .map_err(|e| AppError::DatabaseError {
                    message: format!(
                        "Failed to execute migration {} SQL: {}",
                        migration.version, e
                    ),
                })?;

            debug!(
                version = migration.version,
                "Regular migration SQL executed successfully"
            );
        } else {
            debug!(
                version = migration.version,
                "No regular SQL to execute, migration contains only PRAGMA statements"
            );
        }

        // Record the migration as applied
        debug!(
            version = migration.version,
            "Recording migration as applied"
        );

        sqlx::query("INSERT INTO __migrations (version, description) VALUES (?, ?)")
            .bind(migration.version)
            .bind(&migration.description)
            .execute(&mut *tx)
            .await
            .map_err(|e| AppError::DatabaseError {
                message: format!(
                    "Failed to record migration {} in tracking table: {}",
                    migration.version, e
                ),
            })?;

        // Commit the transaction
        debug!(
            version = migration.version,
            "Committing migration transaction"
        );

        tx.commit().await.map_err(|e| AppError::DatabaseError {
            message: format!(
                "Failed to commit migration {} transaction: {}",
                migration.version, e
            ),
        })?;

        let duration = start_time.elapsed();
        info!(
            version = migration.version,
            description = %migration.description,
            duration_ms = duration.as_millis(),
            "Migration completed successfully"
        );

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

    /// Validate migration SQL for common issues and safety
    pub fn validate_migration(&self, migration: &Migration) -> Vec<String> {
        let mut warnings = Vec::new();
        let sql = migration.sql.to_lowercase();

        // Check for potentially dangerous operations
        if sql.contains("drop table") && !sql.contains("if exists") {
            warnings.push(
                "DROP TABLE without IF EXISTS clause detected - high risk of data loss".to_string(),
            );
        }

        if sql.contains("alter table") && sql.contains("drop column") {
            warnings.push(
                "ALTER TABLE DROP COLUMN detected - will cause permanent data loss".to_string(),
            );
        }

        if sql.contains("truncate") {
            warnings
                .push("TRUNCATE statement detected - will delete all data from table".to_string());
        }

        if sql.contains("delete from") && !sql.contains("where") {
            warnings
                .push("DELETE without WHERE clause detected - will delete all records".to_string());
        }

        if sql.contains("update") && !sql.contains("where") {
            warnings
                .push("UPDATE without WHERE clause detected - will modify all records".to_string());
        }

        // Check for missing transaction handling (already handled by our apply_migration)
        if !sql.contains("begin")
            && !sql.contains("commit")
            && (sql.contains("insert") || sql.contains("update") || sql.contains("delete"))
        {
            warnings.push("Migration contains DML without explicit transaction (will be wrapped automatically)".to_string());
        }

        // Check for foreign key constraint issues
        if sql.contains("alter table")
            && sql.contains("add constraint")
            && sql.contains("foreign key")
        {
            warnings
                .push("Adding foreign key constraint - ensure referenced data exists".to_string());
        }

        // Check for index creation without IF NOT EXISTS
        if sql.contains("create index") && !sql.contains("if not exists") {
            warnings.push(
                "CREATE INDEX without IF NOT EXISTS - may fail if index already exists".to_string(),
            );
        }

        // Check for potential performance issues
        if sql.contains("alter table") && sql.contains("add column") && !sql.contains("default") {
            warnings.push("Adding column without DEFAULT value - may cause performance issues on large tables".to_string());
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

    /// Create a backup of the database before applying migrations
    pub async fn create_backup(&self, db_path: &str) -> AppResult<String> {
        use chrono::Utc;
        use std::fs;

        let db_path = Path::new(db_path);
        let backup_name = format!(
            "{}_backup_{}",
            db_path.file_stem().unwrap().to_string_lossy(),
            Utc::now().format("%Y%m%d_%H%M%S")
        );

        let backup_path = db_path.with_file_name(format!("{}.db", backup_name));

        info!(
            source = %db_path.display(),
            backup = %backup_path.display(),
            "Creating database backup before migration"
        );

        fs::copy(db_path, &backup_path).map_err(|e| AppError::DatabaseError {
            message: format!("Failed to create database backup: {}", e),
        })?;

        info!(
            backup_path = %backup_path.display(),
            "Database backup created successfully"
        );

        Ok(backup_path.to_string_lossy().to_string())
    }

    /// Validate all pending migrations before applying them
    pub async fn validate_pending_migrations(&self, pool: &SqlitePool) -> AppResult<Vec<String>> {
        let mut all_warnings = Vec::new();
        let applied_migrations = self.get_applied_migrations(pool).await?;
        let applied_versions: Vec<i32> = applied_migrations.iter().map(|(v, _)| *v).collect();

        for migration in &self.migrations {
            if !applied_versions.contains(&migration.version) {
                let warnings = self.validate_migration(migration);
                if !warnings.is_empty() {
                    all_warnings.push(format!(
                        "Migration {} ({}): {}",
                        migration.version,
                        migration.description,
                        warnings.join("; ")
                    ));
                }
            }
        }

        if !all_warnings.is_empty() {
            warn!(
                warnings_count = all_warnings.len(),
                "Migration validation warnings found"
            );
        }

        Ok(all_warnings)
    }

    /// Run migrations with safety checks and backup
    pub async fn run_migrations_safely(&self, pool: &SqlitePool, db_path: &str) -> AppResult<()> {
        info!("Starting safe migration process with validation and backup");

        // Validate pending migrations first
        let warnings = self.validate_pending_migrations(pool).await?;
        if !warnings.is_empty() {
            warn!(warnings = ?warnings, "Migration validation warnings detected");
            // In production, you might want to require explicit confirmation here
        }

        // Create backup before applying migrations
        let backup_path = self.create_backup(db_path).await?;
        info!(backup_path = %backup_path, "Backup created, proceeding with migrations");

        // Apply migrations
        match self.run_migrations(pool).await {
            Ok(()) => {
                info!("Migrations applied successfully");
                Ok(())
            }
            Err(e) => {
                warn!(
                    error = %e,
                    backup_path = %backup_path,
                    "Migration failed, backup available for recovery"
                );
                Err(e)
            }
        }
    }

    /// Check if database can be safely migrated
    pub async fn can_migrate_safely(&self, pool: &SqlitePool) -> AppResult<bool> {
        // Check database integrity first
        match sqlx::query_scalar::<_, String>("PRAGMA integrity_check")
            .fetch_one(pool)
            .await
        {
            Ok(result) if result == "ok" => {
                debug!("Database integrity check passed");
            }
            Ok(result) => {
                warn!(result = %result, "Database integrity check failed");
                return Ok(false);
            }
            Err(e) => {
                warn!(error = %e, "Failed to run integrity check");
                return Ok(false);
            }
        }

        // Check for foreign key violations
        match sqlx::query("PRAGMA foreign_key_check")
            .fetch_all(pool)
            .await
        {
            Ok(violations) if violations.is_empty() => {
                debug!("No foreign key violations found");
            }
            Ok(violations) => {
                warn!(
                    violation_count = violations.len(),
                    "Foreign key violations detected"
                );
                return Ok(false);
            }
            Err(e) => {
                warn!(error = %e, "Failed to check foreign keys");
                return Ok(false);
            }
        }

        // Check if there are any pending migrations with high-risk operations
        let warnings = self.validate_pending_migrations(pool).await?;
        let has_high_risk = warnings.iter().any(|w| {
            w.contains("data loss") || w.contains("delete all") || w.contains("DROP TABLE")
        });

        if has_high_risk {
            warn!("High-risk migration operations detected");
            return Ok(false);
        }

        Ok(true)
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
