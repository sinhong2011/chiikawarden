# Tauri Backend Logic Guide: What Goes Where?

## Overview

This guide helps you understand the separation of concerns between Tauri's Rust backend and the SolidJS frontend in the Bitwarden desktop application. Understanding this division is crucial for building a secure, performant, and maintainable application.

## Architecture Principles

### Frontend (SolidJS) Responsibilities
- **UI State Management**: Component state, form validation, UI interactions
- **Presentation Logic**: Data formatting, display logic, user experience
- **Client-side Routing**: Navigation, route guards, URL management
- **UI-specific Caching**: Component-level caching, temporary UI state

### Backend (Tauri/Rust) Responsibilities
- **Security Operations**: Encryption, authentication, secure storage
- **System Integration**: File system, OS APIs, native features
- **Business Logic**: Core application logic, data validation
- **Performance-Critical Operations**: Heavy computations, crypto operations

## Detailed Breakdown

### 1. Authentication & Security Logic

#### ✅ Tauri Backend (Rust)
```rust
#[tauri::command]
pub async fn login(email: String, password: String) -> Result<AuthResponse, String> {
    // ✅ Password hashing and verification
    let password_hash = hash_password(&password, &salt)?;

    // ✅ API communication with Bitwarden servers
    let auth_response = api_client.authenticate(email, password_hash).await?;

    // ✅ Secure token storage in system keychain
    keyring::set_password("bitwarden", &email, &auth_response.access_token)?;

    // ✅ Session management
    session_manager.create_session(auth_response.user_id).await?;

    Ok(auth_response)
}

#[tauri::command]
pub async fn derive_master_key(password: String, salt: Vec<u8>) -> Result<Vec<u8>, String> {
    // ✅ CPU-intensive key derivation (Argon2/PBKDF2)
    argon2::hash_password_verify(&password, &salt, 100_000)
}

#[tauri::command]
pub async fn setup_biometric_auth(user_id: String) -> Result<bool, String> {
    // ✅ Platform-specific biometric setup
    #[cfg(target_os = "macos")]
    return setup_touch_id(&user_id).await;

    #[cfg(target_os = "windows")]
    return setup_windows_hello(&user_id).await;
}
```

#### ❌ Frontend (SolidJS) - What NOT to do
```typescript
// ❌ Never store sensitive data in frontend
const [masterKey, setMasterKey] = createSignal("user-master-key"); // WRONG!

// ❌ Never perform crypto operations in frontend
const hashPassword = (password: string) => {
    return btoa(password); // WRONG! Insecure
};

// ❌ Never handle raw authentication tokens
localStorage.setItem('access_token', token); // WRONG! Insecure storage
```

#### ✅ Frontend (SolidJS) - Correct approach
```typescript
// ✅ UI state and form handling only
const [loginForm, setLoginForm] = createStore({
    email: '',
    password: '',
    isLoading: false,
    errors: {}
});

const handleLogin = async () => {
    setLoginForm('isLoading', true);

    try {
        // ✅ Delegate to Tauri backend
        const result = await invoke('login', {
            email: loginForm.email,
            password: loginForm.password
        });

        // ✅ Handle UI state changes only
        setAuthState('isAuthenticated', true);
        navigate('/vault');
    } catch (error) {
        setLoginForm('errors', { general: error.message });
    } finally {
        setLoginForm('isLoading', false);
    }
};
```

### 2. Data Management & Storage

#### ✅ Tauri Backend (Rust)
```rust
#[tauri::command]
pub async fn save_cipher(cipher_data: CipherData) -> Result<(), String> {
    // ✅ Data validation and sanitization
    validate_cipher_data(&cipher_data)?;

    // ✅ Encryption before storage
    let encrypted_data = encrypt_cipher_data(&cipher_data).await?;

    // ✅ Database operations
    database.insert_cipher(encrypted_data).await?;

    // ✅ Sync with Bitwarden servers
    sync_service.upload_cipher(&cipher_data).await?;

    Ok(())
}

#[tauri::command]
pub async fn get_vault_data(user_id: String) -> Result<VaultData, String> {
    // ✅ Fetch from secure local database
    let encrypted_ciphers = database.get_user_ciphers(&user_id).await?;

    // ✅ Decrypt data
    let decrypted_ciphers = decrypt_ciphers(encrypted_ciphers).await?;

    // ✅ Apply business logic (filtering, sorting)
    let filtered_ciphers = apply_vault_filters(decrypted_ciphers);

    Ok(VaultData { ciphers: filtered_ciphers })
}
```

