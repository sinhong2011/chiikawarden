use crate::error::AppResult;
use serde::{Deserialize, Serialize};
use specta::Type;
use sqlx::{sqlite::SqlitePool, Row};
use std::collections::HashMap;
use tracing::{debug, info, warn};

/// Database health check results
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct DatabaseHealth {
    pub overall_status: HealthStatus,
    pub connection_status: HealthStatus,
    pub migration_status: MigrationHealthStatus,
    pub integrity_status: IntegrityStatus,
    pub performance_metrics: PerformanceMetrics,
    pub recommendations: Vec<String>,
}

/// Health status enumeration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Type)]
pub enum HealthStatus {
    Healthy,
    Warning,
    Critical,
    Unknown,
}

/// Migration-specific health status
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct MigrationHealthStatus {
    pub status: HealthStatus,
    pub current_version: i32,
    pub latest_version: i32,
    pub pending_migrations: Vec<i32>,
    pub applied_migrations: Vec<(i32, String)>,
}

/// Database integrity status
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct IntegrityStatus {
    pub status: HealthStatus,
    pub integrity_check_result: String,
    pub foreign_key_violations: Vec<String>,
    pub missing_indexes: Vec<String>,
    pub orphaned_records: HashMap<String, i32>,
}

/// Performance metrics
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct PerformanceMetrics {
    pub database_size_mb: f64,
    pub page_count: i32,
    pub page_size: i32,
    pub cache_hit_ratio: Option<f64>,
    pub slow_queries: Vec<String>,
    pub index_usage: HashMap<String, IndexUsage>,
}

/// Index usage statistics
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct IndexUsage {
    pub name: String,
    pub table: String,
    pub usage_count: i32,
    pub last_used: Option<String>,
}

/// Database health checker
pub struct DatabaseHealthChecker;

impl DatabaseHealthChecker {
    /// Perform comprehensive database health check
    pub async fn check_health(pool: &SqlitePool) -> AppResult<DatabaseHealth> {
        info!("Starting comprehensive database health check");

        let connection_status = Self::check_connection(pool).await?;
        let migration_status = Self::check_migrations(pool).await?;
        let integrity_status = Self::check_integrity(pool).await?;
        let performance_metrics = Self::collect_performance_metrics(pool).await?;

        let overall_status = Self::determine_overall_status(&[
            &connection_status,
            &migration_status.status,
            &integrity_status.status,
        ]);

        let recommendations = Self::generate_recommendations(
            &connection_status,
            &migration_status,
            &integrity_status,
            &performance_metrics,
        );

        let health = DatabaseHealth {
            overall_status,
            connection_status,
            migration_status,
            integrity_status,
            performance_metrics,
            recommendations,
        };

        info!(
            overall_status = ?health.overall_status,
            recommendations_count = health.recommendations.len(),
            "Database health check completed"
        );

        Ok(health)
    }

    /// Check database connection health
    async fn check_connection(pool: &SqlitePool) -> AppResult<HealthStatus> {
        debug!("Checking database connection health");

        match sqlx::query_scalar::<_, i32>("SELECT 1").fetch_one(pool).await {
            Ok(1) => {
                debug!("Database connection is healthy");
                Ok(HealthStatus::Healthy)
            }
            Ok(_) => {
                warn!("Database connection returned unexpected result");
                Ok(HealthStatus::Warning)
            }
            Err(e) => {
                warn!(error = %e, "Database connection failed");
                Ok(HealthStatus::Critical)
            }
        }
    }

