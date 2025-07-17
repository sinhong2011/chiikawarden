# Cipher Management API Documentation - Tauri Best Practices

## Overview

The Cipher Management API handles all vault item operations including creation, reading, updating, and deletion of passwords, secure notes, cards, identities, and SSH keys. **All cipher operations must be implemented in the Rust backend** for security, encryption, and proper data handling.

## Security Architecture

### ✅ Correct Implementation Pattern
```
SolidJS Frontend → invoke('cipher_command') → Rust Backend → Encryption → Bitwarden API
```

### ❌ Never Do This
```typescript
// WRONG: Direct cipher operations from frontend
const ciphers = await fetch('/ciphers', { headers: { Authorization: token } });
```

## Endpoints

### 1. Get All Ciphers

**Endpoint:** `GET /ciphers`
**Authentication:** Bearer token required
**Purpose:** Retrieve all ciphers accessible to the user

#### Request

```http
GET /ciphers
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```json
{
  "data": [
    {
      "id": "cipher-12345678-1234-1234-1234-123456789012",
      "organizationId": null,
      "folderId": "folder-12345678-1234-1234-1234-123456789012",
      "type": 1,
      "name": "2.encrypted_name|base64_encoded_data",
      "notes": "2.encrypted_notes|base64_encoded_data",
      "favorite": false,
      "organizationUseTotp": false,
      "edit": true,
      "viewPassword": true,
      "revisionDate": "2023-12-01T10:30:00.000Z",
      "creationDate": "2023-11-01T09:15:00.000Z",
      "deletedDate": null,
      "reprompt": 0,
      "login": {
        "username": "2.encrypted_username|base64_encoded_data",
        "password": "2.encrypted_password|base64_encoded_data",
        "passwordRevisionDate": "2023-11-01T09:15:00.000Z",
        "totp": "2.encrypted_totp|base64_encoded_data",
        "autofillOnPageLoad": null,
        "uris": [
          {
            "uri": "2.encrypted_uri|base64_encoded_data",
            "match": null,
            "uriChecksum": "uri_checksum_value"
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
          "name": "2.encrypted_field_name|base64_encoded_data",
          "value": "2.encrypted_field_value|base64_encoded_data",
          "linkedId": null
        }
      ],
      "attachments": null,
      "passwordHistory": [
        {
          "password": "2.encrypted_old_password|base64_encoded_data",
          "lastUsedDate": "2023-10-01T08:00:00.000Z"
        }
      ],
      "collectionIds": [],
      "key": null,
      "object": "cipher"
    }
  ],
  "object": "list"
}
```

#### Cipher Types
- `1` - Login
- `2` - Secure Note
- `3` - Card
- `4` - Identity
- `5` - SSH Key

#### Reprompt Types
- `0` - None
- `1` - Password (require master password before viewing)

#### Implementation Example

```typescript
interface CipherListResponse {
  data: CipherResponse[];
  object: 'list';
}

async function getAllCiphers(): Promise<CipherResponse[]> {
  const response = await fetch('/ciphers', {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    }
  });

  if (!response.ok) {
    throw new Error('Failed to fetch ciphers');
  }

  const result: CipherListResponse = await response.json();
  return result.data;
}
```

---

### 2. Get Cipher by ID

**Endpoint:** `GET /ciphers/{id}`
**Authentication:** Bearer token required
**Purpose:** Retrieve a specific cipher by its ID

#### Request

```http
GET /ciphers/cipher-12345678-1234-1234-1234-123456789012
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```json
{
  "id": "cipher-12345678-1234-1234-1234-123456789012",
  "organizationId": null,
  "folderId": "folder-12345678-1234-1234-1234-123456789012",
  "type": 1,
  "name": "2.encrypted_name|base64_encoded_data",
  "notes": "2.encrypted_notes|base64_encoded_data",
  "favorite": false,
  "organizationUseTotp": false,
  "edit": true,
  "viewPassword": true,
  "revisionDate": "2023-12-01T10:30:00.000Z",
  "creationDate": "2023-11-01T09:15:00.000Z",
  "deletedDate": null,
  "reprompt": 0,
  "login": {
    "username": "2.encrypted_username|base64_encoded_data",
    "password": "2.encrypted_password|base64_encoded_data",
    "passwordRevisionDate": "2023-11-01T09:15:00.000Z",
    "totp": "2.encrypted_totp|base64_encoded_data",
    "autofillOnPageLoad": null,
    "uris": [
      {
        "uri": "2.encrypted_uri|base64_encoded_data",
        "match": 0,
        "uriChecksum": "uri_checksum_value"
      }
    ],
    "fido2Credentials": []
  },
  "secureNote": null,
  "card": null,
  "identity": null,
  "sshKey": null,
  "fields": [],
  "attachments": null,
  "passwordHistory": [],
  "collectionIds": [],
  "key": null,
  "object": "cipher"
}
```