#### ✅ Frontend (SolidJS)
```typescript
// ✅ UI state management and caching
const [vaultState, setVaultState] = createStore({
    ciphers: [],
    folders: [],
    isLoading: false,
    searchQuery: '',
    selectedFolder: null
});

// ✅ UI-specific filtering and sorting
const filteredCiphers = createMemo(() => {
    return vaultState.ciphers.filter(cipher => {
        const matchesSearch = cipher.name.toLowerCase().includes(vaultState.searchQuery.toLowerCase());
        const matchesFolder = !vaultState.selectedFolder || cipher.folderId === vaultState.selectedFolder;
        return matchesSearch && matchesFolder;
    });
});

// ✅ Data fetching coordination
const loadVaultData = async () => {
    setVaultState('isLoading', true);

    try {
        const vaultData = await invoke('get_vault_data', { userId: currentUser().id });
        setVaultState('ciphers', vaultData.ciphers);
    } catch (error) {
        showToast('Failed to load vault data');
    } finally {
        setVaultState('isLoading', false);
    }
};
```

### 3. System Integration

#### ✅ Tauri Backend (Rust)
```rust
#[tauri::command]
pub async fn export_vault(format: String, file_path: String) -> Result<(), String> {
    // ✅ File system operations
    let vault_data = get_vault_data_for_export().await?;

    // ✅ Data serialization
    let exported_data = match format.as_str() {
        "json" => serde_json::to_string_pretty(&vault_data)?,
        "csv" => serialize_to_csv(&vault_data)?,
        _ => return Err("Unsupported format".to_string()),
    };

    // ✅ Secure file writing
    tokio::fs::write(&file_path, exported_data).await?;

    Ok(())
}

#[tauri::command]
pub async fn setup_auto_launch(enabled: bool) -> Result<(), String> {
    // ✅ OS-specific auto-launch configuration
    #[cfg(target_os = "windows")]
    {
        let registry_key = "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run";
        if enabled {
            windows_registry::set_value(registry_key, "Bitwarden", get_exe_path())?;
        } else {
            windows_registry::delete_value(registry_key, "Bitwarden")?;
        }
    }

    #[cfg(target_os = "macos")]
    {
        // Handle macOS launch agents
        setup_macos_launch_agent(enabled).await?;
    }

    Ok(())
}
```

### 4. Network & API Communication

#### ✅ Tauri Backend (Rust)
```rust
#[tauri::command]
pub async fn sync_vault() -> Result<SyncResult, String> {
    // ✅ HTTP client management
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()?;

    // ✅ Authentication header management
    let access_token = get_stored_access_token().await?;

    // ✅ API request with retry logic
    let response = retry_with_backoff(|| {
        client.get("https://api.bitwarden.com/sync")
            .bearer_auth(&access_token)
            .send()
    }).await?;

    // ✅ Response processing and error handling
    let sync_data: SyncResponse = response.json().await?;

    // ✅ Local database updates
    update_local_vault(sync_data).await?;

    Ok(SyncResult { last_sync: Utc::now() })
}
```

#### ✅ Frontend (SolidJS)
```typescript
// ✅ Sync coordination and UI updates
const [syncState, setSyncState] = createStore({
    isSync: false,
    lastSync: null,
    error: null
});

const triggerSync = async () => {
    setSyncState('isSyncing', true);
    setSyncState('error', null);

    try {
        const result = await invoke('sync_vault');
        setSyncState('lastSync', result.last_sync);

        // ✅ Refresh UI data after sync
        await loadVaultData();

        showToast('Vault synced successfully');
    } catch (error) {
        setSyncState('error', error.message);
        showToast('Sync failed: ' + error.message);
    } finally {
        setSyncState('isSyncing', false);
    }
};
```

