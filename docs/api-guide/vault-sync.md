# Vault Sync API Documentation - Tauri Best Practices

## Overview

The Vault Sync API provides comprehensive synchronization of all user vault data including ciphers, folders, collections, policies, and sends. **All sync operations must be handled in the Rust backend** for security, encryption, and proper data management.

## Security Architecture

### ✅ Correct Implementation Pattern
```
SolidJS Frontend → invoke('sync_vault') → Rust Backend → Bitwarden API → Local Database
```

### ❌ Never Do This
```typescript
// WRONG: Direct sync from frontend
const syncData = await fetch('/sync', { headers: { Authorization: token } });
```

## Sync Implementation

### 1. Full Vault Sync

**Endpoint:** `GET /sync`
**Authentication:** Bearer token required (handled in Rust)
**Purpose:** Retrieve and process complete vault data

#### Tauri Command Implementation

```rust
// src-tauri/src/sync/commands.rs
use tauri::State;
use crate::database::Database;
use crate::crypto::CryptoService;

#[tauri::command]
pub async fn sync_vault(
    api_client: State<'_, ApiClientState>,
    database: State<'_, Database>,
    crypto_service: State<'_, CryptoService>
) -> Result<SyncResult, String> {
    // Step 1: Fetch sync data from API
    let sync_response: SyncResponse = api_client
        .make_authenticated_request(
            reqwest::Method::GET,
            "/sync?excludeDomains=true",
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    // Step 2: Process and decrypt data
    let processed_data = process_sync_data(sync_response, &crypto_service).await?;

    // Step 3: Update local database
    database.update_vault_data(processed_data).await
        .map_err(|e| e.to_string())?;

    // Step 4: Return sync result
    Ok(SyncResult {
        last_sync: chrono::Utc::now(),
        ciphers_updated: processed_data.ciphers.len(),
        folders_updated: processed_data.folders.len(),
        success: true,
    })
}

// Process and decrypt sync data
async fn process_sync_data(
    sync_response: SyncResponse,
    crypto_service: &CryptoService
) -> Result<ProcessedSyncData, String> {
    let mut processed_data = ProcessedSyncData::default();

    // Decrypt ciphers
    for cipher in sync_response.ciphers {
        let decrypted_cipher = crypto_service
            .decrypt_cipher(cipher)
            .await
            .map_err(|e| format!("Failed to decrypt cipher: {}", e))?;
        processed_data.ciphers.push(decrypted_cipher);
    }

    // Decrypt folders
    for folder in sync_response.folders {
        let decrypted_folder = crypto_service
            .decrypt_folder(folder)
            .await
            .map_err(|e| format!("Failed to decrypt folder: {}", e))?;
        processed_data.folders.push(decrypted_folder);
    }

    // Process profile data
    processed_data.profile = sync_response.profile;

    Ok(processed_data)
}
```

#### Frontend Usage

```typescript
// src/services/sync.service.ts
import { invoke } from '@tauri-apps/api/tauri';
import { listen } from '@tauri-apps/api/event';

export class SyncService {
    async syncVault(): Promise<SyncResult> {
        return await invoke('sync_vault');
    }

    // Listen for sync progress events
    setupSyncListeners() {
        listen('sync_progress', (event) => {
            console.log('Sync progress:', event.payload);
        });

        listen('sync_completed', (event) => {
            console.log('Sync completed:', event.payload);
        });
    }
}
```

#### Sync with Progress Updates

```rust
#[tauri::command]
pub async fn sync_vault_with_progress(
    app_handle: tauri::AppHandle,
    api_client: State<'_, ApiClientState>,
    database: State<'_, Database>,
    crypto_service: State<'_, CryptoService>
) -> Result<SyncResult, String> {
    // Emit progress: Starting sync
    app_handle.emit_all("sync_progress", SyncProgress {
        step: "Fetching vault data".to_string(),
        percentage: 10,
    }).unwrap();

    // Fetch sync data
    let sync_response: SyncResponse = api_client
        .make_authenticated_request(
            reqwest::Method::GET,
            "/sync?excludeDomains=true",
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    // Emit progress: Processing data
    app_handle.emit_all("sync_progress", SyncProgress {
        step: "Decrypting vault data".to_string(),
        percentage: 50,
    }).unwrap();

    // Process data with progress updates
    let processed_data = process_sync_data_with_progress(
        sync_response,
        &crypto_service,
        &app_handle
    ).await?;

    // Emit progress: Updating database
    app_handle.emit_all("sync_progress", SyncProgress {
        step: "Updating local database".to_string(),
        percentage: 90,
    }).unwrap();

    // Update database
    database.update_vault_data(processed_data).await
        .map_err(|e| e.to_string())?;

    // Emit completion
    let result = SyncResult {
        last_sync: chrono::Utc::now(),
        ciphers_updated: processed_data.ciphers.len(),
        folders_updated: processed_data.folders.len(),
        success: true,
    };

    app_handle.emit_all("sync_completed", &result).unwrap();

    Ok(result)
}
```

