# Attachment API Documentation - Tauri Best Practices

## Overview

The Attachment API handles file attachments for vault items (ciphers). **All attachment operations must be implemented in the Rust backend** for security, file handling, and proper encryption management.

## Security Architecture

### ✅ Correct Implementation Pattern
```
SolidJS Frontend → invoke('attachment_command') → Rust Backend → File Encryption → Bitwarden API
```

### ❌ Never Do This
```typescript
// WRONG: Direct file upload from frontend
const formData = new FormData();
formData.append('data', file);
await fetch(`/ciphers/${id}/attachment`, { method: 'POST', body: formData });
```

## Attachment Operations

### 1. Upload Attachment

**Endpoint:** `POST /ciphers/{id}/attachment`
**Authentication:** Bearer token required (handled in Rust)
**Purpose:** Securely upload and encrypt file attachments

#### Tauri Command Implementation

```rust
// src-tauri/src/attachment/commands.rs
use tauri::State;
use std::path::PathBuf;
use tokio::fs;

#[tauri::command]
pub async fn upload_attachment(
    cipher_id: String,
    file_path: String,
    api_client: State<'_, ApiClientState>,
    crypto_service: State<'_, CryptoService>
) -> Result<CipherView, String> {
    // Validate file exists and get metadata
    let file_path = PathBuf::from(file_path);
    if !file_path.exists() {
        return Err("File does not exist".to_string());
    }

    let file_name = file_path
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or("Invalid file name")?;

    let file_size = fs::metadata(&file_path)
        .await
        .map_err(|e| format!("Failed to get file metadata: {}", e))?
        .len();

    // Check file size limits (10MB for free users, 1GB for premium)
    if file_size > 10 * 1024 * 1024 {
        // Check if user has premium
        let profile = get_user_profile().await?;
        if !profile.premium && file_size > 10 * 1024 * 1024 {
            return Err("File too large. Premium required for files over 10MB".to_string());
        }
        if file_size > 1024 * 1024 * 1024 {
            return Err("File too large. Maximum size is 1GB".to_string());
        }
    }

    // Read file data
    let file_data = fs::read(&file_path)
        .await
        .map_err(|e| format!("Failed to read file: {}", e))?;

    // Generate attachment key and encrypt file
    let attachment_key = crypto_service.generate_attachment_key().await?;
    let encrypted_file_data = crypto_service
        .encrypt_attachment_data(&file_data, &attachment_key)
        .await
        .map_err(|e| format!("Failed to encrypt file: {}", e))?;

    // Encrypt attachment key with cipher key
    let encrypted_attachment_key = crypto_service
        .encrypt_attachment_key(&attachment_key, &cipher_id)
        .await
        .map_err(|e| format!("Failed to encrypt attachment key: {}", e))?;

    // Create multipart form data
    let form = reqwest::multipart::Form::new()
        .text("key", encrypted_attachment_key)
        .part(
            "data",
            reqwest::multipart::Part::bytes(encrypted_file_data)
                .file_name(file_name.to_string())
                .mime_str("application/octet-stream")
                .map_err(|e| format!("Failed to create form part: {}", e))?
        );

    // Upload via API
    let updated_cipher: CipherResponse = api_client
        .make_multipart_request(
            reqwest::Method::POST,
            &format!("/ciphers/{}/attachment", cipher_id),
            form
        )
        .await
        .map_err(|e| e.to_string())?;

    // Decrypt and return updated cipher
    let decrypted_cipher = crypto_service
        .decrypt_cipher(updated_cipher)
        .await
        .map_err(|e| e.to_string())?;

    Ok(decrypted_cipher)
}

#[tauri::command]
pub async fn download_attachment(
    cipher_id: String,
    attachment_id: String,
    save_path: String,
    api_client: State<'_, ApiClientState>,
    crypto_service: State<'_, CryptoService>
) -> Result<String, String> {
    // Download encrypted attachment data
    let encrypted_data = api_client
        .download_attachment(&cipher_id, &attachment_id)
        .await
        .map_err(|e| e.to_string())?;

    // Get attachment key from cipher
    let attachment_key = crypto_service
        .get_attachment_key(&cipher_id, &attachment_id)
        .await
        .map_err(|e| e.to_string())?;

    // Decrypt attachment data
    let decrypted_data = crypto_service
        .decrypt_attachment_data(&encrypted_data, &attachment_key)
        .await
        .map_err(|e| format!("Failed to decrypt attachment: {}", e))?;

    // Save to specified path
    let save_path = PathBuf::from(save_path);
    fs::write(&save_path, decrypted_data)
        .await
        .map_err(|e| format!("Failed to save file: {}", e))?;

    Ok(save_path.to_string_lossy().to_string())
}

#[tauri::command]
pub async fn delete_attachment(
    cipher_id: String,
    attachment_id: String,
    api_client: State<'_, ApiClientState>
) -> Result<(), String> {
    api_client
        .make_authenticated_request(
            reqwest::Method::DELETE,
            &format!("/ciphers/{}/attachment/{}", cipher_id, attachment_id),
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}
```