#### URI Match Types
- `null` - Default (domain matching)
- `0` - Domain
- `1` - Host
- `2` - Starts with
- `3` - Exact
- `4` - Regular expression
- `5` - Never

#### Rust Implementation Example

```rust
// src-tauri/src/cipher/api.rs
use reqwest::Client;
use serde::Deserialize;

#[derive(Deserialize)]
struct CipherResponse {
    id: String,
    organization_id: Option<String>,
    folder_id: Option<String>,
    r#type: u8,
    name: String,
    notes: Option<String>,
    favorite: bool,
    // ... other fields
}

async fn get_cipher(id: &str, access_token: &str) -> Result<CipherResponse, reqwest::Error> {
    let client = Client::new();

    let response = client
        .get(&format!("https://api.bitwarden.com/ciphers/{}", id))
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .send()
        .await?;

    match response.status() {
        reqwest::StatusCode::NOT_FOUND => {
            Err(reqwest::Error::from(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "Cipher not found"
            )))
        }
        status if status.is_success() => {
            response.json::<CipherResponse>().await
        }
        _ => {
            Err(reqwest::Error::from(response.error_for_status().unwrap_err()))
        }
    }
}
```

---

### 3. Create Cipher

**Endpoint:** `POST /ciphers`
**Authentication:** Bearer token required
**Purpose:** Create a new cipher

#### Login Cipher Request

```json
{
  "type": 1,
  "name": "2.encrypted_name|base64_encoded_data",
  "notes": "2.encrypted_notes|base64_encoded_data",
  "favorite": false,
  "folderId": "folder-12345678-1234-1234-1234-123456789012",
  "organizationId": null,
  "reprompt": 0,
  "login": {
    "username": "2.encrypted_username|base64_encoded_data",
    "password": "2.encrypted_password|base64_encoded_data",
    "passwordRevisionDate": "2023-12-01T10:30:00.000Z",
    "totp": "2.encrypted_totp|base64_encoded_data",
    "autofillOnPageLoad": null,
    "uris": [
      {
        "uri": "2.encrypted_uri|base64_encoded_data",
        "match": 0,
        "uriChecksum": "uri_checksum_value"
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
      "name": "2.encrypted_field_name|base64_encoded_data",
      "value": "2.encrypted_field_value|base64_encoded_data",
      "linkedId": null
    }
  ],
  "passwordHistory": [],
  "key": null
}
```

#### Secure Note Cipher Request

```json
{
  "type": 2,
  "name": "2.encrypted_note_name|base64_encoded_data",
  "notes": "2.encrypted_note_content|base64_encoded_data",
  "favorite": false,
  "folderId": null,
  "organizationId": null,
  "reprompt": 0,
  "login": null,
  "secureNote": {
    "type": 0
  },
  "card": null,
  "identity": null,
  "sshKey": null,
  "fields": [],
  "passwordHistory": [],
  "key": null
}
```

#### Card Cipher Request