#### Frontend Sync Component

```typescript
// src/components/SyncStatus.tsx
import { createSignal, onMount } from 'solid-js';
import { invoke } from '@tauri-apps/api/tauri';
import { listen } from '@tauri-apps/api/event';

export function SyncStatus() {
    const [syncState, setSyncState] = createSignal({
        isSync: false,
        progress: 0,
        currentStep: '',
        lastSync: null as Date | null,
        error: null as string | null
    });

    onMount(() => {
        // Listen for sync events
        listen('sync_progress', (event: any) => {
            setSyncState(prev => ({
                ...prev,
                progress: event.payload.percentage,
                currentStep: event.payload.step
            }));
        });

        listen('sync_completed', (event: any) => {
            setSyncState(prev => ({
                ...prev,
                isSync: false,
                progress: 100,
                lastSync: new Date(event.payload.last_sync),
                error: null
            }));
        });

        listen('sync_error', (event: any) => {
            setSyncState(prev => ({
                ...prev,
                isSync: false,
                error: event.payload.message
            }));
        });
    });

    const triggerSync = async () => {
        setSyncState(prev => ({ ...prev, isSync: true, error: null }));

        try {
            await invoke('sync_vault_with_progress');
        } catch (error) {
            setSyncState(prev => ({
                ...prev,
                isSync: false,
                error: error as string
            }));
        }
    };

    return (
        <div class="sync-status">
            <button
                onClick={triggerSync}
                disabled={syncState().isSync}
                class="sync-button"
            >
                {syncState().isSync ? 'Syncing...' : 'Sync Vault'}
            </button>

            {syncState().isSync && (
                <div class="sync-progress">
                    <div class="progress-bar">
                        <div
                            class="progress-fill"
                            style={`width: ${syncState().progress}%`}
                        />
                    </div>
                    <div class="progress-text">
                        {syncState().currentStep} ({syncState().progress}%)
                    </div>
                </div>
            )}

            {syncState().lastSync && (
                <div class="last-sync">
                    Last sync: {syncState().lastSync?.toLocaleString()}
                </div>
            )}

            {syncState().error && (
                <div class="sync-error">
                    Error: {syncState().error}
                </div>
            )}
        </div>
    );
}
      "manage": true,
      "object": "collectionDetails"
    }
  ],
  "ciphers": [
    {
      "id": "cipher-12345678-1234-1234-1234-123456789012",
      "organizationId": null,
      "folderId": "folder-12345678-1234-1234-1234-123456789012",
      "type": 1,
      "name": "2.encrypted_cipher_name|base64",
      "notes": "2.encrypted_notes|base64",
      "favorite": false,
      "organizationUseTotp": false,
      "edit": true,
      "viewPassword": true,
      "revisionDate": "2023-12-01T10:30:00.000Z",
      "creationDate": "2023-11-01T09:15:00.000Z",
      "deletedDate": null,
      "reprompt": 0,
      "login": {
        "username": "2.encrypted_username|base64",
        "password": "2.encrypted_password|base64",
        "passwordRevisionDate": "2023-11-01T09:15:00.000Z",
        "totp": "2.encrypted_totp_secret|base64",
        "autofillOnPageLoad": null,
        "uris": [
          {
            "uri": "2.encrypted_uri|base64",
            "match": null,
            "uriChecksum": "checksum_value"
          }
        ],
        "fido2Credentials": []
      },
      "secureNote": null,
      "card": null,
      "identity": null,
      "sshKey": null,
      "fields": [
        {
          "type": 0,
          "name": "2.encrypted_field_name|base64",
          "value": "2.encrypted_field_value|base64",
          "linkedId": null
        }
      ],
      "attachments": [
        {
          "id": "attachment-id",
          "url": "https://vault.bitwarden.com/attachments/...",
          "fileName": "2.encrypted_filename|base64",
          "key": "encrypted_attachment_key",
          "size": "1024",
          "sizeName": "1 KB",
          "object": "attachment"
        }
      ],
      "passwordHistory": [
        {
          "password": "2.encrypted_old_password|base64",
          "lastUsedDate": "2023-10-01T08:00:00.000Z"
        }
      ],
      "collectionIds": [],
      "key": null,
      "object": "cipher"
    }
  ],
  "domains": {
    "equivalentDomains": [
      ["google.com", "youtube.com"],
      ["apple.com", "icloud.com"]
    ],
    "globalEquivalentDomains": [
      {
        "type": 0,
        "domains": ["ameritrade.com", "tdameritrade.com"],
        "excluded": false
      }
    ],
    "object": "domains"
  },
  "policies": [
    {
      "id": "policy-12345678-1234-1234-1234-123456789012",
      "organizationId": "org-12345678-1234-1234-1234-123456789012",
      "type": 1,
      "data": {
        "minComplexity": 3,
        "minLength": 8,
        "requireUpper": true,
        "requireLower": true,
        "requireNumbers": true,
        "requireSpecial": false
      },
      "enabled": true,
      "object": "policy"
    }
  ],
  "sends": [
    {
      "id": "send-12345678-1234-1234-1234-123456789012",
      "accessId": "access-id-string",
      "type": 0,
      "name": "2.encrypted_send_name|base64",
      "notes": "2.encrypted_send_notes|base64",
      "file": null,
      "text": {
        "text": "2.encrypted_send_text|base64",
        "hidden": false
      },
      "key": "encrypted_send_key",
      "maxAccessCount": null,
      "accessCount": 0,
      "revisionDate": "2023-12-01T10:30:00.000Z",
      "expirationDate": "2023-12-08T10:30:00.000Z",
      "deletionDate": "2023-12-15T10:30:00.000Z",
      "password": null,
      "disabled": false,
      "hideEmail": false,
      "object": "send"
    }
  ],
  "object": "sync"
}
```