#### Frontend Usage

```typescript
// src/services/attachment.service.ts
import { invoke } from '@tauri-apps/api/tauri';
import { open, save } from '@tauri-apps/api/dialog';

export class AttachmentService {
    async uploadAttachment(cipherId: string): Promise<CipherView> {
        // Open file picker
        const filePath = await open({
            multiple: false,
            filters: [{
                name: 'All Files',
                extensions: ['*']
            }]
        });

        if (!filePath || Array.isArray(filePath)) {
            throw new Error('No file selected');
        }

        return await invoke('upload_attachment', {
            cipherId,
            filePath
        });
    }

    async downloadAttachment(
        cipherId: string,
        attachmentId: string,
        fileName: string
    ): Promise<string> {
        // Open save dialog
        const savePath = await save({
            defaultPath: fileName,
            filters: [{
                name: 'All Files',
                extensions: ['*']
            }]
        });

        if (!savePath) {
            throw new Error('No save location selected');
        }

        return await invoke('download_attachment', {
            cipherId,
            attachmentId,
            savePath
        });
    }

    async deleteAttachment(cipherId: string, attachmentId: string): Promise<void> {
        return await invoke('delete_attachment', {
            cipherId,
            attachmentId
        });
    }
}
  "name": "2.encrypted_cipher_name|base64_encoded_data",
  "notes": null,
  "favorite": false,
  "organizationUseTotp": false,
  "edit": true,
  "viewPassword": true,
  "revisionDate": "2023-12-01T16:30:00.000Z",
  "creationDate": "2023-11-01T09:15:00.000Z",
  "deletedDate": null,
  "reprompt": 0,
  "login": {
    "username": "2.encrypted_username|base64_encoded_data",
    "password": "2.encrypted_password|base64_encoded_data",
    "passwordRevisionDate": null,
    "totp": null,
    "autofillOnPageLoad": null,
    "uris": [],
    "fido2Credentials": []
  },
  "secureNote": null,
  "card": null,
  "identity": null,
  "sshKey": null,
  "fields": [],
  "attachments": [
    {
      "id": "attachment-87654321-4321-4321-4321-210987654321",
      "url": "https://vault.bitwarden.com/attachments/cipher-12345678-1234-1234-1234-123456789012/attachment-87654321-4321-4321-4321-210987654321",
      "fileName": "2.encrypted_filename|base64_encoded_data",
      "key": "2.encrypted_attachment_key|base64_encoded_data",
      "size": "1048576",
      "sizeName": "1 MB",
      "object": "attachment"
    }
  ],
  "passwordHistory": [],
  "collectionIds": [],
  "key": null,
  "object": "cipher"
}
```

#### Implementation Example

```typescript
interface AttachmentResponse {
  id: string;
  url: string;
  fileName: string;
  key: string;
  size: string;
  sizeName: string;
  object: 'attachment';
}

async function createAttachment(
  cipherId: string,
  file: File,
  attachmentKey: string
): Promise<CipherResponse> {
  const formData = new FormData();
  formData.append('key', attachmentKey);
  formData.append('data', file);

  const response = await fetch(`/ciphers/${cipherId}/attachment`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`
      // Don't set Content-Type - let browser set it with boundary
    },
    body: formData
  });

  if (!response.ok) {
    throw new Error('Failed to create attachment');
  }

  return response.json();
}

// Helper function to create encrypted attachment
async function createEncryptedAttachment(
  cipherId: string,
  file: File
): Promise<CipherResponse> {
  // 1. Generate attachment key
  const attachmentKey = await generateAttachmentKey();

  // 2. Encrypt the attachment key with user key
  const userKey = await getUserKey();
  const encryptedAttachmentKey = await encryptBytes(attachmentKey, userKey);

  // 3. Encrypt filename
  const encryptedFileName = await encryptString(file.name, userKey);

  // 4. Create attachment (file is encrypted server-side with the attachment key)
  return createAttachment(cipherId, file, encryptedAttachmentKey);
}
```

---

### 2. Download Attachment

**Endpoint:** `GET /attachments/{id}`
**Authentication:** Bearer token required
**Purpose:** Download an attachment file

#### Request

```http
GET /attachments/attachment-87654321-4321-4321-4321-210987654321
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

