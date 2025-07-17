# Bitwarden API Integration Guide for Tauri + SolidJS

## Overview

This guide provides **best practices** for integrating with the Bitwarden API in your Tauri + SolidJS desktop client. All API calls should be handled in the Rust backend for security, performance, and reliability.

## Architecture Principles

### ✅ Correct Pattern: Frontend → Tauri Commands → API
```
SolidJS Frontend → invoke('api_command') → Rust Backend → Bitwarden API
```

### ❌ Incorrect Pattern: Direct API Calls
```
SolidJS Frontend → fetch() → Bitwarden API (NEVER DO THIS)
```

## Secure API Client Setup

### 1. Rust Backend API Client (src-tauri/src/api/client.rs)

```rust
use reqwest::{Client, header::{HeaderMap, HeaderValue, AUTHORIZATION, CONTENT_TYPE}};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::sync::RwLock;
use std::sync::Arc;

#[derive(Debug, Clone)]
pub struct BitwardenApiClient {
    client: Client,
    base_url: String,
    token_store: Arc<RwLock<Option<String>>>,
}

impl BitwardenApiClient {
    pub fn new(base_url: String) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent("Bitwarden-Desktop/1.0.0")
            .build()
            .expect("Failed to create HTTP client");

        Self {
            client,
            base_url,
            token_store: Arc::new(RwLock::new(None)),
        }
    }

    // Secure token management - never expose tokens to frontend
    pub async fn set_access_token(&self, token: String) {
        let mut token_guard = self.token_store.write().await;
        *token_guard = Some(token);
    }

    pub async fn clear_token(&self) {
        let mut token_guard = self.token_store.write().await;
        *token_guard = None;
    }

    // Core request method with automatic token refresh
    async fn make_authenticated_request<T, R>(
        &self,
        method: reqwest::Method,
        endpoint: &str,
        body: Option<T>
    ) -> Result<R, ApiError>
    where
        T: Serialize,
        R: for<'de> Deserialize<'de>,
    {
        let url = format!("{}{}", self.base_url, endpoint);
        let mut request = self.client.request(method.clone(), &url);

        // Add authentication header
        {
            let token_guard = self.token_store.read().await;
            if let Some(token) = token_guard.as_ref() {
                request = request.bearer_auth(token);
            }
        }

        // Add body if provided
        if let Some(data) = body {
            request = request.json(&data);
        }

        let response = request.send().await?;

        // Handle token expiration
        if response.status() == 401 {
            // Attempt token refresh
            if self.refresh_token().await.is_ok() {
                // Retry request with new token
                return self.make_authenticated_request(method, endpoint, None).await;
            }
            return Err(ApiError::Unauthorized);
        }

        if !response.status().is_success() {
            return Err(ApiError::HttpError {
                status: response.status().as_u16(),
                message: response.text().await.unwrap_or_default(),
            });
        }

        Ok(response.json().await?)
    }

    // Token refresh logic
    async fn refresh_token(&self) -> Result<(), ApiError> {
        let refresh_token = get_stored_refresh_token().await?;

        let refresh_request = RefreshTokenRequest {
            refresh_token,
        };

        let response: TokenResponse = self.make_authenticated_request(
            reqwest::Method::POST,
            "/accounts/token",
            Some(refresh_request)
        ).await?;

        // Store new tokens securely
        store_access_token(&response.access_token).await?;
        if let Some(new_refresh_token) = response.refresh_token {
            store_refresh_token(&new_refresh_token).await?;
        }

        // Update in-memory token
        self.set_access_token(response.access_token).await;

        Ok(())
    }
}

// Error types for better error handling
#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("HTTP request failed: {0}")]
    Request(#[from] reqwest::Error),

    #[error("Unauthorized - token expired or invalid")]
    Unauthorized,

    #[error("HTTP error {status}: {message}")]
    HttpError { status: u16, message: String },

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Token storage error: {0}")]
    TokenStorage(String),
}
```

### 2. Tauri Commands (src-tauri/src/api/commands.rs)