#### Rust Implementation Example

```rust
// src-tauri/src/sync/api.rs
use reqwest::Client;
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct SyncResponse {
    profile: ProfileResponse,
    folders: Vec<FolderResponse>,
    collections: Vec<CollectionDetailsResponse>,
    ciphers: Vec<CipherResponse>,
    domains: Option<DomainsResponse>,
    policies: Vec<PolicyResponse>,
    sends: Vec<SendResponse>,
    object: String,
}

async fn perform_full_sync(access_token: &str) -> Result<SyncResponse, reqwest::Error> {
    let client = Client::new();

    let response = client
        .get("https://api.bitwarden.com/sync")
        .query(&[("excludeDomains", "true")])
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    response.json::<SyncResponse>().await
}
```

---

### 2. Incremental Sync Strategy

While the API doesn't provide a dedicated incremental sync endpoint, you can implement efficient syncing using revision dates.

#### Check for Updates

```typescript
async function checkForUpdates(): Promise<boolean> {
  const serverRevisionDate = await getAccountRevisionDate();
  const localRevisionDate = await getLocalRevisionDate();

  return serverRevisionDate > localRevisionDate;
}

async function performIncrementalSync(): Promise<void> {
  if (await checkForUpdates()) {
    const syncData = await performFullSync();
    await processSyncData(syncData);
    await setLocalRevisionDate(Date.now());
  }
}
```

#### Sync Data Processing

```typescript
async function processSyncData(syncData: SyncResponse): Promise<void> {
  // 1. Update profile
  await updateLocalProfile(syncData.profile);

  // 2. Process folders
  await syncFolders(syncData.folders);

  // 3. Process collections
  await syncCollections(syncData.collections);

  // 4. Process ciphers (most complex)
  await syncCiphers(syncData.ciphers);

  // 5. Update policies
  await syncPolicies(syncData.policies);

  // 6. Process sends
  await syncSends(syncData.sends);

  // 7. Update domains
  await updateDomains(syncData.domains);
}
```

---

