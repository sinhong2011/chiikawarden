# Bitwarden API Best Practices Summary - Tauri + SolidJS

## Overview

This document summarizes the best practices for implementing Bitwarden API integration in a Tauri + SolidJS desktop application. **All API communication must go through the Rust backend** for security, performance, and reliability.

## Core Principles

### 1. Security-First Architecture

```
✅ CORRECT: SolidJS Frontend → invoke() → Rust Backend → Bitwarden API
❌ WRONG:   SolidJS Frontend → fetch() → Bitwarden API
```

**Why Rust Backend is Required:**
- **Token Security**: Access tokens never exposed to frontend JavaScript
- **Encryption**: All crypto operations performed in secure Rust environment  
- **System Integration**: Access to keychain, file system, native APIs
- **Performance**: Native crypto operations are faster than WebCrypto

### 2. API Client Architecture

#### Rust Backend (src-tauri/src/api/client.rs)
```rust
pub struct BitwardenApiClient {
    client: reqwest::Client,
    base_url: String,
    token_store: Arc<RwLock<Option<String>>>,
}

impl BitwardenApiClient {
    // Secure token management
    pub async fn set_access_token(&self, token: String) { /* ... */ }
    
    // Automatic token refresh
    async fn refresh_token(&self) -> Result<(), ApiError> { /* ... */ }
    
    // Core request method with retry logic
    async fn make_authenticated_request<T, R>(&self, /* ... */) -> Result<R, ApiError> { /* ... */ }
}
```

#### Frontend Service Layer (src/services/api.service.ts)
```typescript
export class BitwardenApiService {
    // All methods delegate to Tauri commands
    async prelogin(email: string): Promise<PreloginResponse> {
        return await invoke('api_prelogin', { email });
    }
    
    async login(email: string, passwordHash: string): Promise<AuthResponse> {
        return await invoke('api_login', { email, passwordHash });
    }
    
    async syncVault(): Promise<SyncResponse> {
        return await invoke('api_sync_vault');
    }
}
```

## API Implementation Patterns

### 1. Authentication Flow

#### Tauri Commands
```rust
#[tauri::command]
pub async fn auth_prelogin(email: String) -> Result<PreloginResponse, String> { /* ... */ }

#[tauri::command] 
pub async fn auth_login(email: String, password_hash: String) -> Result<AuthResponse, String> { /* ... */ }

#[tauri::command]
pub async fn auth_logout() -> Result<(), String> { /* ... */ }
```

#### Frontend Usage
```typescript
// Complete login flow
const handleLogin = async () => {
    // 1. Get KDF settings
    const kdf = await invoke('auth_prelogin', { email });
    
    // 2. Hash password (in Rust for security)
    const hash = await invoke('crypto_hash_password', { password, ...kdf });
    
    // 3. Authenticate
    const auth = await invoke('auth_login', { email, passwordHash: hash });
    
    // 4. Update UI state
    setAuthState('isAuthenticated', true);
};
```

### 2. Vault Synchronization

#### Tauri Commands
```rust
#[tauri::command]
pub async fn sync_vault() -> Result<SyncResult, String> {
    // 1. Fetch from API
    // 2. Decrypt data
    // 3. Update local database
    // 4. Return result
}

#[tauri::command]
pub async fn sync_vault_with_progress(app_handle: tauri::AppHandle) -> Result<SyncResult, String> {
    // Emit progress events during sync
    app_handle.emit_all("sync_progress", progress).unwrap();
}
```

#### Frontend Usage
```typescript
// Sync with progress updates
const syncVault = async () => {
    // Listen for progress events
    listen('sync_progress', (event) => {
        setSyncProgress(event.payload.percentage);
    });
    
    // Trigger sync
    await invoke('sync_vault_with_progress');
};
```

### 3. Cipher Management

#### Tauri Commands
```rust
#[tauri::command]
pub async fn get_all_ciphers() -> Result<Vec<CipherView>, String> { /* ... */ }

#[tauri::command]
pub async fn save_cipher(cipher: CipherRequest) -> Result<CipherResponse, String> { /* ... */ }

#[tauri::command]
pub async fn delete_cipher(id: String) -> Result<(), String> { /* ... */ }
```

#### Frontend Usage
```typescript
// Reactive cipher list
const [ciphers] = createResource(
    searchQuery,
    async (query) => {
        if (query) {
            return await invoke('search_ciphers', { query });
        } else {
            return await invoke('get_all_ciphers');
        }
    }
);
```

## Error Handling Best Practices