```rust
use tauri::State;
use std::sync::Arc;

// Global API client state
pub type ApiClientState = Arc<BitwardenApiClient>;

#[tauri::command]
pub async fn api_prelogin(
    email: String,
    api_client: State<'_, ApiClientState>
) -> Result<PreloginResponse, String> {
    let request = PreloginRequest { email };

    api_client
        .make_authenticated_request(
            reqwest::Method::POST,
            "/accounts/prelogin",
            Some(request)
        )
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn api_login(
    email: String,
    master_password_hash: String,
    api_client: State<'_, ApiClientState>
) -> Result<AuthResponse, String> {
    let request = LoginRequest {
        email,
        master_password_hash,
        device_type: 6, // Desktop
        device_name: get_device_name()?,
        device_identifier: get_device_identifier()?,
    };

    let response: AuthResponse = api_client
        .make_authenticated_request(
            reqwest::Method::POST,
            "/accounts/login",
            Some(request)
        )
        .await
        .map_err(|e| e.to_string())?;

    // Store tokens securely in system keychain
    store_access_token(&response.access_token).await?;
    if let Some(refresh_token) = &response.refresh_token {
        store_refresh_token(refresh_token).await?;
    }

    // Update API client token
    api_client.set_access_token(response.access_token.clone()).await;

    Ok(response)
}

#[tauri::command]
pub async fn api_sync_vault(
    api_client: State<'_, ApiClientState>
) -> Result<SyncResponse, String> {
    api_client
        .make_authenticated_request(
            reqwest::Method::GET,
            "/sync?excludeDomains=true",
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())
}
```

### 3. Frontend API Service (src/services/api.service.ts)

```typescript
import { invoke } from '@tauri-apps/api/tauri';

// ✅ CORRECT: All API calls go through Tauri commands
export class BitwardenApiService {
  // Authentication APIs
  async prelogin(email: string): Promise<PreloginResponse> {
    return await invoke('api_prelogin', { email });
  }

  async login(email: string, masterPasswordHash: string): Promise<AuthResponse> {
    return await invoke('api_login', {
      email,
      masterPasswordHash
    });
  }

  async logout(): Promise<void> {
    return await invoke('api_logout');
  }

  // Vault APIs
  async syncVault(): Promise<SyncResponse> {
    return await invoke('api_sync_vault');
  }

  async getCiphers(): Promise<CipherResponse[]> {
    return await invoke('api_get_ciphers');
  }

  async saveCipher(cipher: CipherRequest): Promise<CipherResponse> {
    return await invoke('api_save_cipher', { cipher });
  }

  async deleteCipher(id: string): Promise<void> {
    return await invoke('api_delete_cipher', { id });
  }

  // Folder APIs
  async getFolders(): Promise<FolderResponse[]> {
    return await invoke('api_get_folders');
  }

  async saveFolder(folder: FolderRequest): Promise<FolderResponse> {
    return await invoke('api_save_folder', { folder });
  }
  ): Promise<T> {
    return await invoke('api_request', {
      method,
      endpoint,
      data,
      requiresAuth,
    });
  }

  // Authentication
  async prelogin(email: string): Promise<PreloginResponse> {
    return this.makeRequest('POST', '/accounts/prelogin', { email }, false);
  }

  async login(request: PasswordTokenRequest): Promise<TokenResponse> {
    return this.makeRequest('POST', '/identity/connect/token', request, false);
  }

  async sendPasswordHint(email: string): Promise<void> {
    return this.makeRequest('POST', '/accounts/password-hint', { email }, false);
  }

  // Profile
  async getProfile(): Promise<ProfileResponse> {
    return this.makeRequest('GET', '/accounts/profile');
  }

  async updateProfile(request: UpdateProfileRequest): Promise<ProfileResponse> {
    return this.makeRequest('PUT', '/accounts/profile', request);
  }

  // Sync
  async sync(): Promise<SyncResponse> {
    return this.makeRequest('GET', '/sync?excludeDomains=true');
  }

  // Ciphers
  async getCiphers(): Promise<ListResponse<CipherResponse>> {
    return this.makeRequest('GET', '/ciphers');
  }

  async getCipher(id: string): Promise<CipherResponse> {
    return this.makeRequest('GET', `/ciphers/${id}`);
  }

  async createCipher(request: CipherRequest): Promise<CipherResponse> {
    return this.makeRequest('POST', '/ciphers', request);
  }

  async updateCipher(id: string, request: CipherRequest): Promise<CipherResponse> {
    return this.makeRequest('PUT', `/ciphers/${id}`, request);
  }

  async deleteCipher(id: string): Promise<void> {
    return this.makeRequest('DELETE', `/ciphers/${id}`);
  }

  // Folders
  async getFolders(): Promise<ListResponse<FolderResponse>> {
    return this.makeRequest('GET', '/folders');
  }

  async createFolder(request: FolderRequest): Promise<FolderResponse> {
    return this.makeRequest('POST', '/folders', request);
  }

  async updateFolder(id: string, request: FolderRequest): Promise<FolderResponse> {
    return this.makeRequest('PUT', `/folders/${id}`, request);
  }

  async deleteFolder(id: string): Promise<void> {
    return this.makeRequest('DELETE', `/folders/${id}`);
  }
}
```