```json
{
  "type": 3,
  "name": "2.encrypted_card_name|base64_encoded_data",
  "notes": "2.encrypted_notes|base64_encoded_data",
  "favorite": false,
  "folderId": null,
  "organizationId": null,
  "reprompt": 1,
  "login": null,
  "secureNote": null,
  "card": {
    "cardholderName": "2.encrypted_cardholder_name|base64_encoded_data",
    "brand": "2.encrypted_brand|base64_encoded_data",
    "number": "2.encrypted_number|base64_encoded_data",
    "expMonth": "2.encrypted_exp_month|base64_encoded_data",
    "expYear": "2.encrypted_exp_year|base64_encoded_data",
    "code": "2.encrypted_cvv|base64_encoded_data"
  },
  "identity": null,
  "sshKey": null,
  "fields": [],
  "passwordHistory": [],
  "key": null
}
```

#### Identity Cipher Request

```json
{
  "type": 4,
  "name": "2.encrypted_identity_name|base64_encoded_data",
  "notes": "2.encrypted_notes|base64_encoded_data",
  "favorite": false,
  "folderId": null,
  "organizationId": null,
  "reprompt": 0,
  "login": null,
  "secureNote": null,
  "card": null,
  "identity": {
    "title": "2.encrypted_title|base64_encoded_data",
    "firstName": "2.encrypted_first_name|base64_encoded_data",
    "middleName": "2.encrypted_middle_name|base64_encoded_data",
    "lastName": "2.encrypted_last_name|base64_encoded_data",
    "address1": "2.encrypted_address1|base64_encoded_data",
    "address2": "2.encrypted_address2|base64_encoded_data",
    "address3": "2.encrypted_address3|base64_encoded_data",
    "city": "2.encrypted_city|base64_encoded_data",
    "state": "2.encrypted_state|base64_encoded_data",
    "postalCode": "2.encrypted_postal_code|base64_encoded_data",
    "country": "2.encrypted_country|base64_encoded_data",
    "company": "2.encrypted_company|base64_encoded_data",
    "email": "2.encrypted_email|base64_encoded_data",
    "phone": "2.encrypted_phone|base64_encoded_data",
    "ssn": "2.encrypted_ssn|base64_encoded_data",
    "username": "2.encrypted_username|base64_encoded_data",
    "passportNumber": "2.encrypted_passport|base64_encoded_data",
    "licenseNumber": "2.encrypted_license|base64_encoded_data"
  },
  "sshKey": null,
  "fields": [],
  "passwordHistory": [],
  "key": null
}
```

#### SSH Key Cipher Request

```json
{
  "type": 5,
  "name": "2.encrypted_ssh_key_name|base64_encoded_data",
  "notes": "2.encrypted_notes|base64_encoded_data",
  "favorite": false,
  "folderId": null,
  "organizationId": null,
  "reprompt": 1,
  "login": null,
  "secureNote": null,
  "card": null,
  "identity": null,
  "sshKey": {
    "privateKey": "2.encrypted_private_key|base64_encoded_data",
    "publicKey": "2.encrypted_public_key|base64_encoded_data",
    "keyFingerprint": "2.encrypted_fingerprint|base64_encoded_data"
  },
  "fields": [],
  "passwordHistory": [],
  "key": null
}
```

#### Field Types
- `0` - Text
- `1` - Hidden
- `2` - Boolean
- `3` - Linked (auto-filled from other cipher data)
- `4` - HTML
- `5` - Email

#### Response

Returns the created cipher with the same structure as GET response, including the generated ID.

## Mutation Hooks

### Create, Update, Delete Operations