## Decision Matrix

| Operation Type | Frontend (SolidJS) | Backend (Tauri) | Reason |
|---|---|---|---|
| Form validation | ✅ Basic UI validation | ✅ Security validation | UI responsiveness + Security |
| Password hashing | ❌ Never | ✅ Always | Security requirement |
| File operations | ❌ No access | ✅ Full access | Sandbox limitations |
| UI state | ✅ Always | ❌ Never | Separation of concerns |
| Crypto operations | ❌ WebCrypto only | ✅ Native libraries | Performance + Security |
| Database queries | ❌ No direct access | ✅ Full access | Security + Architecture |
| System notifications | ❌ Limited | ✅ Full control | Native integration |
| Network requests | ❌ CORS limited | ✅ Full control | Security + Flexibility |

## Best Practices

### 1. Data Flow Pattern
```
Frontend → Tauri Command → Business Logic → Storage/API → Response → Frontend
```

### 2. Error Handling
- **Frontend**: Handle UI errors, show user-friendly messages
- **Backend**: Handle system errors, log detailed information, return safe error messages

### 3. State Management
- **Frontend**: UI state, temporary data, user preferences
- **Backend**: Persistent data, secure data, system state

### 4. Performance Considerations
- **CPU-intensive operations**: Always in Rust backend
- **UI updates**: Always in frontend
- **Data caching**: Backend for security, frontend for UI performance

## Common Mistakes to Avoid

1. **❌ Storing secrets in frontend**: Never store passwords, keys, or tokens in frontend state
2. **❌ Business logic in UI**: Keep business rules in the backend
3. **❌ Direct API calls from frontend**: Route all external communication through Tauri
4. **❌ File system access from frontend**: Use Tauri commands for all file operations
5. **❌ Heavy computations in frontend**: Move to Rust for better performance

This separation ensures security, performance, and maintainability while leveraging the strengths of both Rust and SolidJS.

## Advanced Patterns

### 1. Event-Driven Communication

#### Backend Events to Frontend
```rust
// Tauri backend - emit events to frontend
use tauri::Manager;

#[tauri::command]
pub async fn start_sync(app_handle: tauri::AppHandle) -> Result<(), String> {
    // Emit progress events during long operations
    app_handle.emit_all("sync_progress", SyncProgress {
        step: "Downloading vault data",
        percentage: 25
    }).unwrap();

    // Perform sync operation
    let result = perform_vault_sync().await?;

    app_handle.emit_all("sync_completed", result).unwrap();
    Ok(())
}

#[tauri::command]
pub async fn watch_file_changes(path: String, app_handle: tauri::AppHandle) -> Result<(), String> {
    // File system watching
    let (tx, rx) = tokio::sync::mpsc::channel(100);

    tokio::spawn(async move {
        let mut watcher = notify::recommended_watcher(move |res| {
            if let Ok(event) = res {
                let _ = tx.try_send(event);
            }
        }).unwrap();

        watcher.watch(Path::new(&path), RecursiveMode::Recursive).unwrap();

        while let Some(event) = rx.recv().await {
            app_handle.emit_all("file_changed", event).unwrap();
        }
    });

    Ok(())
}
```

#### Frontend Event Handling
```typescript
import { listen } from '@tauri-apps/api/event';

// Listen for backend events
const setupEventListeners = () => {
    // Sync progress updates
    listen('sync_progress', (event) => {
        setSyncState('progress', event.payload.percentage);
        setSyncState('currentStep', event.payload.step);
    });

    // Sync completion
    listen('sync_completed', (event) => {
        setSyncState('isComplete', true);
        setVaultState('lastSync', event.payload.timestamp);
        showToast('Vault synchronized successfully');
    });

    // File system changes
    listen('file_changed', (event) => {
        if (event.payload.path.includes('bitwarden-export')) {
            refreshExportsList();
        }
    });
};
```

### 2. Background Services Pattern

