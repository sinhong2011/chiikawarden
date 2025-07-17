# Folder Management API Documentation - Tauri Best Practices

## Overview

The Folder Management API handles organization of vault items into folders. **All folder operations must be implemented in the Rust backend** for security, encryption, and proper data management.

## Security Architecture

### ✅ Correct Implementation Pattern
```
SolidJS Frontend → invoke('folder_command') → Rust Backend → Encryption → Bitwarden API
```

### ❌ Never Do This
```typescript
// WRONG: Direct folder API calls from frontend
const folders = await fetch('/folders', { headers: { Authorization: token } });
```

## Folder Operations

### 1. Get All Folders

**Endpoint:** `GET /folders`
**Authentication:** Bearer token required (handled in Rust)
**Purpose:** Retrieve and decrypt all folders for the authenticated user

#### Tauri Command Implementation

```rust
// src-tauri/src/folder/commands.rs
use tauri::State;
use crate::database::Database;
use crate::crypto::CryptoService;

#[tauri::command]
pub async fn get_all_folders(
    api_client: State<'_, ApiClientState>,
    database: State<'_, Database>,
    crypto_service: State<'_, CryptoService>
) -> Result<Vec<FolderView>, String> {
    // Try to get from local database first
    if let Ok(local_folders) = database.get_all_folders().await {
        if !local_folders.is_empty() {
            return Ok(local_folders);
        }
    }

    // Fetch from API if not in local database
    let encrypted_folders: FolderListResponse = api_client
        .make_authenticated_request(
            reqwest::Method::GET,
            "/folders",
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    // Decrypt folders
    let mut decrypted_folders = Vec::new();
    for encrypted_folder in encrypted_folders.data {
        let decrypted = crypto_service
            .decrypt_folder(encrypted_folder)
            .await
            .map_err(|e| format!("Failed to decrypt folder: {}", e))?;
        decrypted_folders.push(decrypted);
    }

    // Store in local database for offline access
    database.store_folders(&decrypted_folders).await
        .map_err(|e| e.to_string())?;

    Ok(decrypted_folders)
}

#[tauri::command]
pub async fn create_folder(
    name: String,
    api_client: State<'_, ApiClientState>,
    crypto_service: State<'_, CryptoService>,
    database: State<'_, Database>
) -> Result<FolderView, String> {
    // Validate folder name
    if name.trim().is_empty() {
        return Err("Folder name cannot be empty".to_string());
    }

    // Encrypt folder name
    let encrypted_name = crypto_service
        .encrypt_string(&name)
        .await
        .map_err(|e| e.to_string())?;

    let request = CreateFolderRequest {
        name: encrypted_name,
    };

    // Create via API
    let created_folder: FolderResponse = api_client
        .make_authenticated_request(
            reqwest::Method::POST,
            "/folders",
            Some(request)
        )
        .await
        .map_err(|e| e.to_string())?;

    // Decrypt and return
    let decrypted_folder = crypto_service
        .decrypt_folder(created_folder)
        .await
        .map_err(|e| e.to_string())?;

    // Update local database
    database.store_folder(&decrypted_folder).await
        .map_err(|e| e.to_string())?;

    Ok(decrypted_folder)
}

#[tauri::command]
pub async fn update_folder(
    id: String,
    name: String,
    api_client: State<'_, ApiClientState>,
    crypto_service: State<'_, CryptoService>,
    database: State<'_, Database>
) -> Result<FolderView, String> {
    // Validate inputs
    if name.trim().is_empty() {
        return Err("Folder name cannot be empty".to_string());
    }

    // Encrypt folder name
    let encrypted_name = crypto_service
        .encrypt_string(&name)
        .await
        .map_err(|e| e.to_string())?;

    let request = UpdateFolderRequest {
        name: encrypted_name,
    };

    // Update via API
    let updated_folder: FolderResponse = api_client
        .make_authenticated_request(
            reqwest::Method::PUT,
            &format!("/folders/{}", id),
            Some(request)
        )
        .await
        .map_err(|e| e.to_string())?;

    // Decrypt and return
    let decrypted_folder = crypto_service
        .decrypt_folder(updated_folder)
        .await
        .map_err(|e| e.to_string())?;

    // Update local database
    database.update_folder(&decrypted_folder).await
        .map_err(|e| e.to_string())?;

    Ok(decrypted_folder)
}

#[tauri::command]
pub async fn delete_folder(
    id: String,
    api_client: State<'_, ApiClientState>,
    database: State<'_, Database>
) -> Result<(), String> {
    // Delete via API
    api_client
        .make_authenticated_request(
            reqwest::Method::DELETE,
            &format!("/folders/{}", id),
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    // Remove from local database
    database.delete_folder(&id).await
        .map_err(|e| e.to_string())?;

    Ok(())
}
```