    /// Check migration status
    async fn check_migrations(pool: &SqlitePool) -> AppResult<MigrationHealthStatus> {
        debug!("Checking migration status");

        // Get migration runner to compare with applied migrations
        let migration_runner = super::migrations::MigrationRunner::new();
        let latest_version = migration_runner.get_latest_version();

        // Get applied migrations
        let applied_migrations = match migration_runner.get_applied_migrations(pool).await {
            Ok(migrations) => migrations,
            Err(_) => {
                return Ok(MigrationHealthStatus {
                    status: HealthStatus::Critical,
                    current_version: 0,
                    latest_version,
                    pending_migrations: vec![],
                    applied_migrations: vec![],
                });
            }
        };

        let current_version = applied_migrations
            .iter()
            .map(|(v, _)| *v)
            .max()
            .unwrap_or(0);

        let applied_versions: Vec<i32> = applied_migrations.iter().map(|(v, _)| *v).collect();
        let pending_migrations: Vec<i32> = migration_runner
            .get_migrations()
            .iter()
            .map(|m| m.version)
            .filter(|v| !applied_versions.contains(v))
            .collect();

        let status = if pending_migrations.is_empty() {
            // If no pending migrations, the database is up to date regardless of version numbers
            // This handles cases where migrations were consolidated or version numbers changed
            HealthStatus::Healthy
        } else {
            // If there are pending migrations, it's a warning that needs attention
            HealthStatus::Warning
        };

        Ok(MigrationHealthStatus {
            status,
            current_version,
            latest_version,
            pending_migrations,
            applied_migrations,
        })
    }

    /// Check database integrity
    async fn check_integrity(pool: &SqlitePool) -> AppResult<IntegrityStatus> {
        debug!("Checking database integrity");

        // Run SQLite integrity check
        let integrity_result = match sqlx::query_scalar::<_, String>("PRAGMA integrity_check")
            .fetch_one(pool)
            .await
        {
            Ok(result) => result,
            Err(e) => {
                warn!(error = %e, "Failed to run integrity check");
                return Ok(IntegrityStatus {
                    status: HealthStatus::Critical,
                    integrity_check_result: format!("Failed to run integrity check: {}", e),
                    foreign_key_violations: vec![],
                    missing_indexes: vec![],
                    orphaned_records: HashMap::new(),
                });
            }
        };

        // Check foreign key constraints
        let fk_violations = Self::check_foreign_keys(pool).await?;

        // Check for missing critical indexes
        let missing_indexes = Self::check_critical_indexes(pool).await?;

        // Check for orphaned records
        let orphaned_records = Self::check_orphaned_records(pool).await?;

        let status = if integrity_result == "ok" && fk_violations.is_empty() && missing_indexes.is_empty() {
            if orphaned_records.is_empty() {
                HealthStatus::Healthy
            } else {
                HealthStatus::Warning
            }
        } else {
            HealthStatus::Critical
        };

        Ok(IntegrityStatus {
            status,
            integrity_check_result: integrity_result,
            foreign_key_violations: fk_violations,
            missing_indexes,
            orphaned_records,
        })
    }

    /// Check foreign key constraints
    async fn check_foreign_keys(pool: &SqlitePool) -> AppResult<Vec<String>> {
        debug!("Checking foreign key constraints");

        // Enable foreign key checking temporarily
        sqlx::query("PRAGMA foreign_keys = ON").execute(pool).await?;

        let violations = match sqlx::query("PRAGMA foreign_key_check").fetch_all(pool).await {
            Ok(rows) => rows
                .iter()
                .map(|row| {
                    format!(
                        "Table: {}, Row: {}, Parent: {}, Key: {}",
                        row.get::<String, _>(0),
                        row.get::<i64, _>(1),
                        row.get::<String, _>(2),
                        row.get::<i64, _>(3)
                    )
                })
                .collect(),
            Err(_) => vec![],
        };

        Ok(violations)
    }

    /// Check for missing critical indexes
    async fn check_critical_indexes(pool: &SqlitePool) -> AppResult<Vec<String>> {
        debug!("Checking for missing critical indexes");

        let critical_indexes = vec![
            "idx_users_email",
            "idx_users_master_key_hash",
            "idx_ciphers_user_id",
            "idx_ciphers_folder_id",
            "idx_audit_log_user_id",
            "idx_sessions_user_id",
        ];

        let existing_indexes: Vec<String> = sqlx::query_scalar(
            "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
        )
        .fetch_all(pool)
        .await?;

        let missing: Vec<String> = critical_indexes
            .into_iter()
            .filter(|idx| !existing_indexes.contains(&idx.to_string()))
            .map(|s| s.to_string())
            .collect();

        if !missing.is_empty() {
            warn!(missing_indexes = ?missing, "Critical indexes are missing");
        }

        Ok(missing)
    }