#### Long-Running Services in Rust
```rust
// Background service for auto-sync
pub struct AutoSyncService {
    interval: Duration,
    is_running: Arc<AtomicBool>,
}

impl AutoSyncService {
    pub async fn start(&self, app_handle: tauri::AppHandle) {
        let is_running = self.is_running.clone();
        let interval = self.interval;

        tokio::spawn(async move {
            let mut interval_timer = tokio::time::interval(interval);

            while is_running.load(Ordering::Relaxed) {
                interval_timer.tick().await;

                // Perform background sync
                match perform_background_sync().await {
                    Ok(changes) => {
                        if changes.has_updates {
                            app_handle.emit_all("vault_updated", changes).unwrap();
                        }
                    }
                    Err(e) => {
                        app_handle.emit_all("sync_error", e.to_string()).unwrap();
                    }
                }
            }
        });
    }
}

#[tauri::command]
pub async fn start_background_services(app_handle: tauri::AppHandle) -> Result<(), String> {
    // Auto-sync service
    let sync_service = AutoSyncService::new(Duration::from_secs(300)); // 5 minutes
    sync_service.start(app_handle.clone()).await;

    // Clipboard monitoring
    let clipboard_service = ClipboardMonitorService::new();
    clipboard_service.start(app_handle.clone()).await;

    Ok(())
}
```

### 3. Secure Configuration Management

#### Backend Configuration
```rust
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Serialize, Deserialize)]
pub struct AppConfig {
    pub vault_timeout: u32,
    pub auto_sync_interval: u32,
    pub theme: String,
    pub minimize_to_tray: bool,
    // Sensitive settings stored separately
}

#[derive(Serialize, Deserialize)]
struct SecureConfig {
    pub server_url: String,
    pub client_id: String,
    // Never expose these to frontend
}

#[tauri::command]
pub async fn get_app_settings() -> Result<AppConfig, String> {
    let config_path = get_config_path()?;
    let config_content = tokio::fs::read_to_string(config_path).await?;
    let config: AppConfig = serde_json::from_str(&config_content)?;
    Ok(config)
}

#[tauri::command]
pub async fn update_app_settings(settings: AppConfig) -> Result<(), String> {
    // Validate settings
    validate_app_config(&settings)?;

    // Save to secure location
    let config_path = get_config_path()?;
    let config_json = serde_json::to_string_pretty(&settings)?;
    tokio::fs::write(config_path, config_json).await?;

    // Apply settings immediately
    apply_runtime_settings(&settings).await?;

    Ok(())
}

fn get_config_path() -> Result<PathBuf, String> {
    let mut path = dirs::config_dir()
        .ok_or("Could not find config directory")?;
    path.push("bitwarden");
    path.push("config.json");
    Ok(path)
}
```

### 4. Error Handling Patterns

#### Structured Error Types
```rust
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Error, Debug, Serialize, Deserialize)]
pub enum BitwardenError {
    #[error("Authentication failed: {message}")]
    AuthenticationError { message: String },

    #[error("Network error: {status_code}")]
    NetworkError { status_code: u16, message: String },

    #[error("Encryption error: {operation}")]
    CryptographyError { operation: String },

    #[error("Storage error: {path}")]
    StorageError { path: String, source: String },

    #[error("Validation error: {field}")]
    ValidationError { field: String, message: String },
}

// Convert to string for Tauri command returns
impl From<BitwardenError> for String {
    fn from(error: BitwardenError) -> Self {
        serde_json::to_string(&error).unwrap_or_else(|_| error.to_string())
    }
}

#[tauri::command]
pub async fn login_with_detailed_errors(email: String, password: String) -> Result<AuthResponse, BitwardenError> {
    // Validate input
    if email.is_empty() {
        return Err(BitwardenError::ValidationError {
            field: "email".to_string(),
            message: "Email is required".to_string(),
        });
    }

    // Attempt authentication
    match authenticate_user(&email, &password).await {
        Ok(response) => Ok(response),
        Err(e) if e.status_code == 401 => Err(BitwardenError::AuthenticationError {
            message: "Invalid email or password".to_string(),
        }),
        Err(e) => Err(BitwardenError::NetworkError {
            status_code: e.status_code,
            message: e.message,
        }),
    }
}
```