Returns the encrypted file data as binary stream:

```
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="encrypted_file_data"
Content-Length: 1048576

[Encrypted binary file data]
```

#### Rust Implementation Example

```rust
// src-tauri/src/attachment/download.rs
use reqwest::Client;
use bytes::Bytes;

async fn download_attachment(
    attachment_id: &str,
    access_token: &str
) -> Result<Bytes, reqwest::Error> {
    let client = Client::new();

    let response = client
        .get(&format!("https://api.bitwarden.com/attachments/{}", attachment_id))
        .header("Authorization", format!("Bearer {}", access_token))
        .send()
        .await?;

    match response.status() {
        reqwest::StatusCode::NOT_FOUND => {
            Err(reqwest::Error::from(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "Attachment not found"
            )))
        }
        status if status.is_success() => {
            response.bytes().await
        }
        _ => {
            Err(reqwest::Error::from(response.error_for_status().unwrap_err()))
        }
    }
}

// Helper function to download and decrypt attachment
async function downloadAndDecryptAttachment(
  attachment: AttachmentResponse,
  userKey: SymmetricCryptoKey
): Promise<{ data: ArrayBuffer; fileName: string }> {
  // 1. Download encrypted file
  const encryptedData = await downloadAttachment(attachment.id);

  // 2. Decrypt attachment key
  const attachmentKey = await decryptBytes(attachment.key, userKey);

  // 3. Decrypt file data
  const decryptedData = await decryptFileData(encryptedData, attachmentKey);

  // 4. Decrypt filename
  const fileName = await decryptString(attachment.fileName, userKey);

  return {
    data: decryptedData,
    fileName
  };
}
```

---

### 3. Delete Attachment

**Endpoint:** `DELETE /ciphers/{cipherId}/attachment/{attachmentId}`
**Authentication:** Bearer token required
**Purpose:** Delete an attachment from a cipher

#### Request