## Type Definitions

### 3. Core Types (TypeScript)

```typescript
// src/types/api.types.ts

// Authentication Types
export interface PreloginResponse {
  kdf: number;
  kdfIterations: number;
  kdfMemory?: number;
  kdfParallelism?: number;
}

export interface PasswordTokenRequest {
  grant_type: 'password';
  username: string;
  password: string;
  scope: string;
  client_id: string;
  deviceType: number;
  deviceIdentifier: string;
  deviceName: string;
  twoFactorToken?: string;
  twoFactorProvider?: number;
  twoFactorRemember?: number;
}

export interface TokenResponse {
  access_token: string;
  expires_in: number;
  token_type: string;
  refresh_token: string;
  scope: string;
  Kdf: number;
  KdfIterations: number;
  KdfMemory?: number;
  KdfParallelism?: number;
  ResetMasterPassword: boolean;
  PrivateKey?: string;
  Key: string;
  TwoFactorToken?: string;
  MasterPasswordPolicy?: any;
}

// Cipher Types
export interface CipherResponse {
  id: string;
  organizationId?: string;
  folderId?: string;
  type: CipherType;
  name: string;
  notes?: string;
  favorite: boolean;
  organizationUseTotp: boolean;
  edit: boolean;
  viewPassword: boolean;
  revisionDate: string;
  creationDate: string;
  deletedDate?: string;
  reprompt: RepromptType;
  login?: LoginResponse;
  secureNote?: SecureNoteResponse;
  card?: CardResponse;
  identity?: IdentityResponse;
  sshKey?: SshKeyResponse;
  fields?: FieldResponse[];
  attachments?: AttachmentResponse[];
  passwordHistory?: PasswordHistoryResponse[];
  collectionIds?: string[];
  key?: string;
  object: 'cipher';
}

export enum CipherType {
  Login = 1,
  SecureNote = 2,
  Card = 3,
  Identity = 4,
  SshKey = 5,
}

export enum RepromptType {
  None = 0,
  Password = 1,
}

export interface LoginResponse {
  username?: string;
  password?: string;
  passwordRevisionDate?: string;
  totp?: string;
  autofillOnPageLoad?: boolean;
  uris?: LoginUriResponse[];
  fido2Credentials?: Fido2CredentialResponse[];
}

export interface LoginUriResponse {
  uri?: string;
  match?: number;
  uriChecksum?: string;
}

// Folder Types
export interface FolderResponse {
  id: string;
  name: string;
  revisionDate: string;
  object: 'folder';
}

export interface FolderRequest {
  name: string;
}

// Sync Types
export interface SyncResponse {
  profile: ProfileResponse;
  folders: FolderResponse[];
  collections: CollectionDetailsResponse[];
  ciphers: CipherResponse[];
  domains: DomainsResponse;
  policies: PolicyResponse[];
  sends: SendResponse[];
  object: 'sync';
}

// Generic List Response
export interface ListResponse<T> {
  data: T[];
  object: 'list';
}
```

## Implementation Examples

### 4. Authentication Flow

```typescript
// src/services/auth.service.ts
import { createSignal } from 'solid-js';
import { BitwardenApiService } from './api.service';
import { CryptoService } from './crypto.service';

export class AuthService {
  private api = new BitwardenApiService();
  private crypto = new CryptoService();

  async login(email: string, password: string): Promise<LoginResult> {
    try {
      // 1. Get KDF settings
      const prelogin = await this.api.prelogin(email);

      // 2. Derive master key
      const masterKey = await this.crypto.deriveMasterKey(
        password,
        email,
        prelogin.kdfIterations,
        prelogin.kdf
      );

      // 3. Hash password for authentication
      const hashedPassword = await this.crypto.hashPassword(password, masterKey);

      // 4. Prepare login request
      const loginRequest: PasswordTokenRequest = {
        grant_type: 'password',
        username: email,
        password: hashedPassword,
        scope: 'api offline_access',
        client_id: 'desktop',
        deviceType: 8, // Desktop
        deviceIdentifier: await this.getDeviceIdentifier(),
        deviceName: await this.getDeviceName(),
      };

      // 5. Authenticate
      const tokenResponse = await this.api.login(loginRequest);

      // 6. Store tokens and keys
      await this.storeAuthData(tokenResponse, masterKey);

      return { success: true, requiresTwoFactor: false };
    } catch (error) {
      if (error.error === 'invalid_grant' && error.TwoFactorProviders) {
        return {
          success: false,
          requiresTwoFactor: true,
          twoFactorProviders: error.TwoFactorProviders
        };
      }
      throw error;
    }
  }

  async loginWithTwoFactor(
    email: string,
    password: string,
    twoFactorToken: string,
    twoFactorProvider: number,
    remember: boolean = false
  ): Promise<LoginResult> {
    // Similar to login but include 2FA parameters
    const prelogin = await this.api.prelogin(email);
    const masterKey = await this.crypto.deriveMasterKey(password, email, prelogin.kdfIterations, prelogin.kdf);
    const hashedPassword = await this.crypto.hashPassword(password, masterKey);

    const loginRequest: PasswordTokenRequest = {
      grant_type: 'password',
      username: email,
      password: hashedPassword,
      scope: 'api offline_access',
      client_id: 'desktop',
      deviceType: 8,
      deviceIdentifier: await this.getDeviceIdentifier(),
      deviceName: await this.getDeviceName(),
      twoFactorToken,
      twoFactorProvider,
      twoFactorRemember: remember ? 1 : 0,
    };

    const tokenResponse = await this.api.login(loginRequest);
    await this.storeAuthData(tokenResponse, masterKey);

    return { success: true, requiresTwoFactor: false };
  }
}

interface LoginResult {
  success: boolean;
  requiresTwoFactor: boolean;
  twoFactorProviders?: number[];
}
```