#### Frontend Usage

```typescript
// src/services/folder.service.ts
import { invoke } from '@tauri-apps/api/tauri';

export class FolderService {
    async getAllFolders(): Promise<FolderView[]> {
        return await invoke('get_all_folders');
    }

    async createFolder(name: string): Promise<FolderView> {
        return await invoke('create_folder', { name });
    }

    async updateFolder(id: string, name: string): Promise<FolderView> {
        return await invoke('update_folder', { id, name });
    }

    async deleteFolder(id: string): Promise<void> {
        return await invoke('delete_folder', { id });
    }
}
  object: 'folder';
}

interface FolderListResponse {
  data: FolderResponse[];
  object: 'list';
}

async function getAllFolders(): Promise<FolderResponse[]> {
  const response = await fetch('/folders', {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    }
  });

  if (!response.ok) {
    throw new Error('Failed to fetch folders');
  }

  const result: FolderListResponse = await response.json();
  return result.data;
}

// Decrypt folders for display
async function getDecryptedFolders(): Promise<FolderView[]> {
  const encryptedFolders = await getAllFolders();
  const userKey = await getUserKey();

  return Promise.all(
    encryptedFolders.map(async folder => ({
      id: folder.id,
      name: await decryptString(folder.name, userKey),
      revisionDate: new Date(folder.revisionDate)
    }))
  );
}
```

---

### 2. Get Folder by ID

**Endpoint:** `GET /folders/{id}`
**Authentication:** Bearer token required
**Purpose:** Retrieve a specific folder by its ID

#### Request

```http
GET /folders/folder-12345678-1234-1234-1234-123456789012
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```json
{
  "id": "folder-12345678-1234-1234-1234-123456789012",
  "name": "2.encrypted_folder_name|base64_encoded_data",
  "revisionDate": "2023-12-01T10:30:00.000Z",
  "object": "folder"
}
```

#### Rust Implementation Example

```rust
// src-tauri/src/folder/api.rs
use reqwest::Client;
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

#[derive(Deserialize)]
struct FolderResponse {
    id: String,
    name: String,
    revision_date: DateTime<Utc>,
}

#[derive(Serialize)]
struct FolderView {
    id: String,
    name: String,
    revision_date: DateTime<Utc>,
}

async fn get_folder(id: &str, access_token: &str) -> Result<FolderResponse, reqwest::Error> {
    let client = Client::new();

    let response = client
        .get(&format!("https://api.bitwarden.com/folders/{}", id))
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .send()
        .await?;

    match response.status() {
        reqwest::StatusCode::NOT_FOUND => {
            Err(reqwest::Error::from(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "Folder not found"
            )))
        }
        status if status.is_success() => {
            response.json::<FolderResponse>().await
        }
        _ => {
            Err(reqwest::Error::from(response.error_for_status().unwrap_err()))
        }
    }
}

async fn get_decrypted_folder(
    id: &str,
    access_token: &str,
    crypto_service: &CryptoService
) -> Result<FolderView, Box<dyn std::error::Error>> {
    let encrypted_folder = get_folder(id, access_token).await?;
    let user_key = crypto_service.get_user_key().await?;

    let decrypted_name = crypto_service
        .decrypt_string(&encrypted_folder.name, &user_key)
        .await?;

    Ok(FolderView {
        id: encrypted_folder.id,
        name: decrypted_name,
        revision_date: encrypted_folder.revision_date,
    })
}
```

---

### 3. Create Folder

**Endpoint:** `POST /folders`
**Authentication:** Bearer token required
**Purpose:** Create a new folder

#### Request

```json
{
  "name": "2.encrypted_new_folder_name|base64_encoded_data"
}
```

#### Response

```json
{
  "id": "folder-new12345-1234-1234-1234-123456789012",
  "name": "2.encrypted_new_folder_name|base64_encoded_data",
  "revisionDate": "2023-12-01T15:45:00.000Z",
  "object": "folder"
}
```

#### Implementation Example

```typescript
interface FolderRequest {
  name: string;
}

interface FolderView {
  id?: string;
  name: string;
  revisionDate?: Date;
}

async function createFolder(folderData: FolderRequest): Promise<FolderResponse> {
  const response = await fetch('/folders', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(folderData)
  });

  if (!response.ok) {
    throw new Error('Failed to create folder');
  }

  return response.json();
}