```http
DELETE /ciphers/cipher-12345678-1234-1234-1234-123456789012/attachment/attachment-87654321-4321-4321-4321-210987654321
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```
200 OK
```

#### Implementation Example

```typescript
async function deleteAttachment(cipherId: string, attachmentId: string): Promise<void> {
  const response = await fetch(`/ciphers/${cipherId}/attachment/${attachmentId}`, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${accessToken}`
    }
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('Attachment not found');
    }
    throw new Error('Failed to delete attachment');
  }
}
```

---

### 4. Get Attachment Info

**Endpoint:** `GET /ciphers/{id}/attachment/{attachmentId}`
**Authentication:** Bearer token required
**Purpose:** Get attachment metadata without downloading the file

#### Request

```http
GET /ciphers/cipher-12345678-1234-1234-1234-123456789012/attachment/attachment-87654321-4321-4321-4321-210987654321
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```json
{
  "id": "attachment-87654321-4321-4321-4321-210987654321",
  "url": "https://vault.bitwarden.com/attachments/cipher-12345678-1234-1234-1234-123456789012/attachment-87654321-4321-4321-4321-210987654321",
  "fileName": "2.encrypted_filename|base64_encoded_data",
  "key": "2.encrypted_attachment_key|base64_encoded_data",
  "size": "1048576",
  "sizeName": "1 MB",
  "object": "attachment"
}
```

#### Rust Implementation Example

```rust
// src-tauri/src/attachment/info.rs
use reqwest::Client;
use serde::Deserialize;
use chrono::{DateTime, Utc};

#[derive(Deserialize)]
struct AttachmentResponse {
    id: String,
    url: String,
    file_name: String,
    key: String,
    size: u64,
    size_name: String,
    revision_date: DateTime<Utc>,
}

async fn get_attachment_info(
    cipher_id: &str,
    attachment_id: &str,
    access_token: &str
) -> Result<AttachmentResponse, reqwest::Error> {
    let client = Client::new();

    let response = client
        .get(&format!(
            "https://api.bitwarden.com/ciphers/{}/attachment/{}",
            cipher_id,
            attachment_id
        ))
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .send()
        .await?;

    match response.status() {
        reqwest::StatusCode::NOT_FOUND => {
            Err(reqwest::Error::from(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "Attachment not found"
            )))
        }
        status if status.is_success() => {
            response.json::<AttachmentResponse>().await
        }
        _ => {
            Err(reqwest::Error::from(response.error_for_status().unwrap_err()))
        }
    }
}
```

## Attachment Management

### 1. File Encryption and Decryption

```typescript
class AttachmentCryptoService {
  // Generate a new attachment key
  async generateAttachmentKey(): Promise<Uint8Array> {
    return crypto.getRandomValues(new Uint8Array(64)); // 512-bit key
  }

  // Encrypt file data with attachment key
  async encryptFileData(data: ArrayBuffer, key: Uint8Array): Promise<ArrayBuffer> {
    const algorithm = { name: 'AES-CBC', iv: crypto.getRandomValues(new Uint8Array(16)) };
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      key.slice(0, 32), // Use first 32 bytes for AES-256
      algorithm,
      false,
      ['encrypt']
    );

    const encrypted = await crypto.subtle.encrypt(algorithm, cryptoKey, data);

    // Prepend IV to encrypted data
    const result = new Uint8Array(16 + encrypted.byteLength);
    result.set(algorithm.iv, 0);
    result.set(new Uint8Array(encrypted), 16);

    return result.buffer;
  }

  // Decrypt file data with attachment key
  async decryptFileData(encryptedData: ArrayBuffer, key: Uint8Array): Promise<ArrayBuffer> {
    const data = new Uint8Array(encryptedData);
    const iv = data.slice(0, 16);
    const encrypted = data.slice(16);

    const algorithm = { name: 'AES-CBC', iv };
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      key.slice(0, 32), // Use first 32 bytes for AES-256
      algorithm,
      false,
      ['decrypt']
    );

    return crypto.subtle.decrypt(algorithm, cryptoKey, encrypted);
  }

  // Encrypt attachment key with user key
  async encryptAttachmentKey(attachmentKey: Uint8Array, userKey: SymmetricCryptoKey): Promise<string> {
    return encryptBytes(attachmentKey, userKey);
  }

  // Decrypt attachment key with user key
  async decryptAttachmentKey(encryptedKey: string, userKey: SymmetricCryptoKey): Promise<Uint8Array> {
    return decryptBytes(encryptedKey, userKey);
  }
}
```

### 2. File Upload with Progress

```typescript
class AttachmentUploadService {
  async uploadAttachmentWithProgress(
    cipherId: string,
    file: File,
    onProgress?: (progress: number) => void
  ): Promise<CipherResponse> {
    // 1. Generate and encrypt attachment key
    const cryptoService = new AttachmentCryptoService();
    const attachmentKey = await cryptoService.generateAttachmentKey();
    const userKey = await getUserKey();
    const encryptedAttachmentKey = await cryptoService.encryptAttachmentKey(attachmentKey, userKey);

    // 2. Create form data
    const formData = new FormData();
    formData.append('key', encryptedAttachmentKey);
    formData.append('data', file);

    // 3. Upload with progress tracking
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();

      xhr.upload.addEventListener('progress', (event) => {
        if (event.lengthComputable && onProgress) {
          const progress = (event.loaded / event.total) * 100;
          onProgress(progress);
        }
      });

      xhr.addEventListener('load', () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve(JSON.parse(xhr.responseText));
        } else {
          reject(new Error(`Upload failed: ${xhr.status}`));
        }
      });

      xhr.addEventListener('error', () => {
        reject(new Error('Upload failed'));
      });

      xhr.open('POST', `/ciphers/${cipherId}/attachment`);
      xhr.setRequestHeader('Authorization', `Bearer ${accessToken}`);
      xhr.send(formData);
    });
  }
}
```

### 3. File Type Validation and Restrictions

```typescript
class AttachmentValidationService {
  private readonly MAX_FILE_SIZE = 100 * 1024 * 1024; // 100MB
  private readonly ALLOWED_EXTENSIONS = [
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.txt', '.rtf', '.csv', '.json', '.xml',
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg',
    '.mp3', '.mp4', '.avi', '.mov', '.wmv',
    '.zip', '.rar', '.7z', '.tar', '.gz'
  ];

  validateFile(file: File): void {
    // Check file size
    if (file.size > this.MAX_FILE_SIZE) {
      throw new AttachmentError(
        `File size exceeds maximum allowed size of ${this.formatFileSize(this.MAX_FILE_SIZE)}`,
        'FILE_TOO_LARGE'
      );
    }

    // Check file extension
    const extension = this.getFileExtension(file.name);
    if (!this.ALLOWED_EXTENSIONS.includes(extension.toLowerCase())) {
      throw new AttachmentError(
        `File type '${extension}' is not allowed`,
        'FILE_TYPE_NOT_ALLOWED'
      );
    }

    // Check for empty file
    if (file.size === 0) {
      throw new AttachmentError('Cannot upload empty file', 'FILE_EMPTY');
    }
  }

  private getFileExtension(fileName: string): string {
    const lastDotIndex = fileName.lastIndexOf('.');
    return lastDotIndex >= 0 ? fileName.substring(lastDotIndex) : '';
  }

