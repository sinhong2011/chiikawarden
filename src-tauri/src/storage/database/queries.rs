/// SQL query constants for database operations
pub mod sql {
    // User queries
    pub const CREATE_USER: &str = r#"
        INSERT INTO users
        (id, email, master_key_hash, encrypted_private_key_new, encrypted_user_key_new, key_derivation_method,
         device_trust_enabled, webauthn_enabled, server_provider_id, kdf_type, kdf_iterations,
         kdf_memory, kdf_parallelism, created_date, revision_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    "#;

    pub const GET_USER_BY_ID: &str = r#"
        SELECT id, email, master_key_hash, encrypted_private_key_new, encrypted_user_key_new, key_derivation_method,
               device_trust_enabled, webauthn_enabled, server_provider_id, kdf_type, kdf_iterations,
               kdf_memory, kdf_parallelism, created_date, revision_date
        FROM users WHERE id = ?
    "#;

    pub const GET_USER_BY_EMAIL: &str = r#"
        SELECT id, email, master_key_hash, encrypted_private_key_new, encrypted_user_key_new, key_derivation_method,
               device_trust_enabled, webauthn_enabled, server_provider_id, kdf_type, kdf_iterations,
               kdf_memory, kdf_parallelism, created_date, revision_date
        FROM users WHERE email = ?
    "#;

    pub const GET_ALL_USERS: &str = r#"
        SELECT id, email, master_key_hash, encrypted_private_key_new, encrypted_user_key_new, key_derivation_method,
               device_trust_enabled, webauthn_enabled, server_provider_id, kdf_type, kdf_iterations,
               kdf_memory, kdf_parallelism, created_date, revision_date
        FROM users ORDER BY created_date ASC
    "#;

    pub const UPDATE_USER: &str = r#"
        UPDATE users SET
            email = ?, master_key_hash = ?, encrypted_private_key_new = ?, encrypted_user_key_new = ?,
            key_derivation_method = ?, device_trust_enabled = ?, webauthn_enabled = ?, server_provider_id = ?,
            kdf_type = ?, kdf_iterations = ?, kdf_memory = ?, kdf_parallelism = ?,
            revision_date = ?
        WHERE id = ?
    "#;

    pub const UPSERT_USER: &str = r#"
        INSERT OR REPLACE INTO users
        (id, email, master_key_hash, encrypted_private_key_new, encrypted_user_key_new, key_derivation_method,
         device_trust_enabled, webauthn_enabled, server_provider_id, kdf_type, kdf_iterations,
         kdf_memory, kdf_parallelism, created_date, revision_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    "#;

    // Cipher queries
    pub const SAVE_CIPHER: &str = r#"
        INSERT OR REPLACE INTO ciphers
        (id, user_id, organization_id, folder_id, name, notes, cipher_type, encrypted_data, favorite,
         revision_date, created_date, deleted_date, enc_type, mac)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    "#;

    pub const GET_ALL_CIPHERS: &str = r#"
        SELECT id, user_id, organization_id, folder_id, name, notes,
               cipher_type, encrypted_data, favorite,
               revision_date, created_date, deleted_date, enc_type, mac
        FROM ciphers
        WHERE user_id = ? AND deleted_date IS NULL
        ORDER BY name
    "#;

    pub const SEARCH_CIPHERS: &str = r#"
        SELECT id, user_id, organization_id, folder_id, name, notes,
               cipher_type, encrypted_data, favorite,
               revision_date, created_date, deleted_date, enc_type, mac
        FROM ciphers
        WHERE user_id = ? AND deleted_date IS NULL
        AND (name LIKE ? OR notes LIKE ? OR encrypted_data LIKE ?)
        ORDER BY 
            CASE 
                WHEN name LIKE ? THEN 1
                WHEN notes LIKE ? THEN 2
                WHEN encrypted_data LIKE ? THEN 3
                ELSE 4
            END,
            name
    "#;

    pub const GET_CIPHERS_BY_FOLDER: &str = r#"
        SELECT id, user_id, organization_id, folder_id, name, notes,
               cipher_type, encrypted_data, favorite,
               revision_date, created_date, deleted_date, enc_type, mac
        FROM ciphers
        WHERE user_id = ? AND folder_id = ? AND deleted_date IS NULL
        ORDER BY name
    "#;

    pub const GET_FAVORITE_CIPHERS: &str = r#"
        SELECT id, user_id, organization_id, folder_id, name, notes,
               cipher_type, encrypted_data, favorite,
               revision_date, created_date, deleted_date, enc_type, mac
        FROM ciphers
        WHERE user_id = ? AND favorite = 1 AND deleted_date IS NULL
        ORDER BY name
    "#;

    pub const DELETE_CIPHER: &str = r#"
        UPDATE ciphers SET deleted_date = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ?
    "#;

    // Folder queries
    pub const GET_FOLDERS: &str = r#"
        SELECT id, user_id, name, revision_date FROM folders WHERE user_id = ?
    "#;

    pub const SAVE_FOLDER: &str = r#"
        INSERT OR REPLACE INTO folders (id, user_id, name, revision_date) VALUES (?, ?, ?, ?)
    "#;

    pub const DELETE_FOLDER: &str = r#"
        DELETE FROM folders WHERE id = ? AND user_id = ?
    "#;

    // Collection queries
    pub const GET_COLLECTIONS: &str = r#"
        SELECT id, organization_id, name, external_id, revision_date FROM collections WHERE organization_id = ?
    "#;

    // Sync state queries
    pub const GET_SYNC_STATE: &str = r#"
        SELECT user_id, last_sync, revision_date FROM sync_state WHERE user_id = ?
    "#;

    pub const SAVE_SYNC_STATE: &str = r#"
        INSERT OR REPLACE INTO sync_state (user_id, last_sync, revision_date) VALUES (?, ?, ?)
    "#;

    pub const CLEAR_SYNC_STATE: &str = r#"
        DELETE FROM sync_state WHERE user_id = ?
    "#;

    // Settings queries removed - now using tauri-plugin-store

    // Statistics queries
    pub const COUNT_CIPHERS: &str = r#"
        SELECT COUNT(*) as count FROM ciphers WHERE user_id = ? AND deleted_date IS NULL
    "#;

    pub const COUNT_FOLDERS: &str = r#"
        SELECT COUNT(*) as count FROM folders WHERE user_id = ?
    "#;

    pub const COUNT_DELETED_CIPHERS: &str = r#"
        SELECT COUNT(*) as count FROM ciphers WHERE user_id = ? AND deleted_date IS NOT NULL
    "#;

    // Utility queries
    pub const CHECK_CONNECTION: &str = "SELECT 1 as test";
    pub const GET_USER_VERSION: &str = "PRAGMA user_version";
    pub const GET_PAGE_COUNT: &str = "PRAGMA page_count";
    pub const GET_PAGE_SIZE: &str = "PRAGMA page_size";
    pub const CHECK_INTEGRITY: &str = "PRAGMA integrity_check";
    pub const CHECK_TABLE_EXISTS: &str =
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?";
}

/// Query builder utilities
pub mod builder {
    use serde_json::Value;

    /// Build a dynamic search query with conditions
    pub fn build_advanced_search_query(
        query: Option<&str>,
        folder_id: Option<&str>,
        organization_id: Option<&str>,
        cipher_type: Option<i32>,
        favorites_only: bool,
    ) -> (String, Vec<Value>) {
        let mut conditions = vec![
            "user_id = ?".to_string(),
            "deleted_date IS NULL".to_string(),
        ];
        let mut params = vec![]; // Note: user_id will be added by caller

        if let Some(q) = query {
            conditions.push("(name LIKE ? OR notes LIKE ? OR encrypted_data LIKE ?)".to_string());
            let search_pattern = format!("%{}%", q);
            params.push(Value::String(search_pattern.clone()));
            params.push(Value::String(search_pattern.clone()));
            params.push(Value::String(search_pattern.clone()));
        }

        if let Some(fid) = folder_id {
            conditions.push("folder_id = ?".to_string());
            params.push(Value::String(fid.to_string()));
        }

        if let Some(oid) = organization_id {
            conditions.push("organization_id = ?".to_string());
            params.push(Value::String(oid.to_string()));
        }

        if let Some(ct) = cipher_type {
            conditions.push("cipher_type = ?".to_string());
            params.push(Value::Number(ct.into()));
        }

        if favorites_only {
            conditions.push("favorite = 1".to_string());
        }

        let sql = format!(
            r#"
            SELECT id, user_id, organization_id, folder_id, name, notes,
                   cipher_type, encrypted_data, favorite,
                   revision_date, created_date, deleted_date, enc_type, mac
            FROM ciphers
            WHERE {}
            ORDER BY name
            "#,
            conditions.join(" AND ")
        );

        (sql, params)
    }

    /// Build a batch delete query
    pub fn build_batch_delete_query(table: &str, id_column: &str, ids: &[String]) -> String {
        let placeholders = ids.iter().map(|_| "?").collect::<Vec<_>>().join(",");
        format!(
            "UPDATE {} SET deleted_date = CURRENT_TIMESTAMP WHERE {} IN ({})",
            table, id_column, placeholders
        )
    }

    /// Build a batch update query
    pub fn build_batch_update_query(
        table: &str,
        set_clause: &str,
        where_column: &str,
        ids: &[String],
    ) -> String {
        let placeholders = ids.iter().map(|_| "?").collect::<Vec<_>>().join(",");
        format!(
            "UPDATE {} SET {} WHERE {} IN ({})",
            table, set_clause, where_column, placeholders
        )
    }
}