### Structured Error Types (Rust)
```rust
#[derive(Debug, thiserror::Error, Serialize)]
pub enum ApiError {
    #[error("Authentication failed: {message}")]
    AuthenticationError { message: String },
    
    #[error("Network error {status}: {message}")]
    NetworkError { status: u16, message: String },
    
    #[error("Encryption error: {operation}")]
    CryptographyError { operation: String },
}
```

### Frontend Error Handling
```typescript
const handleApiError = (errorJson: string) => {
    try {
        const error = JSON.parse(errorJson);
        
        if (error.AuthenticationError) {
            // Handle auth errors
            navigate('/login');
        } else if (error.NetworkError) {
            // Handle network errors
            showToast(`Network error: ${error.NetworkError.message}`);
        }
    } catch {
        // Fallback for non-JSON errors
        showToast(errorJson);
    }
};
```

## Performance Optimizations

### 1. Local Database Caching
```rust
#[tauri::command]
pub async fn get_ciphers_cached() -> Result<Vec<CipherView>, String> {
    // Try local database first
    if let Ok(cached) = database.get_ciphers().await {
        return Ok(cached);
    }
    
    // Fallback to API
    let api_ciphers = fetch_from_api().await?;
    database.store_ciphers(&api_ciphers).await?;
    Ok(api_ciphers)
}
```

### 2. Batch Operations
```rust
#[tauri::command]
pub async fn batch_update_ciphers(updates: Vec<CipherUpdate>) -> Result<BatchResult, String> {
    let mut transaction = database.begin_transaction().await?;
    
    for update in updates {
        process_cipher_update(&mut transaction, update).await?;
    }
    
    transaction.commit().await?;
    Ok(BatchResult { updated_count: updates.len() })
}
```

### 3. Background Services
```rust
pub struct AutoSyncService {
    interval: Duration,
    is_running: Arc<AtomicBool>,
}

impl AutoSyncService {
    pub async fn start(&self, app_handle: tauri::AppHandle) {
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(self.interval);
            
            while self.is_running.load(Ordering::Relaxed) {
                interval.tick().await;
                
                if let Ok(changes) = perform_background_sync().await {
                    app_handle.emit_all("vault_updated", changes).unwrap();
                }
            }
        });
    }
}
```

## Security Checklist

### ✅ Required Security Measures
- [ ] All API calls go through Rust backend
- [ ] Access tokens stored in system keychain (never in frontend)
- [ ] All encryption/decryption performed in Rust
- [ ] Automatic token refresh implemented
- [ ] Secure error handling (no sensitive data in error messages)
- [ ] Input validation on all API parameters
- [ ] HTTPS-only communication
- [ ] Proper session management

### ❌ Security Anti-Patterns to Avoid
- [ ] Direct API calls from frontend JavaScript
- [ ] Storing tokens in localStorage/sessionStorage
- [ ] Performing crypto operations in frontend
- [ ] Exposing raw API responses to frontend
- [ ] Hardcoding API credentials
- [ ] Logging sensitive data
- [ ] Trusting frontend input without validation

## Testing Strategy

### Backend Testing (Rust)
```rust
#[tokio::test]
async fn test_login_success() {
    let result = auth_login("test@example.com".to_string(), "hash".to_string()).await;
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_encryption_roundtrip() {
    let plaintext = "sensitive data";
    let encrypted = encrypt_string(plaintext.to_string(), key).await.unwrap();
    let decrypted = decrypt_string(encrypted, key).await.unwrap();
    assert_eq!(plaintext, decrypted);
}
```

### Frontend Testing (SolidJS)
```typescript
// Mock Tauri invoke
const mockInvoke = vi.fn();
vi.mock('@tauri-apps/api/tauri', () => ({ invoke: mockInvoke }));

test('login form calls correct Tauri command', async () => {
    mockInvoke.mockResolvedValue({ access_token: 'token' });
    
    render(() => <LoginForm />);
    
    fireEvent.click(screen.getByText('Login'));
    
    expect(mockInvoke).toHaveBeenCalledWith('auth_login', {
        email: 'test@example.com',
        passwordHash: 'hashed_password'
    });
});
```

## Migration from Direct API Calls

### Before (Insecure)
```typescript
// ❌ WRONG
const response = await fetch('https://api.bitwarden.com/sync', {
    headers: { 'Authorization': `Bearer ${token}` }
});
```

### After (Secure)
```typescript
// ✅ CORRECT
const syncResult = await invoke('sync_vault');
```

This architecture ensures your Bitwarden desktop client is secure, performant, and maintainable while leveraging the full power of both Rust and SolidJS.
