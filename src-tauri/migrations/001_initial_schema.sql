-- Complete consolidated database schema for Chiikawarden
-- This schema includes all tables, columns, indexes, triggers, and optimizations
-- from the original migration sequence (001, 002, 003) consolidated into a single file
-- for pre-release development phase to eliminate migration inconsistencies
-- Users table with new key management structure (BREAKING CHANGE)
-- This eliminates MAC verification failures by using proper key management patterns
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    master_key_hash TEXT,
    -- BREAKING: New key management fields replace old encrypted_private_key and encrypted_user_key
    encrypted_private_key_new TEXT,
    encrypted_user_key_new TEXT,
    key_derivation_method TEXT DEFAULT 'server_provided',
    device_trust_enabled BOOLEAN DEFAULT FALSE,
    webauthn_enabled BOOLEAN DEFAULT FALSE,
    server_provider_id TEXT NOT NULL DEFAULT 'us-cloud',
    kdf_type INTEGER NOT NULL DEFAULT 0,
    kdf_iterations INTEGER NOT NULL DEFAULT 600000,
    kdf_memory INTEGER,
    kdf_parallelism INTEGER,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    revision_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Trusted devices table for RSA-based device trust system
CREATE TABLE IF NOT EXISTS trusted_devices (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_identifier TEXT NOT NULL UNIQUE,
    device_name TEXT,
    device_type TEXT DEFAULT 'desktop',
    encrypted_device_public_key TEXT NOT NULL,
    encrypted_device_private_key TEXT NOT NULL,
    encrypted_user_key TEXT NOT NULL,
    device_key_encrypted TEXT NOT NULL,
    trust_established_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_used_at DATETIME,
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- WebAuthn credentials table for WebAuthn PRF support
CREATE TABLE IF NOT EXISTS webauthn_credentials (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    credential_id TEXT NOT NULL UNIQUE,
    public_key TEXT NOT NULL,
    counter INTEGER DEFAULT 0,
    prf_salt TEXT,
    name TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_used_at DATETIME,
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Key operations log for comprehensive audit logging
CREATE TABLE IF NOT EXISTS key_operations_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    operation_type TEXT NOT NULL,
    -- 'derive', 'rotate', 'validate', 'device_trust', 'webauthn'
    operation_method TEXT NOT NULL,
    -- 'server_key', 'device_trust', 'webauthn_prf'
    success BOOLEAN NOT NULL,
    error_code TEXT,
    error_message TEXT,
    correlation_id TEXT NOT NULL,
    duration_ms INTEGER,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Organization keys table for multi-organization support
CREATE TABLE IF NOT EXISTS organization_keys (
    id TEXT PRIMARY KEY,
    organization_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    encrypted_organization_key TEXT NOT NULL,
    key_type TEXT DEFAULT 'organization',
    -- 'organization', 'collection'
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Ciphers table for encrypted vault items with encryption metadata
CREATE TABLE IF NOT EXISTS ciphers (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    organization_id TEXT,
    folder_id TEXT,
    name TEXT NOT NULL,
    notes TEXT,
    cipher_type INTEGER NOT NULL,
    encrypted_data TEXT NOT NULL,
    favorite BOOLEAN DEFAULT FALSE,
    reprompt BOOLEAN DEFAULT FALSE,
    revision_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    deleted_date DATETIME,
    enc_type INTEGER NOT NULL DEFAULT 2,
    mac TEXT,
    key_id TEXT,
    nonce TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE
    SET
        NULL
);

-- Folders table
CREATE TABLE IF NOT EXISTS folders (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    revision_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Collections table for organization data
CREATE TABLE IF NOT EXISTS collections (
    id TEXT PRIMARY KEY,
    organization_id TEXT NOT NULL,
    name TEXT NOT NULL,
    external_id TEXT,
    revision_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Sync state table with real-time sync extensions
CREATE TABLE IF NOT EXISTS sync_state (
    user_id TEXT PRIMARY KEY,
    last_sync DATETIME,
    revision_date DATETIME,
    -- Real-time sync extensions from migration 002
    is_syncing BOOLEAN DEFAULT FALSE,
    last_websocket_connection DATETIME,
    websocket_connected BOOLEAN DEFAULT FALSE,
    background_sync_enabled BOOLEAN DEFAULT TRUE,
    sync_interval_hours INTEGER DEFAULT 6,
    last_server_notification DATETIME,
    server_revision_date DATETIME,
    network_state TEXT DEFAULT 'unknown',
    last_online_sync DATETIME,
    cached_items_count INTEGER DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Audit trail table for security tracking
CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    ACTION TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    resource_id TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    ip_address TEXT,
    user_agent TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Session tracking table
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    expires_at DATETIME NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_activity DATETIME DEFAULT CURRENT_TIMESTAMP,
    device_info TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Database statistics table for performance monitoring
CREATE TABLE IF NOT EXISTS db_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    duration_ms INTEGER NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Real-time sync settings table for user preferences (from migration 002)
CREATE TABLE IF NOT EXISTS sync_settings (
    user_id TEXT PRIMARY KEY,
    realtime_sync_enabled BOOLEAN DEFAULT TRUE,
    background_sync_enabled BOOLEAN DEFAULT TRUE,
    sync_interval_hours INTEGER DEFAULT 6,
    websocket_reconnect_enabled BOOLEAN DEFAULT TRUE,
    max_reconnect_attempts INTEGER DEFAULT 10,
    sync_on_network_change BOOLEAN DEFAULT TRUE,
    sync_on_app_focus BOOLEAN DEFAULT TRUE,
    battery_optimization_enabled BOOLEAN DEFAULT TRUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- WebSocket connection tracking table (from migration 002)
CREATE TABLE IF NOT EXISTS websocket_connections (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    connection_id TEXT NOT NULL,
    server_url TEXT NOT NULL,
    connected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    disconnected_at DATETIME,
    last_ping DATETIME,
    last_pong DATETIME,
    reconnect_count INTEGER DEFAULT 0,
    STATUS TEXT DEFAULT 'connecting',
    -- 'connecting', 'connected', 'disconnected', 'error'
    error_message TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Sync events log for debugging and monitoring (from migration 002)
CREATE TABLE IF NOT EXISTS sync_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    -- 'sync_started', 'sync_completed', 'server_notification', etc.
    event_source TEXT NOT NULL,
    -- 'manual', 'background', 'websocket', 'login'
    item_type TEXT,
    -- 'cipher', 'folder', 'collection', 'vault'
    item_id TEXT,
    details TEXT,
    -- JSON details about the event
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    duration_ms INTEGER,
    success BOOLEAN,
    error_message TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Settings table removed - now using tauri-plugin-store for settings persistence
-- Settings are stored in JSON format in the app data directory
-- This provides better cross-platform compatibility and easier maintenance
-- Comprehensive performance indexes from all migrations
-- Basic indexes
CREATE INDEX IF NOT EXISTS idx_ciphers_user_id ON ciphers(user_id);

CREATE INDEX IF NOT EXISTS idx_ciphers_folder_id ON ciphers(folder_id);

CREATE INDEX IF NOT EXISTS idx_ciphers_organization_id ON ciphers(organization_id);

CREATE INDEX IF NOT EXISTS idx_ciphers_deleted_date ON ciphers(deleted_date);

CREATE INDEX IF NOT EXISTS idx_ciphers_name ON ciphers(name);

CREATE INDEX IF NOT EXISTS idx_folders_user_id ON folders(user_id);

CREATE INDEX IF NOT EXISTS idx_collections_organization_id ON collections(organization_id);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- User authentication indexes
CREATE INDEX IF NOT EXISTS idx_users_master_key_hash ON users(master_key_hash);

CREATE INDEX IF NOT EXISTS idx_users_key_derivation_method ON users(key_derivation_method);

CREATE INDEX IF NOT EXISTS idx_users_device_trust_enabled ON users(device_trust_enabled);

CREATE INDEX IF NOT EXISTS idx_users_webauthn_enabled ON users(webauthn_enabled);

-- Key management indexes
CREATE INDEX IF NOT EXISTS idx_trusted_devices_user_id ON trusted_devices(user_id);

CREATE INDEX IF NOT EXISTS idx_trusted_devices_device_identifier ON trusted_devices(device_identifier);

CREATE INDEX IF NOT EXISTS idx_webauthn_credentials_user_id ON webauthn_credentials(user_id);

CREATE INDEX IF NOT EXISTS idx_webauthn_credentials_credential_id ON webauthn_credentials(credential_id);

CREATE INDEX IF NOT EXISTS idx_key_operations_log_user_id ON key_operations_log(user_id);

CREATE INDEX IF NOT EXISTS idx_key_operations_log_timestamp ON key_operations_log(timestamp);

CREATE INDEX IF NOT EXISTS idx_organization_keys_user_id ON organization_keys(user_id);

CREATE INDEX IF NOT EXISTS idx_organization_keys_org_id ON organization_keys(organization_id);

-- Audit log and session indexes
CREATE INDEX IF NOT EXISTS idx_audit_log_user_id ON audit_log(user_id);

CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON audit_log(timestamp);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);

CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at);

-- Real-time sync indexes (from migration 002)
-- WebSocket connections indexes
CREATE INDEX IF NOT EXISTS idx_websocket_connections_user_id ON websocket_connections(user_id);

CREATE INDEX IF NOT EXISTS idx_websocket_connections_status ON websocket_connections(STATUS);

CREATE INDEX IF NOT EXISTS idx_websocket_connections_connected_at ON websocket_connections(connected_at);

CREATE INDEX IF NOT EXISTS idx_websocket_connections_active ON websocket_connections(user_id, STATUS)
WHERE
    STATUS = 'connected';

-- Sync events indexes
CREATE INDEX IF NOT EXISTS idx_sync_events_user_id ON sync_events(user_id);

CREATE INDEX IF NOT EXISTS idx_sync_events_timestamp ON sync_events(timestamp);

CREATE INDEX IF NOT EXISTS idx_sync_events_type ON sync_events(event_type);

CREATE INDEX IF NOT EXISTS idx_sync_events_source ON sync_events(event_source);

CREATE INDEX IF NOT EXISTS idx_sync_events_user_type ON sync_events(user_id, event_type);

CREATE INDEX IF NOT EXISTS idx_sync_events_item ON sync_events(item_type, item_id);

-- Extended sync_state indexes for real-time sync
CREATE INDEX IF NOT EXISTS idx_sync_state_is_syncing ON sync_state(is_syncing)
WHERE
    is_syncing = TRUE;

CREATE INDEX IF NOT EXISTS idx_sync_state_websocket_connected ON sync_state(websocket_connected)
WHERE
    websocket_connected = TRUE;

-- Performance optimization indexes
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

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_folders_user_name ON folders(user_id, name);

CREATE INDEX IF NOT EXISTS idx_audit_log_user_action ON audit_log(user_id, ACTION);

CREATE INDEX IF NOT EXISTS idx_audit_log_resource ON audit_log(resource_type, resource_id);

CREATE INDEX IF NOT EXISTS idx_sessions_activity ON sessions(user_id, last_activity);

CREATE INDEX IF NOT EXISTS idx_sessions_active ON sessions(user_id, expires_at)
WHERE
    expires_at > datetime('now');

-- Partial indexes for better performance
CREATE INDEX IF NOT EXISTS idx_ciphers_non_deleted ON ciphers(user_id, revision_date)
WHERE
    deleted_date IS NULL;

CREATE INDEX IF NOT EXISTS idx_ciphers_deleted ON ciphers(user_id, deleted_date)
WHERE
    deleted_date IS NOT NULL;

-- Database statistics indexes
CREATE INDEX IF NOT EXISTS idx_db_stats_table_operation ON db_stats(table_name, operation);

CREATE INDEX IF NOT EXISTS idx_db_stats_timestamp ON db_stats(timestamp);

-- Automatic timestamp update triggers
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

-- Real-time sync triggers (from migration 002)
-- Update sync_settings updated_at trigger
CREATE TRIGGER IF NOT EXISTS update_sync_settings_updated_at
AFTER
UPDATE
    ON sync_settings BEGIN
UPDATE
    sync_settings
SET
    updated_at = CURRENT_TIMESTAMP
WHERE
    user_id = NEW.user_id;

END;

-- Cleanup old sync events trigger (keep only last 30 days)
CREATE TRIGGER IF NOT EXISTS cleanup_old_sync_events
AFTER
INSERT
    ON sync_events BEGIN
DELETE FROM
    sync_events
WHERE
    timestamp < datetime('now', '-30 days');

END;

-- SQLite performance optimizations are now handled by apply_performance_optimizations() in core.rs
-- This ensures they are applied after the connection is established, not during migration