```typescript
// src/hooks/useCipherMutations.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { cipherKeys } from '../api/queryKeys';

export function useCreateCipher() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (cipherView: CipherView) => {
      const userId = await getCurrentUserId();
      const encryptionContext = await cipherService.encrypt(cipherView, userId);
      return cipherApiService.createCipher(encryptionContext.cipher);
    },
    onSuccess: (newCipher, variables) => {
      // Invalidate and refetch cipher lists
      queryClient.invalidateQueries({ queryKey: cipherKeys.lists() });

      // Optimistically add to cache
      queryClient.setQueryData(
        cipherKeys.detail(newCipher.id),
        variables
      );

      // Update specific filtered lists
      if (variables.type) {
        queryClient.invalidateQueries({ queryKey: cipherKeys.byType(variables.type) });
      }
      if (variables.folderId) {
        queryClient.invalidateQueries({ queryKey: cipherKeys.byFolder(variables.folderId) });
      }
      if (variables.favorite) {
        queryClient.invalidateQueries({ queryKey: cipherKeys.favorites() });
      }
    },
    onError: (error) => {
      console.error('Failed to create cipher:', error);
    },
  });
}

export function useUpdateCipher() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, cipherView }: { id: string; cipherView: CipherView }) => {
      const userId = await getCurrentUserId();
      const encryptionContext = await cipherService.encrypt(cipherView, userId);
      return cipherApiService.updateCipher(id, encryptionContext.cipher);
    },
    onMutate: async ({ id, cipherView }) => {
      // Cancel outgoing refetches
      await queryClient.cancelQueries({ queryKey: cipherKeys.detail(id) });

      // Snapshot previous value
      const previousCipher = queryClient.getQueryData(cipherKeys.detail(id));

      // Optimistically update
      queryClient.setQueryData(cipherKeys.detail(id), cipherView);

      return { previousCipher };
    },
    onError: (error, variables, context) => {
      // Rollback on error
      if (context?.previousCipher) {
        queryClient.setQueryData(cipherKeys.detail(variables.id), context.previousCipher);
      }
    },
    onSettled: (data, error, variables) => {
      // Always refetch after mutation
      queryClient.invalidateQueries({ queryKey: cipherKeys.detail(variables.id) });
      queryClient.invalidateQueries({ queryKey: cipherKeys.lists() });
    },
  });
}

export function useDeleteCipher() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => cipherApiService.deleteCipher(id),
    onMutate: async (id) => {
      // Cancel outgoing refetches
      await queryClient.cancelQueries({ queryKey: cipherKeys.detail(id) });

      // Remove from cache
      queryClient.removeQueries({ queryKey: cipherKeys.detail(id) });

      // Optimistically remove from lists
      queryClient.setQueriesData(
        { queryKey: cipherKeys.lists() },
        (oldData: CipherView[] | undefined) =>
          oldData?.filter(cipher => cipher.id !== id)
      );
    },
    onError: (error, id) => {
      // Refetch on error to restore state
      queryClient.invalidateQueries({ queryKey: cipherKeys.lists() });
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: cipherKeys.lists() });
    },
  });
}

export function useBulkDeleteCiphers() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (ids: string[]) => cipherApiService.bulkDeleteCiphers(ids),
    onSuccess: (data, ids) => {
      // Remove from cache
      ids.forEach(id => {
        queryClient.removeQueries({ queryKey: cipherKeys.detail(id) });
      });

      // Invalidate lists
      queryClient.invalidateQueries({ queryKey: cipherKeys.lists() });
    },
  });
}
```

#### TanStack Query Implementation

```typescript
// Create cipher component
function CreateCipherForm() {
  const createCipher = useCreateCipher();
  const navigate = useNavigate();

  const handleSubmit = async (formData: CipherFormData) => {
    try {
      const cipherView = await buildCipherFromForm(formData);
      const result = await createCipher.mutateAsync(cipherView);
      navigate(`/vault/cipher/${result.id}`);
    } catch (error) {
      // Error is handled by the mutation
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      {/* Form fields */}
      <button
        type="submit"
        disabled={createCipher.isPending}
      >
        {createCipher.isPending ? 'Creating...' : 'Create Cipher'}
      </button>
      {createCipher.error && (
        <ErrorMessage error={createCipher.error} />
      )}
    </form>
  );
}

// Update cipher component
function EditCipherForm({ id }: { id: string }) {
  const { data: cipher } = useCipher(id);
  const updateCipher = useUpdateCipher();

  const handleSubmit = async (formData: CipherFormData) => {
    const updatedCipher = await buildCipherFromForm(formData, cipher);
    await updateCipher.mutateAsync({ id, cipherView: updatedCipher });
  };

  return (
    <form onSubmit={handleSubmit}>
      {/* Form fields pre-filled with cipher data */}
      <button
        type="submit"
        disabled={updateCipher.isPending}
      >
        {updateCipher.isPending ? 'Saving...' : 'Save Changes'}
      </button>
    </form>
  );
}
```