// Helper function to create folder with encryption
async function createFolderFromView(folderView: FolderView): Promise<FolderView> {
  const userKey = await getUserKey();

  const encryptedRequest: FolderRequest = {
    name: await encryptString(folderView.name, userKey)
  };

  const encryptedResponse = await createFolder(encryptedRequest);

  return {
    id: encryptedResponse.id,
    name: folderView.name, // Return original unencrypted name
    revisionDate: new Date(encryptedResponse.revisionDate)
  };
}
```

---

### 4. Update Folder

**Endpoint:** `PUT /folders/{id}`
**Authentication:** Bearer token required
**Purpose:** Update an existing folder

#### Request

```json
{
  "name": "2.encrypted_updated_folder_name|base64_encoded_data"
}
```

#### Response

```json
{
  "id": "folder-12345678-1234-1234-1234-123456789012",
  "name": "2.encrypted_updated_folder_name|base64_encoded_data",
  "revisionDate": "2023-12-01T16:00:00.000Z",
  "object": "folder"
}
```

#### Implementation Example

```typescript
async function updateFolder(id: string, folderData: FolderRequest): Promise<FolderResponse> {
  const response = await fetch(`/folders/${id}`, {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(folderData)
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('Folder not found');
    }
    throw new Error('Failed to update folder');
  }

  return response.json();
}

// Helper function to update folder with encryption
async function updateFolderFromView(folderView: FolderView): Promise<FolderView> {
  if (!folderView.id) {
    throw new Error('Folder ID is required for update');
  }

  const userKey = await getUserKey();

  const encryptedRequest: FolderRequest = {
    name: await encryptString(folderView.name, userKey)
  };

  const encryptedResponse = await updateFolder(folderView.id, encryptedRequest);

  return {
    id: encryptedResponse.id,
    name: folderView.name, // Return original unencrypted name
    revisionDate: new Date(encryptedResponse.revisionDate)
  };
}
```

---

### 5. Delete Folder

**Endpoint:** `DELETE /folders/{id}`
**Authentication:** Bearer token required
**Purpose:** Delete a folder (ciphers in the folder are moved to "No Folder")

#### Request

```http
DELETE /folders/folder-12345678-1234-1234-1234-123456789012
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```
200 OK
```

#### Implementation Example

```typescript
async function deleteFolder(id: string): Promise<void> {
  const response = await fetch(`/folders/${id}`, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${accessToken}`
    }
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('Folder not found');
    }
    throw new Error('Failed to delete folder');
  }
}

// Helper function with confirmation
async function deleteFolderWithConfirmation(
  id: string,
  confirmCallback?: () => Promise<boolean>
): Promise<void> {
  // Check if folder has ciphers
  const ciphersInFolder = await getCiphersByFolder(id);

  if (ciphersInFolder.length > 0 && confirmCallback) {
    const confirmed = await confirmCallback();
    if (!confirmed) {
      return;
    }
  }

  await deleteFolder(id);
}
```

## Folder Organization and Management

### 1. Folder Hierarchy Simulation

While Bitwarden doesn't support nested folders natively, you can simulate hierarchy using naming conventions:

```typescript
class FolderHierarchyService {
  private readonly SEPARATOR = '/';

  // Create hierarchical folder names
  createHierarchicalName(parentPath: string, folderName: string): string {
    return parentPath ? `${parentPath}${this.SEPARATOR}${folderName}` : folderName;
  }

  // Parse folder hierarchy from names
  parseFolderHierarchy(folders: FolderView[]): FolderTreeNode[] {
    const tree: FolderTreeNode[] = [];
    const folderMap = new Map<string, FolderTreeNode>();

    // Sort folders by name to ensure parent folders are processed first
    const sortedFolders = [...folders].sort((a, b) => a.name.localeCompare(b.name));

    for (const folder of sortedFolders) {
      const parts = folder.name.split(this.SEPARATOR);
      const node: FolderTreeNode = {
        id: folder.id!,
        name: parts[parts.length - 1], // Last part is the actual folder name
        fullPath: folder.name,
        children: [],
        parent: null,
        level: parts.length - 1
      };

      folderMap.set(folder.id!, node);

      if (parts.length === 1) {
        // Root level folder
        tree.push(node);
      } else {
        // Find parent folder
        const parentPath = parts.slice(0, -1).join(this.SEPARATOR);
        const parentFolder = folders.find(f => f.name === parentPath);

        if (parentFolder && folderMap.has(parentFolder.id!)) {
          const parentNode = folderMap.get(parentFolder.id!)!;
          node.parent = parentNode;
          parentNode.children.push(node);
        } else {
          // Parent not found, add to root
          tree.push(node);
        }
      }
    }

    return tree;
  }

