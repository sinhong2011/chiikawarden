-- Initial database schema for Chiikawarden
-- Users table
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    encrypted_private_key TEXT,
    encrypted_user_key TEXT,
    kdf_type INTEGER NOT NULL DEFAULT 0,
    kdf_iterations INTEGER NOT NULL DEFAULT 600000,
    kdf_memory INTEGER,
    kdf_parallelism INTEGER,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    revision_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Ciphers table for encrypted vault items
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

-- Sync state table
CREATE TABLE IF NOT EXISTS sync_state (
    user_id TEXT PRIMARY KEY,
    last_sync DATETIME,
    revision_date DATETIME,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Settings table removed - now using tauri-plugin-store for settings persistence
-- Settings are stored in JSON format in the app data directory
-- This provides better cross-platform compatibility and easier maintenance

-- Performance indices
CREATE INDEX IF NOT EXISTS idx_ciphers_user_id ON ciphers(user_id);

CREATE INDEX IF NOT EXISTS idx_ciphers_folder_id ON ciphers(folder_id);

CREATE INDEX IF NOT EXISTS idx_ciphers_organization_id ON ciphers(organization_id);

CREATE INDEX IF NOT EXISTS idx_ciphers_deleted_date ON ciphers(deleted_date);

CREATE INDEX IF NOT EXISTS idx_ciphers_name ON ciphers(name);

CREATE INDEX IF NOT EXISTS idx_folders_user_id ON folders(user_id);

CREATE INDEX IF NOT EXISTS idx_collections_organization_id ON collections(organization_id);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);