#### Traditional Implementation

```typescript
interface CipherRequest {
  type: CipherType;
  name: string;
  notes?: string;
  favorite: boolean;
  folderId?: string;
  organizationId?: string;
  reprompt: RepromptType;
  login?: LoginRequest;
  secureNote?: SecureNoteRequest;
  card?: CardRequest;
  identity?: IdentityRequest;
  sshKey?: SshKeyRequest;
  fields?: FieldRequest[];
  passwordHistory?: PasswordHistoryRequest[];
  key?: string;
}

async function createCipher(cipherData: CipherRequest): Promise<CipherResponse> {
  const response = await fetch('/ciphers', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(cipherData)
  });

  if (!response.ok) {
    throw new Error('Failed to create cipher');
  }

  return response.json();
}

// Helper function to create encrypted login cipher
async function createLoginCipher(
  name: string,
  username: string,
  password: string,
  uri: string,
  folderId?: string
): Promise<CipherResponse> {
  const userKey = await getUserKey();

  const cipherRequest: CipherRequest = {
    type: CipherType.Login,
    name: await encryptString(name, userKey),
    notes: null,
    favorite: false,
    folderId,
    organizationId: null,
    reprompt: RepromptType.None,
    login: {
      username: await encryptString(username, userKey),
      password: await encryptString(password, userKey),
      passwordRevisionDate: new Date().toISOString(),
      totp: null,
      autofillOnPageLoad: null,
      uris: [
        {
          uri: await encryptString(uri, userKey),
          match: UriMatchType.Domain,
          uriChecksum: await generateUriChecksum(uri)
        }
      ],
      fido2Credentials: []
    },
    secureNote: null,
    card: null,
    identity: null,
    sshKey: null,
    fields: [],
    passwordHistory: [],
    key: null
  };

  return createCipher(cipherRequest);
}
```

---

### 4. Update Cipher

**Endpoint:** `PUT /ciphers/{id}`
**Authentication:** Bearer token required
**Purpose:** Update an existing cipher

#### Request

Same structure as create request, but sent to the specific cipher ID endpoint.

#### Response

Returns the updated cipher with new revision date.

#### Implementation Example

```typescript
async function updateCipher(id: string, cipherData: CipherRequest): Promise<CipherResponse> {
  const response = await fetch(`/ciphers/${id}`, {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(cipherData)
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('Cipher not found');
    }
    throw new Error('Failed to update cipher');
  }

  return response.json();
}
```

---

### 5. Delete Cipher

**Endpoint:** `DELETE /ciphers/{id}`
**Authentication:** Bearer token required
**Purpose:** Delete a cipher (moves to trash)

#### Request

