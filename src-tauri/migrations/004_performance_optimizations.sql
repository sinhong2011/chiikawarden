-- Performance optimization migration
-- Add performance-critical indexes
CREATE INDEX IF NOT EXISTS idx_ciphers_created_date ON ciphers(created_date);

CREATE INDEX IF NOT EXISTS idx_ciphers_revision_date ON ciphers(revision_date);

CREATE INDEX IF NOT EXISTS idx_ciphers_favorite ON ciphers(favorite)
WHERE
  favorite = TRUE;

CREATE INDEX IF NOT EXISTS idx_ciphers_type ON ciphers(cipher_type);

CREATE INDEX IF NOT EXISTS idx_ciphers_user_name ON ciphers(user_id, name);

CREATE INDEX IF NOT EXISTS idx_ciphers_user_folder ON ciphers(user_id, folder_id);

CREATE INDEX IF NOT EXISTS idx_ciphers_active ON ciphers(user_id, deleted_date)
WHERE
  deleted_date IS NULL;

-- Add composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_folders_user_name ON folders(user_id, name);

CREATE INDEX IF NOT EXISTS idx_audit_log_user_action ON audit_log(user_id, ACTION);

CREATE INDEX IF NOT EXISTS idx_audit_log_resource ON audit_log(resource_type, resource_id);

CREATE INDEX IF NOT EXISTS idx_sessions_activity ON sessions(user_id, last_activity);

CREATE INDEX IF NOT EXISTS idx_sessions_active ON sessions(user_id, expires_at)
WHERE
  expires_at > datetime('now');

-- Add partial indexes for better performance
CREATE INDEX IF NOT EXISTS idx_ciphers_non_deleted ON ciphers(user_id, revision_date)
WHERE
  deleted_date IS NULL;

CREATE INDEX IF NOT EXISTS idx_ciphers_deleted ON ciphers(user_id, deleted_date)
WHERE
  deleted_date IS NOT NULL;

-- Add database configuration optimizations (SQLite-specific)
-- These PRAGMA statements are executed outside of transactions by the migration runner
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = 10000;
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 268435456; -- 256MB
-- Note: Check constraints would be added here, but SQLite doesn't support
-- adding named constraints via ALTER TABLE. These would need to be part
-- of the initial table creation.
-- Add triggers for automatic timestamp updates
CREATE TRIGGER IF NOT EXISTS update_ciphers_revision_date
AFTER
UPDATE
  ON ciphers BEGIN
UPDATE
  ciphers
SET
  revision_date = CURRENT_TIMESTAMP
WHERE
  id = NEW.id;

END;

CREATE TRIGGER IF NOT EXISTS update_folders_revision_date
AFTER
UPDATE
  ON folders BEGIN
UPDATE
  folders
SET
  revision_date = CURRENT_TIMESTAMP
WHERE
  id = NEW.id;

END;

CREATE TRIGGER IF NOT EXISTS update_users_revision_date
AFTER
UPDATE
  ON users BEGIN
UPDATE
  users
SET
  revision_date = CURRENT_TIMESTAMP
WHERE
  id = NEW.id;

END;

-- Settings trigger removed - settings now managed by tauri-plugin-store



-- Add database statistics table for performance monitoring
CREATE TABLE IF NOT EXISTS db_stats (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  operation TEXT NOT NULL,
  duration_ms INTEGER NOT NULL,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_db_stats_table_operation ON db_stats(table_name, operation);

CREATE INDEX IF NOT EXISTS idx_db_stats_timestamp ON db_stats(timestamp);

-- Analyze tables for better query planning
ANALYZE;