#### Frontend Error Handling
```typescript
interface BitwardenError {
    AuthenticationError?: { message: string };
    NetworkError?: { status_code: number; message: string };
    CryptographyError?: { operation: string };
    StorageError?: { path: string; source: string };
    ValidationError?: { field: string; message: string };
}

const handleBitwardenError = (errorJson: string) => {
    try {
        const error: BitwardenError = JSON.parse(errorJson);

        if (error.AuthenticationError) {
            setLoginForm('errors', {
                email: error.AuthenticationError.message
            });
            return;
        }

        if (error.NetworkError) {
            if (error.NetworkError.status_code >= 500) {
                showToast('Server error. Please try again later.');
            } else {
                showToast(`Network error: ${error.NetworkError.message}`);
            }
            return;
        }

        if (error.ValidationError) {
            setLoginForm('errors', {
                [error.ValidationError.field]: error.ValidationError.message
            });
            return;
        }

        // Generic error handling
        showToast('An unexpected error occurred');

    } catch {
        // Fallback for non-JSON errors
        showToast(errorJson);
    }
};
```

### 5. Performance Optimization Patterns

#### Batch Operations
```rust
#[tauri::command]
pub async fn batch_update_ciphers(updates: Vec<CipherUpdate>) -> Result<BatchResult, String> {
    let mut results = Vec::new();
    let mut transaction = database.begin_transaction().await?;

    for update in updates {
        match process_cipher_update(&mut transaction, update).await {
            Ok(result) => results.push(result),
            Err(e) => {
                transaction.rollback().await?;
                return Err(format!("Batch update failed: {}", e));
            }
        }
    }

    transaction.commit().await?;

    Ok(BatchResult {
        updated_count: results.len(),
        results,
    })
}
```

#### Streaming Large Data
```rust
use futures::stream::{self, StreamExt};

#[tauri::command]
pub async fn export_large_vault(app_handle: tauri::AppHandle) -> Result<(), String> {
    let ciphers = get_all_ciphers().await?;
    let total_count = ciphers.len();

    // Process in chunks to avoid memory issues
    let chunk_size = 100;
    let mut processed = 0;

    let chunks = ciphers.chunks(chunk_size);

    for chunk in chunks {
        let exported_chunk = export_cipher_chunk(chunk).await?;
        write_export_chunk(&exported_chunk).await?;

        processed += chunk.len();
        let progress = (processed as f32 / total_count as f32) * 100.0;

        app_handle.emit_all("export_progress", ExportProgress {
            processed,
            total: total_count,
            percentage: progress,
        }).unwrap();
    }

    app_handle.emit_all("export_completed", ExportResult {
        file_path: get_export_path(),
        total_exported: processed,
    }).unwrap();

    Ok(())
}
```

## Testing Strategies

### Backend Testing
```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tokio_test;

    #[tokio::test]
    async fn test_login_success() {
        let result = login("test@example.com".to_string(), "password123".to_string()).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_encryption_roundtrip() {
        let plaintext = "sensitive data";
        let key = generate_test_key();

        let encrypted = encrypt_string(plaintext.to_string(), key.clone()).await.unwrap();
        let decrypted = decrypt_string(encrypted, key).await.unwrap();

        assert_eq!(plaintext, decrypted);
    }
}
```

### Frontend Testing
```typescript
import { render, screen, fireEvent, waitFor } from '@solidjs/testing-library';
import { vi } from 'vitest';

// Mock Tauri invoke
const mockInvoke = vi.fn();
vi.mock('@tauri-apps/api/tauri', () => ({
    invoke: mockInvoke
}));

test('login form handles success', async () => {
    mockInvoke.mockResolvedValue({ user_id: '123', access_token: 'token' });

    render(() => <LoginForm />);

    fireEvent.input(screen.getByLabelText('Email'), { target: { value: 'test@example.com' } });
    fireEvent.input(screen.getByLabelText('Password'), { target: { value: 'password' } });
    fireEvent.click(screen.getByText('Login'));

    await waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('login', {
            email: 'test@example.com',
            password: 'password'
        });
    });
});
```

This comprehensive guide should help you understand exactly what logic belongs in the Tauri backend versus the SolidJS frontend, with practical examples and patterns for building a secure, performant Bitwarden desktop application.