```http
DELETE /ciphers/cipher-12345678-1234-1234-1234-123456789012
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```
200 OK
```

#### Implementation Example

```typescript
async function deleteCipher(id: string): Promise<void> {
  const response = await fetch(`/ciphers/${id}`, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${accessToken}`
    }
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('Cipher not found');
    }
    throw new Error('Failed to delete cipher');
  }
}
```

---

### 6. Bulk Delete Ciphers

**Endpoint:** `DELETE /ciphers`
**Authentication:** Bearer token required
**Purpose:** Delete multiple ciphers at once

#### Request

```json
{
  "ids": [
    "cipher-12345678-1234-1234-1234-123456789012",
    "cipher-87654321-4321-4321-4321-210987654321"
  ]
}
```

#### Response

```
200 OK
```

#### Implementation Example

```typescript
async function bulkDeleteCiphers(ids: string[]): Promise<void> {
  const response = await fetch('/ciphers', {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ ids })
  });

  if (!response.ok) {
    throw new Error('Failed to delete ciphers');
  }
}
```

---

### 7. Move Ciphers to Organization

**Endpoint:** `PUT /ciphers/move`
**Authentication:** Bearer token required
**Purpose:** Move personal ciphers to an organization

#### Request

```json
{
  "cipherIds": [
    "cipher-12345678-1234-1234-1234-123456789012"
  ],
  "organizationId": "org-12345678-1234-1234-1234-123456789012"
}
```

#### Response

```
200 OK
```

#### Implementation Example

```typescript
async function moveCiphersToOrganization(
  cipherIds: string[],
  organizationId: string
): Promise<void> {
  const response = await fetch('/ciphers/move', {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      cipherIds,
      organizationId
    })
  });

  if (!response.ok) {
    throw new Error('Failed to move ciphers to organization');
  }
}
```

---

### 8. Import Ciphers

**Endpoint:** `POST /ciphers/import`
**Authentication:** Bearer token required
**Purpose:** Bulk import ciphers and folders

#### Request

```json
{
  "ciphers": [
    {
      "type": 1,
      "name": "2.encrypted_name|base64_encoded_data",
      "notes": null,
      "favorite": false,
      "folderId": null,
      "organizationId": null,
      "reprompt": 0,
      "login": {
        "username": "2.encrypted_username|base64_encoded_data",
        "password": "2.encrypted_password|base64_encoded_data",
        "passwordRevisionDate": null,
        "totp": null,
        "autofillOnPageLoad": null,
        "uris": [
          {
            "uri": "2.encrypted_uri|base64_encoded_data",
            "match": null,
            "uriChecksum": null
          }
        ],
        "fido2Credentials": []
      },
      "secureNote": null,
      "card": null,
      "identity": null,
      "sshKey": null,
      "fields": [],
      "passwordHistory": [],
      "key": null
    }
  ],
  "folders": [
    {
      "name": "2.encrypted_folder_name|base64_encoded_data"
    }
  ],
  "folderRelationships": [
    [0, 0]
  ]
}
```

#### Folder Relationships
Array of `[cipherIndex, folderIndex]` pairs to assign ciphers to folders.

#### Response

```
200 OK
```

#### Implementation Example

```typescript
interface ImportRequest {
  ciphers: CipherRequest[];
  folders: FolderRequest[];
  folderRelationships: [number, number][];
}

async function importCiphers(importData: ImportRequest): Promise<void> {
  const response = await fetch('/ciphers/import', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(importData)
  });

  if (!response.ok) {
    throw new Error('Failed to import ciphers');
  }
}
```

## Encryption and Decryption

### Cipher Encryption Process

```typescript
async function encryptCipherForStorage(cipherView: CipherView): Promise<CipherRequest> {
  const userKey = await getUserKey();

  const encrypted: CipherRequest = {
    type: cipherView.type,
    name: await encryptString(cipherView.name, userKey),
    notes: cipherView.notes ? await encryptString(cipherView.notes, userKey) : null,
    favorite: cipherView.favorite,
    folderId: cipherView.folderId,
    organizationId: cipherView.organizationId,
    reprompt: cipherView.reprompt,
    login: null,
    secureNote: null,
    card: null,
    identity: null,
    sshKey: null,
    fields: [],
    passwordHistory: [],
    key: null
  };

  // Encrypt type-specific data
  if (cipherView.login) {
    encrypted.login = await encryptLogin(cipherView.login, userKey);
  }

  if (cipherView.secureNote) {
    encrypted.secureNote = await encryptSecureNote(cipherView.secureNote, userKey);
  }

  if (cipherView.card) {
    encrypted.card = await encryptCard(cipherView.card, userKey);
  }

  if (cipherView.identity) {
    encrypted.identity = await encryptIdentity(cipherView.identity, userKey);
  }

  if (cipherView.sshKey) {
    encrypted.sshKey = await encryptSshKey(cipherView.sshKey, userKey);
  }

  // Encrypt fields
  if (cipherView.fields) {
    encrypted.fields = await Promise.all(
      cipherView.fields.map(field => encryptField(field, userKey))
    );
  }

  // Encrypt password history
  if (cipherView.passwordHistory) {
    encrypted.passwordHistory = await Promise.all(
      cipherView.passwordHistory.map(history => encryptPasswordHistory(history, userKey))
    );
  }

  return encrypted;
}

async function encryptLogin(login: LoginView, key: SymmetricCryptoKey): Promise<LoginRequest> {
  return {
    username: login.username ? await encryptString(login.username, key) : null,
    password: login.password ? await encryptString(login.password, key) : null,
    passwordRevisionDate: login.passwordRevisionDate?.toISOString() || null,
    totp: login.totp ? await encryptString(login.totp, key) : null,
    autofillOnPageLoad: login.autofillOnPageLoad,
    uris: login.uris ? await Promise.all(
      login.uris.map(uri => encryptLoginUri(uri, key))
    ) : null,
    fido2Credentials: login.fido2Credentials || []
  };
}
```

### Cipher Decryption Process

```typescript
async function decryptCipherFromStorage(cipher: CipherResponse): Promise<CipherView> {
  const userKey = await getUserKey();

  const decrypted: CipherView = {
    id: cipher.id,
    organizationId: cipher.organizationId,
    folderId: cipher.folderId,
    type: cipher.type,
    name: await decryptString(cipher.name, userKey),
    notes: cipher.notes ? await decryptString(cipher.notes, userKey) : null,
    favorite: cipher.favorite,
    revisionDate: new Date(cipher.revisionDate),
    creationDate: new Date(cipher.creationDate),
    deletedDate: cipher.deletedDate ? new Date(cipher.deletedDate) : null,
    reprompt: cipher.reprompt,
    collectionIds: cipher.collectionIds || []
  };

  // Decrypt type-specific data
  if (cipher.login) {
    decrypted.login = await decryptLogin(cipher.login, userKey);
  }

  if (cipher.secureNote) {
    decrypted.secureNote = await decryptSecureNote(cipher.secureNote, userKey);
  }

  if (cipher.card) {
    decrypted.card = await decryptCard(cipher.card, userKey);
  }

  if (cipher.identity) {
    decrypted.identity = await decryptIdentity(cipher.identity, userKey);
  }

  if (cipher.sshKey) {
    decrypted.sshKey = await decryptSshKey(cipher.sshKey, userKey);
  }

  // Decrypt fields
  if (cipher.fields) {
    decrypted.fields = await Promise.all(
      cipher.fields.map(field => decryptField(field, userKey))
    );
  }

  // Decrypt password history
  if (cipher.passwordHistory) {
    decrypted.passwordHistory = await Promise.all(
      cipher.passwordHistory.map(history => decryptPasswordHistory(history, userKey))
    );
  }

  return decrypted;
}
```

## Search and Filtering

### Client-Side Search Implementation

```typescript
class CipherSearchService {
  searchCiphers(ciphers: CipherView[], query: string): CipherView[] {
    if (!query.trim()) {
      return ciphers;
    }

    const searchTerms = query.toLowerCase().split(' ');

    return ciphers.filter(cipher => {
      const searchableText = this.getSearchableText(cipher).toLowerCase();
      return searchTerms.every(term => searchableText.includes(term));
    });
  }

  private getSearchableText(cipher: CipherView): string {
    const parts = [cipher.name];

    if (cipher.notes) {
      parts.push(cipher.notes);
    }

    if (cipher.login) {
      if (cipher.login.username) parts.push(cipher.login.username);
      if (cipher.login.uris) {
        cipher.login.uris.forEach(uri => {
          if (uri.uri) parts.push(uri.uri);
        });
      }
    }

    if (cipher.card) {
      if (cipher.card.cardholderName) parts.push(cipher.card.cardholderName);
      if (cipher.card.brand) parts.push(cipher.card.brand);
    }

    if (cipher.identity) {
      if (cipher.identity.firstName) parts.push(cipher.identity.firstName);
      if (cipher.identity.lastName) parts.push(cipher.identity.lastName);
      if (cipher.identity.company) parts.push(cipher.identity.company);
      if (cipher.identity.email) parts.push(cipher.identity.email);
    }

    if (cipher.fields) {
      cipher.fields.forEach(field => {
        if (field.name) parts.push(field.name);
        if (field.value && field.type !== FieldType.Hidden) {
          parts.push(field.value);
        }
      });
    }

    return parts.join(' ');
  }

  filterByType(ciphers: CipherView[], type: CipherType): CipherView[] {
    return ciphers.filter(cipher => cipher.type === type);
  }

  filterByFolder(ciphers: CipherView[], folderId: string | null): CipherView[] {
    return ciphers.filter(cipher => cipher.folderId === folderId);
  }

  filterByFavorites(ciphers: CipherView[]): CipherView[] {
    return ciphers.filter(cipher => cipher.favorite);
  }

  filterByOrganization(ciphers: CipherView[], organizationId: string): CipherView[] {
    return ciphers.filter(cipher => cipher.organizationId === organizationId);
  }
}
```

## Error Handling

### Cipher-Specific Errors

```typescript
class CipherError extends Error {
  constructor(
    message: string,
    public code: string,
    public cipherId?: string
  ) {
    super(message);
    this.name = 'CipherError';
  }
}

async function handleCipherOperation<T>(
  operation: () => Promise<T>,
  cipherId?: string
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    if (error.status === 404) {
      throw new CipherError('Cipher not found', 'CIPHER_NOT_FOUND', cipherId);
    } else if (error.status === 403) {
      throw new CipherError('Access denied to cipher', 'CIPHER_ACCESS_DENIED', cipherId);
    } else if (error.status === 400) {
      throw new CipherError('Invalid cipher data', 'CIPHER_INVALID_DATA', cipherId);
    } else {
      throw new CipherError('Cipher operation failed', 'CIPHER_OPERATION_FAILED', cipherId);
    }
  }
}
```

## Performance Optimization

### Batch Operations

```typescript
class CipherBatchProcessor {
  private readonly BATCH_SIZE = 50;

  async processCiphersBatch<T>(
    ciphers: CipherResponse[],
    processor: (cipher: CipherResponse) => Promise<T>
  ): Promise<T[]> {
    const results: T[] = [];

    for (let i = 0; i < ciphers.length; i += this.BATCH_SIZE) {
      const batch = ciphers.slice(i, i + this.BATCH_SIZE);
      const batchResults = await Promise.all(
        batch.map(cipher => processor(cipher))
      );
      results.push(...batchResults);

      // Allow UI to update between batches
      await new Promise(resolve => setTimeout(resolve, 0));
    }

    return results;
  }

  async decryptCiphersBatch(ciphers: CipherResponse[]): Promise<CipherView[]> {
    return this.processCiphersBatch(ciphers, cipher =>
      decryptCipherFromStorage(cipher)
    );
  }
}
```

### Caching Strategy

```typescript
class CipherCacheService {
  private cache = new Map<string, CipherView>();
  private cacheExpiry = new Map<string, number>();
  private readonly CACHE_TTL = 5 * 60 * 1000; // 5 minutes

  getCachedCipher(id: string): CipherView | null {
    const expiry = this.cacheExpiry.get(id);
    if (expiry && Date.now() > expiry) {
      this.cache.delete(id);
      this.cacheExpiry.delete(id);
      return null;
    }
    return this.cache.get(id) || null;
  }

  setCachedCipher(cipher: CipherView): void {
    this.cache.set(cipher.id, cipher);
    this.cacheExpiry.set(cipher.id, Date.now() + this.CACHE_TTL);
  }

  invalidateCache(id?: string): void {
    if (id) {
      this.cache.delete(id);
      this.cacheExpiry.delete(id);
    } else {
      this.cache.clear();
      this.cacheExpiry.clear();
    }
  }
}
```