    /// Check for orphaned records
    async fn check_orphaned_records(pool: &SqlitePool) -> AppResult<HashMap<String, i32>> {
        debug!("Checking for orphaned records");

        let mut orphaned = HashMap::new();

        // Check for ciphers without users
        if let Ok(count) = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM ciphers WHERE user_id NOT IN (SELECT id FROM users)"
        )
        .fetch_one(pool)
        .await
        {
            if count > 0 {
                orphaned.insert("ciphers_without_users".to_string(), count as i32);
            }
        }

        // Check for folders without users
        if let Ok(count) = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM folders WHERE user_id NOT IN (SELECT id FROM users)"
        )
        .fetch_one(pool)
        .await
        {
            if count > 0 {
                orphaned.insert("folders_without_users".to_string(), count as i32);
            }
        }

        Ok(orphaned)
    }

    /// Collect performance metrics
    async fn collect_performance_metrics(pool: &SqlitePool) -> AppResult<PerformanceMetrics> {
        debug!("Collecting performance metrics");

        let page_count = sqlx::query_scalar::<_, i64>("PRAGMA page_count")
            .fetch_one(pool)
            .await
            .unwrap_or(0) as i32;

        let page_size = sqlx::query_scalar::<_, i64>("PRAGMA page_size")
            .fetch_one(pool)
            .await
            .unwrap_or(4096) as i32;

        let database_size_mb = (page_count as i64 * page_size as i64) as f64 / (1024.0 * 1024.0);

        Ok(PerformanceMetrics {
            database_size_mb,
            page_count,
            page_size,
            cache_hit_ratio: None, // SQLite doesn't provide this easily
            slow_queries: vec![], // Would need query logging to implement
            index_usage: HashMap::new(), // Would need statistics collection
        })
    }

    /// Determine overall health status
    fn determine_overall_status(statuses: &[&HealthStatus]) -> HealthStatus {
        if statuses.iter().any(|s| **s == HealthStatus::Critical) {
            HealthStatus::Critical
        } else if statuses.iter().any(|s| **s == HealthStatus::Warning) {
            HealthStatus::Warning
        } else if statuses.iter().all(|s| **s == HealthStatus::Healthy) {
            HealthStatus::Healthy
        } else {
            HealthStatus::Unknown
        }
    }

    /// Generate health recommendations
    fn generate_recommendations(
        connection_status: &HealthStatus,
        migration_status: &MigrationHealthStatus,
        integrity_status: &IntegrityStatus,
        performance_metrics: &PerformanceMetrics,
    ) -> Vec<String> {
        let mut recommendations = Vec::new();

        if *connection_status != HealthStatus::Healthy {
            recommendations.push("Database connection issues detected. Check database file permissions and disk space.".to_string());
        }

        if !migration_status.pending_migrations.is_empty() {
            recommendations.push(format!(
                "Apply pending migrations: {:?}",
                migration_status.pending_migrations
            ));
        }

        if !integrity_status.foreign_key_violations.is_empty() {
            recommendations.push("Fix foreign key constraint violations before they cause data corruption.".to_string());
        }

        if !integrity_status.missing_indexes.is_empty() {
            recommendations.push(format!(
                "Create missing critical indexes: {:?}",
                integrity_status.missing_indexes
            ));
        }

        if !integrity_status.orphaned_records.is_empty() {
            recommendations.push("Clean up orphaned records to maintain data consistency.".to_string());
        }

        if performance_metrics.database_size_mb > 100.0 {
            recommendations.push("Consider database maintenance: VACUUM and ANALYZE operations.".to_string());
        }

        if recommendations.is_empty() {
            recommendations.push("Database is healthy. No immediate actions required.".to_string());
        }

        recommendations
    }
}