  // Get all descendant folder IDs
  getDescendantFolderIds(folderId: string, folderTree: FolderTreeNode[]): string[] {
    const descendants: string[] = [];

    const findDescendants = (nodes: FolderTreeNode[]) => {
      for (const node of nodes) {
        if (node.id === folderId) {
          this.collectDescendantIds(node, descendants);
          return;
        }
        findDescendants(node.children);
      }
    };

    findDescendants(folderTree);
    return descendants;
  }

  private collectDescendantIds(node: FolderTreeNode, result: string[]): void {
    for (const child of node.children) {
      result.push(child.id);
      this.collectDescendantIds(child, result);
    }
  }
}

interface FolderTreeNode {
  id: string;
  name: string;
  fullPath: string;
  children: FolderTreeNode[];
  parent: FolderTreeNode | null;
  level: number;
}
```

### 2. Folder-Cipher Relationships

```typescript
class FolderCipherService {
  // Get all ciphers in a specific folder
  async getCiphersByFolder(folderId: string | null): Promise<CipherView[]> {
    const allCiphers = await getAllDecryptedCiphers();
    return allCiphers.filter(cipher => cipher.folderId === folderId);
  }

  // Get cipher count for each folder
  async getFolderCipherCounts(folders: FolderView[]): Promise<Map<string, number>> {
    const allCiphers = await getAllDecryptedCiphers();
    const counts = new Map<string, number>();

    // Initialize all folders with 0 count
    folders.forEach(folder => counts.set(folder.id!, 0));

    // Count "No Folder" items
    const noFolderCount = allCiphers.filter(cipher => !cipher.folderId).length;
    counts.set('no-folder', noFolderCount);

    // Count ciphers in each folder
    allCiphers.forEach(cipher => {
      if (cipher.folderId && counts.has(cipher.folderId)) {
        counts.set(cipher.folderId, counts.get(cipher.folderId)! + 1);
      }
    });

    return counts;
  }

  // Move ciphers to a different folder
  async moveCiphersToFolder(cipherIds: string[], targetFolderId: string | null): Promise<void> {
    const updatePromises = cipherIds.map(async cipherId => {
      const cipher = await getCipher(cipherId);
      const decryptedCipher = await decryptCipherFromStorage(cipher);

      // Update folder assignment
      decryptedCipher.folderId = targetFolderId;

      // Re-encrypt and update
      const encryptedCipher = await encryptCipherForStorage(decryptedCipher);
      return updateCipher(cipherId, encryptedCipher);
    });

    await Promise.all(updatePromises);
  }

  // Move all ciphers from one folder to another (useful before deleting folder)
  async moveAllCiphersFromFolder(sourceFolderId: string, targetFolderId: string | null): Promise<void> {
    const ciphersInFolder = await this.getCiphersByFolder(sourceFolderId);
    const cipherIds = ciphersInFolder.map(cipher => cipher.id);

    if (cipherIds.length > 0) {
      await this.moveCiphersToFolder(cipherIds, targetFolderId);
    }
  }
}
```

### 3. Folder Search and Filtering

```typescript
class FolderSearchService {
  // Search folders by name
  searchFolders(folders: FolderView[], query: string): FolderView[] {
    if (!query.trim()) {
      return folders;
    }

    const searchTerm = query.toLowerCase();
    return folders.filter(folder =>
      folder.name.toLowerCase().includes(searchTerm)
    );
  }

  // Get recently used folders based on cipher activity
  async getRecentlyUsedFolders(limit: number = 5): Promise<FolderView[]> {
    const allCiphers = await getAllDecryptedCiphers();
    const allFolders = await getDecryptedFolders();

    // Count recent cipher activity per folder
    const folderActivity = new Map<string, Date>();

    allCiphers.forEach(cipher => {
      if (cipher.folderId && cipher.revisionDate) {
        const currentDate = folderActivity.get(cipher.folderId);
        if (!currentDate || cipher.revisionDate > currentDate) {
          folderActivity.set(cipher.folderId, cipher.revisionDate);
        }
      }
    });

    // Sort folders by recent activity
    return allFolders
      .filter(folder => folderActivity.has(folder.id!))
      .sort((a, b) => {
        const dateA = folderActivity.get(a.id!)!;
        const dateB = folderActivity.get(b.id!)!;
        return dateB.getTime() - dateA.getTime();
      })
      .slice(0, limit);
  }