### 5. Vault Sync Implementation

```typescript
// src/services/sync.service.ts
export class SyncService {
  private api = new BitwardenApiService();

  async fullSync(): Promise<void> {
    try {
      const syncData = await this.api.sync();

      // Update local state
      await this.updateProfile(syncData.profile);
      await this.updateFolders(syncData.folders);
      await this.updateCiphers(syncData.ciphers);
      await this.updateCollections(syncData.collections);

      // Store last sync time
      await this.setLastSyncTime(new Date());

    } catch (error) {
      console.error('Sync failed:', error);
      throw error;
    }
  }

  private async updateCiphers(ciphers: CipherResponse[]): Promise<void> {
    // Decrypt and store ciphers
    const decryptedCiphers = await Promise.all(
      ciphers.map(cipher => this.crypto.decryptCipher(cipher))
    );

    // Update vault state
    setVaultState('ciphers', decryptedCiphers);
  }
}
```

## Error Handling

### 6. API Error Management

```typescript
// src/types/errors.ts
export class ApiError extends Error {
  constructor(
    public status: number,
    public message: string,
    public validationErrors?: Record<string, string[]>
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

// src/services/error-handler.service.ts
export class ErrorHandlerService {
  handleApiError(error: any): string {
    if (error.status === 401) {
      return 'Authentication failed. Please log in again.';
    } else if (error.status === 403) {
      return 'Access denied. You do not have permission to perform this action.';
    } else if (error.status === 429) {
      return 'Too many requests. Please try again later.';
    } else if (error.validationErrors) {
      return this.formatValidationErrors(error.validationErrors);
    } else {
      return error.message || 'An unexpected error occurred.';
    }
  }

  private formatValidationErrors(errors: Record<string, string[]>): string {
    const messages = Object.entries(errors)
      .map(([field, fieldErrors]) => `${field}: ${fieldErrors.join(', ')}`)
      .join('\n');
    return `Validation errors:\n${messages}`;
  }
}
```

## Usage in Components

### 7. SolidJS Component Integration

```typescript
// src/components/vault/CipherList.tsx
import { createSignal, createEffect, For } from 'solid-js';
import { BitwardenApiService } from '../@/services/api.service';

export function CipherList() {
  const [ciphers, setCiphers] = createSignal<CipherView[]>([]);
  const [loading, setLoading] = createSignal(false);
  const api = new BitwardenApiService();

  createEffect(async () => {
    setLoading(true);
    try {
      const response = await api.getCiphers();
      setCiphers(response.data);
    } catch (error) {
      console.error('Failed to load ciphers:', error);
    } finally {
      setLoading(false);
    }
  });

  const deleteCipher = async (id: string) => {
    try {
      await api.deleteCipher(id);
      setCiphers(prev => prev.filter(c => c.id !== id));
    } catch (error) {
      console.error('Failed to delete cipher:', error);
    }
  };

  return (
    <div class="cipher-list">
      <Show when={loading()}>
        <div>Loading...</div>
      </Show>
      <For each={ciphers()}>
        {(cipher) => (
          <div class="cipher-item">
            <h3>{cipher.name}</h3>
            <button onClick={() => deleteCipher(cipher.id)}>Delete</button>
          </div>
        )}
      </For>
    </div>
  );
}
```

This comprehensive API integration guide provides everything needed to implement the Bitwarden API in your Tauri + SolidJS desktop client, with complete type safety and error handling.