  private formatFileSize(bytes: number): string {
    const units = ['B', 'KB', 'MB', 'GB'];
    let size = bytes;
    let unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return `${size.toFixed(1)} ${units[unitIndex]}`;
  }
}
```

### 4. Attachment Management Service

```typescript
class AttachmentManagementService {
  private cryptoService = new AttachmentCryptoService();
  private uploadService = new AttachmentUploadService();
  private validationService = new AttachmentValidationService();

  // Upload attachment with full validation and encryption
  async uploadAttachment(
    cipherId: string,
    file: File,
    onProgress?: (progress: number) => void
  ): Promise<AttachmentView> {
    // Validate file
    this.validationService.validateFile(file);

    // Upload with progress
    const updatedCipher = await this.uploadService.uploadAttachmentWithProgress(
      cipherId,
      file,
      onProgress
    );

    // Return the new attachment
    const newAttachment = updatedCipher.attachments?.find(
      att => att.fileName.includes(file.name) // Simplified matching
    );

    if (!newAttachment) {
      throw new AttachmentError('Attachment not found in response', 'ATTACHMENT_NOT_FOUND');
    }

    return this.decryptAttachmentView(newAttachment);
  }

  // Download and save attachment
  async downloadAttachment(attachment: AttachmentResponse): Promise<void> {
    const userKey = await getUserKey();
    const { data, fileName } = await downloadAndDecryptAttachment(attachment, userKey);

    // Create download link
    const blob = new Blob([data]);
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  // Get all attachments for a cipher
  async getCipherAttachments(cipherId: string): Promise<AttachmentView[]> {
    const cipher = await getCipher(cipherId);
    if (!cipher.attachments) {
      return [];
    }

    return Promise.all(
      cipher.attachments.map(att => this.decryptAttachmentView(att))
    );
  }

  // Delete attachment with confirmation
  async deleteAttachmentSafely(
    cipherId: string,
    attachmentId: string,
    confirmCallback?: () => Promise<boolean>
  ): Promise<void> {
    if (confirmCallback) {
      const confirmed = await confirmCallback();
      if (!confirmed) {
        return;
      }
    }

    await deleteAttachment(cipherId, attachmentId);
  }

  // Decrypt attachment view for display
  private async decryptAttachmentView(attachment: AttachmentResponse): Promise<AttachmentView> {
    const userKey = await getUserKey();
    const fileName = await decryptString(attachment.fileName, userKey);

    return {
      id: attachment.id,
      url: attachment.url,
      fileName,
      size: parseInt(attachment.size),
      sizeName: attachment.sizeName,
      key: attachment.key
    };
  }
}

interface AttachmentView {
  id: string;
  url: string;
  fileName: string;
  size: number;
  sizeName: string;
  key: string;
}
```

## Error Handling

### Attachment-Specific Errors

```typescript
class AttachmentError extends Error {
  constructor(
    message: string,
    public code: string,
    public attachmentId?: string
  ) {
    super(message);
    this.name = 'AttachmentError';
  }
}

async function handleAttachmentOperation<T>(
  operation: () => Promise<T>,
  attachmentId?: string
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    if (error.status === 404) {
      throw new AttachmentError('Attachment not found', 'ATTACHMENT_NOT_FOUND', attachmentId);
    } else if (error.status === 403) {
      throw new AttachmentError('Access denied to attachment', 'ATTACHMENT_ACCESS_DENIED', attachmentId);
    } else if (error.status === 413) {
      throw new AttachmentError('File too large', 'ATTACHMENT_TOO_LARGE', attachmentId);
    } else if (error.status === 415) {
      throw new AttachmentError('Unsupported file type', 'ATTACHMENT_UNSUPPORTED_TYPE', attachmentId);
    } else if (error.status === 507) {
      throw new AttachmentError('Storage quota exceeded', 'STORAGE_QUOTA_EXCEEDED', attachmentId);
    } else {
      throw new AttachmentError('Attachment operation failed', 'ATTACHMENT_OPERATION_FAILED', attachmentId);
    }
  }
}
```

## Storage Considerations

### Premium Features
- Attachments require premium subscription or organization membership
- Free accounts cannot upload attachments
- Storage limits apply based on subscription tier

### File Size Limits
- Individual file: 100MB maximum
- Total storage varies by plan:
  - Premium: 1GB
  - Family: 1GB shared
  - Organization: Varies by plan

### Security Features
- All files encrypted with unique attachment keys
- Attachment keys encrypted with user's vault key
- Server-side virus scanning
- Secure deletion when attachments are removed
