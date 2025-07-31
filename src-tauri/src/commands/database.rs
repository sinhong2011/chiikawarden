use crate::app_state::AppState;
use crate::error::AppResult;
use crate::storage::database::{dev_utils, health};
use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::{command, State};
use tracing::{debug, info};

/// Database health status response
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct DatabaseHealthResponse {
    pub health: health::DatabaseHealth,
    pub timestamp: String,
}

/// Database statistics response
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct DatabaseStatsResponse {
    pub stats: dev_utils::DatabaseStats,
    pub timestamp: String,
}

/// Database schema inspection response
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct DatabaseSchemaResponse {
    pub schema: dev_utils::SchemaInfo,
    pub timestamp: String,
}

/// Get database health status
#[command]
#[specta::specta]
pub async fn get_database_health(state: State<'_, AppState>) -> AppResult<DatabaseHealthResponse> {
    debug!("Getting database health status");
    
    let health = state.database.check_health().await?;
    let timestamp = chrono::Utc::now().to_rfc3339();
    
    info!(
        overall_status = ?health.overall_status,
        recommendations_count = health.recommendations.len(),
        "Database health check completed"
    );
    
    Ok(DatabaseHealthResponse { health, timestamp })
}

/// Get database statistics (development only)
#[cfg(debug_assertions)]
#[command]
#[specta::specta]
pub async fn get_database_stats(state: State<'_, AppState>) -> AppResult<DatabaseStatsResponse> {
    debug!("Getting database statistics");
    
    let stats = state.database.collect_statistics().await?;
    let timestamp = chrono::Utc::now().to_rfc3339();
    
    info!(
        total_size_mb = stats.total_size_mb,
        table_count = stats.table_stats.len(),
        "Database statistics collected"
    );
    
    Ok(DatabaseStatsResponse { stats, timestamp })
}

/// Inspect database schema (development only)
#[cfg(debug_assertions)]
#[command]
#[specta::specta]
pub async fn inspect_database_schema(state: State<'_, AppState>) -> AppResult<DatabaseSchemaResponse> {
    debug!("Inspecting database schema");
    
    let schema = state.database.inspect_schema().await?;
    let timestamp = chrono::Utc::now().to_rfc3339();
    
    info!(
        table_count = schema.tables.len(),
        index_count = schema.indexes.len(),
        trigger_count = schema.triggers.len(),
        view_count = schema.views.len(),
        "Database schema inspection completed"
    );
    
    Ok(DatabaseSchemaResponse { schema, timestamp })
}

/// Optimize database (development only)
#[cfg(debug_assertions)]
#[command]
#[specta::specta]
pub async fn optimize_database(state: State<'_, AppState>) -> AppResult<String> {
    info!("Starting database optimization");
    
    state.database.optimize_database().await?;
    let timestamp = chrono::Utc::now().to_rfc3339();
    
    info!("Database optimization completed successfully");
    
    Ok(format!("Database optimization completed at {}", timestamp))
}

/// Reset database (development only)
#[cfg(debug_assertions)]
#[command]
#[specta::specta]
pub async fn reset_database(state: State<'_, AppState>) -> AppResult<String> {
    use tracing::warn;
    
    warn!("Resetting database - all data will be lost!");
    
    state.database.reset_database().await?;
    let timestamp = chrono::Utc::now().to_rfc3339();
    
    warn!("Database reset completed");
    
    Ok(format!("Database reset completed at {}", timestamp))
}

/// Generate sample data (development only)
#[cfg(debug_assertions)]
#[command]
#[specta::specta]
pub async fn generate_sample_data(state: State<'_, AppState>) -> AppResult<String> {
    info!("Generating sample data for development");
    
    state.database.generate_sample_data().await?;
    let timestamp = chrono::Utc::now().to_rfc3339();
    
    info!("Sample data generation completed");
    
    Ok(format!("Sample data generated at {}", timestamp))
}

/// Migration status information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct MigrationStatusResponse {
    pub current_version: i32,
    pub latest_version: i32,
    pub applied_migrations: Vec<(i32, String)>,
    pub pending_migrations: Vec<i32>,
    pub is_up_to_date: bool,
    pub timestamp: String,
}

/// Get migration status
#[command]
#[specta::specta]
pub async fn get_migration_status(state: State<'_, AppState>) -> AppResult<MigrationStatusResponse> {
    debug!("Getting migration status");
    
    // We need to access the migration runner through the database
    // For now, we'll use the health check which includes migration status
    let health = state.database.check_health().await?;
    let timestamp = chrono::Utc::now().to_rfc3339();
    
    let migration_status = &health.migration_status;
    
    Ok(MigrationStatusResponse {
        current_version: migration_status.current_version,
        latest_version: migration_status.latest_version,
        applied_migrations: migration_status.applied_migrations.clone(),
        pending_migrations: migration_status.pending_migrations.clone(),
        is_up_to_date: migration_status.pending_migrations.is_empty(),
        timestamp,
    })
}

/// Database maintenance operations
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct MaintenanceResult {
    pub operation: String,
    pub success: bool,
    pub message: String,
    pub timestamp: String,
}

/// Run database maintenance (VACUUM and ANALYZE)
#[command]
#[specta::specta]
pub async fn run_database_maintenance(state: State<'_, AppState>) -> AppResult<MaintenanceResult> {
    info!("Running database maintenance operations");
    
    let timestamp = chrono::Utc::now().to_rfc3339();
    
    #[cfg(debug_assertions)]
    {
        match state.database.optimize_database().await {
            Ok(()) => {
                info!("Database maintenance completed successfully");
                Ok(MaintenanceResult {
                    operation: "maintenance".to_string(),
                    success: true,
                    message: "Database maintenance (VACUUM and ANALYZE) completed successfully".to_string(),
                    timestamp,
                })
            }
            Err(e) => {
                Ok(MaintenanceResult {
                    operation: "maintenance".to_string(),
                    success: false,
                    message: format!("Database maintenance failed: {}", e),
                    timestamp,
                })
            }
        }
    }

    #[cfg(not(debug_assertions))]
    {
        info!("Database maintenance is only available in debug builds");
        Ok(MaintenanceResult {
            operation: "maintenance".to_string(),
            success: false,
            message: "Database maintenance is only available in debug builds".to_string(),
            timestamp,
        })
    }
}

/// Check if database is initialized
#[command]
#[specta::specta]
pub async fn is_database_initialized(state: State<'_, AppState>) -> AppResult<bool> {
    Ok(state.database.is_initialized().await)
}

/// Get database file path
#[command]
#[specta::specta]
pub async fn get_database_path(state: State<'_, AppState>) -> AppResult<String> {
    Ok(state.database.get_db_path().to_string())
}