### 3. Cipher Sync Processing

Ciphers require special handling due to their complexity and encryption.

#### Sync Algorithm

```typescript
async function syncCiphers(serverCiphers: CipherResponse[]): Promise<void> {
  const localCiphers = await getLocalCiphers();
  const localCipherMap = new Map(localCiphers.map(c => [c.id, c]));

  for (const serverCipher of serverCiphers) {
    const localCipher = localCipherMap.get(serverCipher.id);

    if (!localCipher) {
      // New cipher - decrypt and store
      const decryptedCipher = await decryptCipher(serverCipher);
      await storeLocalCipher(decryptedCipher);
    } else if (new Date(serverCipher.revisionDate) > new Date(localCipher.revisionDate)) {
      // Updated cipher - decrypt and update
      const decryptedCipher = await decryptCipher(serverCipher);
      await updateLocalCipher(decryptedCipher);
    }

    // Remove from map to track processed ciphers
    localCipherMap.delete(serverCipher.id);
  }

  // Remaining ciphers in map were deleted on server
  for (const [cipherId] of localCipherMap) {
    await deleteLocalCipher(cipherId);
  }
}
```

#### Cipher Decryption

```typescript
async function decryptCipher(encryptedCipher: CipherResponse): Promise<CipherView> {
  const userKey = await getUserKey();

  const decrypted: CipherView = {
    id: encryptedCipher.id,
    organizationId: encryptedCipher.organizationId,
    folderId: encryptedCipher.folderId,
    type: encryptedCipher.type,
    name: await decryptString(encryptedCipher.name, userKey),
    notes: encryptedCipher.notes ? await decryptString(encryptedCipher.notes, userKey) : null,
    favorite: encryptedCipher.favorite,
    revisionDate: new Date(encryptedCipher.revisionDate),
    creationDate: new Date(encryptedCipher.creationDate),
    deletedDate: encryptedCipher.deletedDate ? new Date(encryptedCipher.deletedDate) : null,
    reprompt: encryptedCipher.reprompt,
    collectionIds: encryptedCipher.collectionIds || []
  };

  // Decrypt type-specific data
  if (encryptedCipher.login) {
    decrypted.login = await decryptLogin(encryptedCipher.login, userKey);
  }

  if (encryptedCipher.secureNote) {
    decrypted.secureNote = await decryptSecureNote(encryptedCipher.secureNote, userKey);
  }

  if (encryptedCipher.card) {
    decrypted.card = await decryptCard(encryptedCipher.card, userKey);
  }

  if (encryptedCipher.identity) {
    decrypted.identity = await decryptIdentity(encryptedCipher.identity, userKey);
  }

  if (encryptedCipher.sshKey) {
    decrypted.sshKey = await decryptSshKey(encryptedCipher.sshKey, userKey);
  }

  // Decrypt fields
  if (encryptedCipher.fields) {
    decrypted.fields = await Promise.all(
      encryptedCipher.fields.map(field => decryptField(field, userKey))
    );
  }

  // Decrypt password history
  if (encryptedCipher.passwordHistory) {
    decrypted.passwordHistory = await Promise.all(
      encryptedCipher.passwordHistory.map(history => decryptPasswordHistory(history, userKey))
    );
  }

  return decrypted;
}
```

---

### 4. Conflict Resolution

Handle conflicts when local and server data differ.

#### Conflict Detection

```typescript
interface ConflictInfo {
  type: 'cipher' | 'folder' | 'collection';
  id: string;
  localRevisionDate: Date;
  serverRevisionDate: Date;
  localData: any;
  serverData: any;
}

async function detectConflicts(syncData: SyncResponse): Promise<ConflictInfo[]> {
  const conflicts: ConflictInfo[] = [];

  // Check cipher conflicts
  for (const serverCipher of syncData.ciphers) {
    const localCipher = await getLocalCipher(serverCipher.id);
    if (localCipher && localCipher.hasLocalChanges) {
      const localDate = new Date(localCipher.revisionDate);
      const serverDate = new Date(serverCipher.revisionDate);

      if (localDate.getTime() !== serverDate.getTime()) {
        conflicts.push({
          type: 'cipher',
          id: serverCipher.id,
          localRevisionDate: localDate,
          serverRevisionDate: serverDate,
          localData: localCipher,
          serverData: serverCipher
        });
      }
    }
  }

  return conflicts;
}
```