  // Get empty folders (folders with no ciphers)
  async getEmptyFolders(): Promise<FolderView[]> {
    const allFolders = await getDecryptedFolders();
    const folderCounts = await new FolderCipherService().getFolderCipherCounts(allFolders);

    return allFolders.filter(folder =>
      folderCounts.get(folder.id!) === 0
    );
  }
}
```

## Error Handling

### Folder-Specific Errors

```typescript
class FolderError extends Error {
  constructor(
    message: string,
    public code: string,
    public folderId?: string
  ) {
    super(message);
    this.name = 'FolderError';
  }
}

async function handleFolderOperation<T>(
  operation: () => Promise<T>,
  folderId?: string
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    if (error.status === 404) {
      throw new FolderError('Folder not found', 'FOLDER_NOT_FOUND', folderId);
    } else if (error.status === 403) {
      throw new FolderError('Access denied to folder', 'FOLDER_ACCESS_DENIED', folderId);
    } else if (error.status === 400) {
      throw new FolderError('Invalid folder data', 'FOLDER_INVALID_DATA', folderId);
    } else if (error.status === 409) {
      throw new FolderError('Folder name already exists', 'FOLDER_NAME_EXISTS', folderId);
    } else {
      throw new FolderError('Folder operation failed', 'FOLDER_OPERATION_FAILED', folderId);
    }
  }
}

// Validation helpers
function validateFolderName(name: string): void {
  if (!name || name.trim().length === 0) {
    throw new FolderError('Folder name cannot be empty', 'FOLDER_NAME_EMPTY');
  }

  if (name.length > 100) {
    throw new FolderError('Folder name too long (max 100 characters)', 'FOLDER_NAME_TOO_LONG');
  }

  // Check for invalid characters (if using hierarchy)
  const invalidChars = ['<', '>', ':', '"', '|', '?', '*'];
  if (invalidChars.some(char => name.includes(char))) {
    throw new FolderError('Folder name contains invalid characters', 'FOLDER_NAME_INVALID_CHARS');
  }
}

async function validateUniqueFolderName(name: string, excludeId?: string): Promise<void> {
  const existingFolders = await getDecryptedFolders();
  const duplicate = existingFolders.find(folder =>
    folder.name.toLowerCase() === name.toLowerCase() && folder.id !== excludeId
  );

  if (duplicate) {
    throw new FolderError('Folder name already exists', 'FOLDER_NAME_EXISTS');
  }
}
```

## Best Practices

### 1. Folder Management Guidelines

```typescript
class FolderManagementService {
  // Create folder with validation
  async createFolderSafely(name: string): Promise<FolderView> {
    validateFolderName(name);
    await validateUniqueFolderName(name);

    return createFolderFromView({ name });
  }

  // Update folder with validation
  async updateFolderSafely(id: string, name: string): Promise<FolderView> {
    validateFolderName(name);
    await validateUniqueFolderName(name, id);

    return updateFolderFromView({ id, name });
  }

  // Delete folder with cipher handling
  async deleteFolderSafely(
    id: string,
    targetFolderId: string | null = null
  ): Promise<void> {
    const folderCipherService = new FolderCipherService();

    // Move all ciphers to target folder (or "No Folder" if null)
    await folderCipherService.moveAllCiphersFromFolder(id, targetFolderId);

    // Delete the empty folder
    await deleteFolder(id);
  }

  // Bulk folder operations
  async bulkDeleteFolders(folderIds: string[], targetFolderId: string | null = null): Promise<void> {
    for (const folderId of folderIds) {
      await this.deleteFolderSafely(folderId, targetFolderId);
    }
  }
}
```

### 2. Performance Optimization

```typescript
class FolderCacheService {
  private folderCache = new Map<string, FolderView>();
  private cacheExpiry: number = 0;
  private readonly CACHE_TTL = 5 * 60 * 1000; // 5 minutes

  async getCachedFolders(): Promise<FolderView[]> {
    if (Date.now() > this.cacheExpiry || this.folderCache.size === 0) {
      await this.refreshCache();
    }

    return Array.from(this.folderCache.values());
  }

  private async refreshCache(): Promise<void> {
    const folders = await getDecryptedFolders();
    this.folderCache.clear();

    folders.forEach(folder => {
      if (folder.id) {
        this.folderCache.set(folder.id, folder);
      }
    });

    this.cacheExpiry = Date.now() + this.CACHE_TTL;
  }

  invalidateCache(): void {
    this.folderCache.clear();
    this.cacheExpiry = 0;
  }

  updateCachedFolder(folder: FolderView): void {
    if (folder.id) {
      this.folderCache.set(folder.id, folder);
    }
  }

  removeCachedFolder(id: string): void {
    this.folderCache.delete(id);
  }
}
```