#### Conflict Resolution Strategies

```typescript
enum ConflictResolution {
  UseServer = 'server',
  UseLocal = 'local',
  Merge = 'merge',
  CreateDuplicate = 'duplicate'
}

async function resolveConflict(
  conflict: ConflictInfo,
  resolution: ConflictResolution
): Promise<void> {
  switch (resolution) {
    case ConflictResolution.UseServer:
      // Accept server version
      const decryptedServer = await decryptCipher(conflict.serverData);
      await updateLocalCipher(decryptedServer);
      break;

    case ConflictResolution.UseLocal:
      // Push local version to server
      await updateCipherOnServer(conflict.localData);
      break;

    case ConflictResolution.Merge:
      // Merge both versions (implementation depends on data type)
      const merged = await mergeCipherData(conflict.localData, conflict.serverData);
      await updateLocalCipher(merged);
      await updateCipherOnServer(merged);
      break;

    case ConflictResolution.CreateDuplicate:
      // Keep both versions
      const duplicate = { ...conflict.localData, id: generateUuid() };
      await createCipherOnServer(duplicate);
      break;
  }
}
```

---

### 5. Sync Performance Optimization

#### Batch Processing

```typescript
async function processSyncDataInBatches(syncData: SyncResponse): Promise<void> {
  const BATCH_SIZE = 50;

  // Process ciphers in batches
  for (let i = 0; i < syncData.ciphers.length; i += BATCH_SIZE) {
    const batch = syncData.ciphers.slice(i, i + BATCH_SIZE);
    await Promise.all(batch.map(cipher => processCipher(cipher)));

    // Allow UI to update between batches
    await new Promise(resolve => setTimeout(resolve, 0));
  }
}
```

#### Sync Progress Tracking

```typescript
interface SyncProgress {
  total: number;
  completed: number;
  currentOperation: string;
  percentage: number;
}

class SyncProgressTracker {
  private progress: SyncProgress = {
    total: 0,
    completed: 0,
    currentOperation: '',
    percentage: 0
  };

  private callbacks: ((progress: SyncProgress) => void)[] = [];

  onProgress(callback: (progress: SyncProgress) => void): void {
    this.callbacks.push(callback);
  }

  setTotal(total: number): void {
    this.progress.total = total;
    this.updateProgress();
  }

  setOperation(operation: string): void {
    this.progress.currentOperation = operation;
    this.updateProgress();
  }

  incrementCompleted(): void {
    this.progress.completed++;
    this.updateProgress();
  }

  private updateProgress(): void {
    this.progress.percentage = this.progress.total > 0
      ? (this.progress.completed / this.progress.total) * 100
      : 0;

    this.callbacks.forEach(callback => callback({ ...this.progress }));
  }
}
```

## Error Handling

### Sync Error Types

```typescript
class SyncError extends Error {
  constructor(
    message: string,
    public code: string,
    public retryable: boolean = true
  ) {
    super(message);
    this.name = 'SyncError';
  }
}

async function handleSyncError(error: any): Promise<void> {
  if (error.status === 401) {
    // Token expired - refresh and retry
    await refreshAccessToken();
    throw new SyncError('Authentication expired', 'AUTH_EXPIRED', true);
  } else if (error.status === 429) {
    // Rate limited - wait and retry
    const retryAfter = error.headers?.['retry-after'] || 60;
    throw new SyncError(`Rate limited. Retry after ${retryAfter}s`, 'RATE_LIMITED', true);
  } else if (error.status >= 500) {
    // Server error - retry with backoff
    throw new SyncError('Server error occurred', 'SERVER_ERROR', true);
  } else {
    // Client error - don't retry
    throw new SyncError('Sync failed', 'CLIENT_ERROR', false);
  }
}
```

### Retry Logic

```typescript
async function syncWithRetry(maxRetries: number = 3): Promise<void> {
  let lastError: Error;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      await performFullSync();
      return; // Success
    } catch (error) {
      lastError = error;

      if (error instanceof SyncError && !error.retryable) {
        throw error; // Don't retry non-retryable errors
      }

      if (attempt < maxRetries) {
        const delay = Math.pow(2, attempt) * 1000; // Exponential backoff
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  throw lastError;
}
```
