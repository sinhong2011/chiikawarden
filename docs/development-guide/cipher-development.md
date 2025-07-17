# Bitwarden Cipher Development Guide

## Table of Contents
1. [Overview](#overview)
2. [Core Concepts](#core-concepts)
3. [Data Architecture](#data-architecture)
4. [Cipher Types](#cipher-types)
5. [Encryption & Decryption Flow](#encryption--decryption-flow)
6. [CipherService Deep Dive](#cipherservice-deep-dive)
7. [Working with Ciphers](#working-with-ciphers)
8. [Best Practices](#best-practices)
9. [Common Patterns](#common-patterns)
10. [Testing Strategies](#testing-strategies)

## Overview

In the Bitwarden ecosystem, a **cipher** is the fundamental data structure representing any encrypted vault item. Despite its name suggesting cryptographic algorithms, a "cipher" in Bitwarden context refers to any vault item that stores sensitive information in an encrypted format.

### Key Characteristics
- **Universal Container**: All vault items (logins, notes, cards, identities, SSH keys) are ciphers
- **Encrypted Storage**: Sensitive data is always encrypted at rest and in transit
- **Type-Specific Data**: Each cipher contains type-specific information based on its purpose
- **Metadata Management**: Includes permissions, organization data, and audit information

## Core Concepts

### Three-Layer Architecture

Bitwarden uses a three-layer data architecture for ciphers:

1. **Data Layer** (`CipherData`): Raw encrypted data from API responses
2. **Domain Layer** (`Cipher`): Business logic with encrypted strings (`EncString`)
3. **View Layer** (`CipherView`): Decrypted data for UI consumption

```typescript
// Data Layer - Raw from API
class CipherData {
  name: string;           // Encrypted string from server
  login?: LoginData;      // Encrypted login data
}

// Domain Layer - Business logic
class Cipher {
  name: EncString;        // Typed encrypted string
  login: Login;           // Domain login object
}

// View Layer - Decrypted for UI
class CipherView {
  name: string;           // Decrypted plain text
  login: LoginView;       // Decrypted login view
}
```

### Cipher Types

Bitwarden supports five cipher types:

```typescript
export const CipherType = {
  Login: 1,        // Username/password combinations
  SecureNote: 2,   // Encrypted text notes
  Card: 3,         // Credit card information
  Identity: 4,     // Personal identity data
  SshKey: 5,       // SSH key pairs
} as const;
```

## Data Architecture

### CipherData Structure
```typescript
export class CipherData {
  // Core Properties
  id: string;
  organizationId: string;
  folderId: string;
  type: CipherType;
  name: string;                    // Encrypted
  notes: string;                   // Encrypted

  // Permissions & Metadata
  edit: boolean;
  viewPassword: boolean;
  permissions: CipherPermissionsApi;
  favorite: boolean;
  revisionDate: string;
  creationDate: string;
  deletedDate: string | null;
  reprompt: CipherRepromptType;

  // Type-Specific Data (only one will be populated)
  login?: LoginData;
  secureNote?: SecureNoteData;
  card?: CardData;
  identity?: IdentityData;
  sshKey?: SshKeyData;

  // Additional Data
  fields?: FieldData[];            // Custom fields
  attachments?: AttachmentData[];  // File attachments
  passwordHistory?: PasswordHistoryData[];
  collectionIds?: string[];       // Organization collections
  key: string;                    // Individual cipher encryption key
}
```

### Domain Model Structure
```typescript
export class Cipher extends Domain {
  // Core Properties (encrypted)
  name: EncString;
  notes: EncString;
  key: EncString;

  // Type-Specific Domain Objects
  login: Login;
  identity: Identity;
  card: Card;
  secureNote: SecureNote;
  sshKey: SshKey;

  // Collections
  attachments: Attachment[];
  fields: Field[];
  passwordHistory: Password[];

  // Metadata (unencrypted)
  id: string;
  type: CipherType;
  favorite: boolean;
  // ... other metadata
}
```

## Cipher Types

### 1. Login Cipher
Stores website credentials and authentication data.

```typescript
// LoginData (encrypted strings from API)
class LoginData {
  username: string;
  password: string;
  passwordRevisionDate: string;
  totp: string;
  autofillOnPageLoad: boolean;
  uris: LoginUriData[];
  fido2Credentials?: Fido2CredentialData[];
}

// LoginView (decrypted for UI)
class LoginView {
  username: string;
  password: string;
  passwordRevisionDate?: Date;
  totp: string;
  uris: LoginUriView[];
  autofillOnPageLoad: boolean;
  fido2Credentials: Fido2CredentialView[];

  // Computed properties
  get uri(): string;              // First URI
  get maskedPassword(): string;   // "••••••••"
  get hasUris(): boolean;
}
```

### 2. Card Cipher
Stores credit card and payment information.

```typescript
class CardView {
  cardholderName: string;
  brand: string;
  number: string;
  expMonth: string;
  expYear: string;
  code: string;

  // Computed properties
  get maskedCode(): string;       // "•••"
  get maskedNumber(): string;     // "••••••••••••1234"
  get subTitle(): string;         // Brand and last 4 digits
}
```

### 3. Identity Cipher
Stores personal identity information.

```typescript
class IdentityView {
  title: string;
  firstName: string;
  middleName: string;
  lastName: string;
  address1: string;
  address2: string;
  address3: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
  company: string;
  email: string;
  phone: string;
  ssn: string;
  username: string;
  passportNumber: string;
  licenseNumber: string;

  // Computed properties
  get fullName(): string;
  get subTitle(): string;
}
```

### 4. SecureNote Cipher
Stores encrypted text notes.

```typescript
class SecureNoteView {
  type: SecureNoteType;  // Generic = 0
}
```

### 5. SSH Key Cipher
Stores SSH key pairs for server authentication.

```typescript
class SshKeyView {
  privateKey: string;
  publicKey: string;
  keyFingerprint: string;

  get maskedPrivateKey(): string;  // Masks middle lines
  get subTitle(): string;          // Key fingerprint
}
```

## Encryption & Decryption Flow

### Encryption Process
1. **User Input**: Plain text data from UI forms
2. **View to Domain**: Convert `CipherView` to `Cipher` with `EncString` objects
3. **Key Selection**: Choose appropriate encryption key (user key or org key)
4. **Encryption**: Encrypt sensitive fields using AES-256-GCM
5. **API Request**: Send encrypted `CipherData` to server

### Decryption Process
1. **API Response**: Receive encrypted `CipherData` from server
2. **Domain Creation**: Convert to `Cipher` domain object
3. **Key Retrieval**: Get appropriate decryption key
4. **Decryption**: Decrypt `EncString` fields to plain text
5. **View Creation**: Create `CipherView` for UI consumption

### Key Management
```typescript
// Individual cipher keys (when enabled)
if (cipher.key != null) {
  // Decrypt cipher key with user/org key
  const cipherKey = await decryptCipherKey(cipher.key, userKey);
  // Use cipher key for field encryption/decryption
  const decryptedData = await decrypt(cipher.data, cipherKey);
}
```

## CipherService Deep Dive

The `CipherService` is the central orchestrator for all cipher operations.

### Core Observables
```typescript
class CipherService {
  // Encrypted ciphers from storage
  ciphers$(userId: UserId): Observable<Record<CipherId, CipherData>>;

  // Decrypted ciphers for UI (null during decryption)
  cipherViews$(userId: UserId): Observable<CipherView[] | null>;

  // Ciphers that failed to decrypt
  failedToDecryptCiphers$(userId: UserId): Observable<CipherView[]>;

  // Local metadata (usage stats, etc.)
  localData$(userId: UserId): Observable<Record<CipherId, LocalData>>;
}
```

### Key Methods

#### CRUD Operations
```typescript
// Create
async encrypt(model: CipherView, userId: UserId): Promise<EncryptionContext>;
async createWithServer(context: EncryptionContext): Promise<Cipher>;

// Read
async get(id: string, userId: UserId): Promise<Cipher>;
async getAllDecrypted(userId: UserId): Promise<CipherView[]>;
async getAllDecryptedForUrl(url: string, userId: UserId): Promise<CipherView[]>;

// Update
async updateWithServer(context: EncryptionContext): Promise<Cipher>;
async upsert(cipher: CipherData | CipherData[]): Promise<Record<CipherId, CipherData>>;

// Delete
async deleteWithServer(id: string, userId: UserId): Promise<void>;
async delete(id: string | string[], userId: UserId): Promise<void>;
```

#### Bulk Operations
```typescript
// Decrypt multiple ciphers efficiently
async getAllDecrypted(userId: UserId): Promise<CipherView[]> {
  const ciphers = await this.getAll(userId);
  const keys = await this.keyService.cipherDecryptionKeys$(userId);

  // Group by organization for batch decryption
  const grouped = this.groupByOrganization(ciphers);

  // Decrypt in parallel by organization
  const decrypted = await Promise.all(
    Object.entries(grouped).map(([orgId, ciphers]) =>
      this.bulkEncryptService.decryptItems(ciphers, keys[orgId])
    )
  );

  return decrypted.flat().sort(this.getLocaleSortingFunction());
}
```

## Working with Ciphers

### Creating a New Cipher

```typescript
async function createLoginCipher(
  name: string,
  username: string,
  password: string,
  uri: string,
  userId: UserId
): Promise<Cipher> {
  // 1. Create view model
  const cipherView = new CipherView();
  cipherView.type = CipherType.Login;
  cipherView.name = name;
  cipherView.favorite = false;
  cipherView.reprompt = CipherRepromptType.None;

  // 2. Set login-specific data
  cipherView.login = new LoginView();
  cipherView.login.username = username;
  cipherView.login.password = password;
  cipherView.login.uris = [
    {
      uri: uri,
      match: UriMatchType.Domain
    }
  ];

  // 3. Encrypt and create on server
  const encryptionContext = await cipherService.encrypt(cipherView, userId);
  return await cipherService.createWithServer(encryptionContext);
}
```

### Updating an Existing Cipher

```typescript
async function updateCipherPassword(
  cipherId: string,
  newPassword: string,
  userId: UserId
): Promise<Cipher> {
  // 1. Get current cipher
  const cipher = await cipherService.get(cipherId, userId);
  const cipherView = await cipherService.decrypt(cipher, userId);

  // 2. Update password and add to history
  const oldPassword = cipherView.login.password;
  cipherView.login.password = newPassword;
  cipherView.login.passwordRevisionDate = new Date();

  // 3. Add to password history
  if (oldPassword && cipherView.passwordHistory) {
    cipherView.passwordHistory.unshift({
      password: oldPassword,
      lastUsedDate: new Date()
    });
  }

  // 4. Encrypt and update on server
  const encryptionContext = await cipherService.encrypt(cipherView, userId, null, null, cipher);
  return await cipherService.updateWithServer(encryptionContext);
}
```

### Working with Custom Fields

```typescript
// Add custom field to cipher
function addCustomField(cipherView: CipherView, name: string, value: string, type: FieldType): void {
  if (!cipherView.fields) {
    cipherView.fields = [];
  }

  const field = new FieldView();
  field.name = name;
  field.value = value;
  field.type = type;
  field.newField = true;

  cipherView.fields.push(field);
}

// Add linked field (auto-fills from cipher data)
function addLinkedField(cipherView: CipherView, linkedId: LinkedIdType): void {
  const field = new FieldView();
  field.name = `Linked ${linkedId}`;
  field.type = FieldType.Linked;
  field.linkedId = linkedId;
  field.newField = true;

  cipherView.fields = cipherView.fields || [];
  cipherView.fields.push(field);
}
```

### Handling Attachments

```typescript
async function addAttachmentToCipher(
  cipher: Cipher,
  filename: string,
  data: ArrayBuffer,
  userId: UserId
): Promise<Cipher> {
  return await cipherService.saveAttachmentWithServer(
    cipher,
    filename,
    data,
    userId,
    false // not admin
  );
}

async function downloadAttachment(
  cipher: Cipher,
  attachment: AttachmentView,
  userId: UserId
): Promise<ArrayBuffer> {
  // Get decryption key for attachment
  const key = attachment.key || await cipherService.getKeyForCipherKeyDecryption(cipher, userId);

  // Download and decrypt
  const response = await apiService.getCipherAttachment(cipher.id, attachment.id);
  const encryptedData = await response.arrayBuffer();

  return await encryptService.decryptFileData(encryptedData, key);
}
```

## Best Practices

### 1. Always Use Observables for UI
```typescript
// ✅ Good - Reactive updates
@Component({})
export class VaultComponent {
  ciphers$ = this.cipherService.cipherViews$(this.userId);

  constructor(private cipherService: CipherService) {}
}

// ❌ Bad - Manual updates required
@Component({})
export class VaultComponent {
  ciphers: CipherView[] = [];

  async loadCiphers() {
    this.ciphers = await this.cipherService.getAllDecrypted(this.userId);
  }
}
```

### 2. Handle Decryption Failures Gracefully
```typescript
@Component({})
export class VaultComponent {
  ciphers$ = this.cipherService.cipherViews$(this.userId);
  failedCiphers$ = this.cipherService.failedToDecryptCiphers$(this.userId);

  // Show error state for failed decryptions
  showDecryptionErrors$ = this.failedCiphers$.pipe(
    map(failed => failed && failed.length > 0)
  );
}
```

### 3. Use Proper Error Handling
```typescript
async function safeCipherOperation<T>(
  operation: () => Promise<T>,
  fallback: T
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    console.error('Cipher operation failed:', error);
    // Log to error service
    errorService.logError(error);
    return fallback;
  }
}
```

### 4. Optimize for Performance
```typescript
// Use bulk operations when possible
async function updateMultipleCiphers(
  cipherViews: CipherView[],
  userId: UserId
): Promise<void> {
  // Encrypt all ciphers
  const encryptionContexts = await Promise.all(
    cipherViews.map(view => cipherService.encrypt(view, userId))
  );

  // Update all on server
  await Promise.all(
    encryptionContexts.map(context => cipherService.updateWithServer(context))
  );
}
```

## Common Patterns

### 1. Cipher Type Guards
```typescript
function isLoginCipher(cipher: CipherView): cipher is CipherView & { login: LoginView } {
  return cipher.type === CipherType.Login && cipher.login != null;
}

function isCardCipher(cipher: CipherView): cipher is CipherView & { card: CardView } {
  return cipher.type === CipherType.Card && cipher.card != null;
}

// Usage
if (isLoginCipher(cipher)) {
  // TypeScript knows cipher.login is available
  console.log(cipher.login.username);
}
```

### 2. Cipher Filtering and Searching
```typescript
// Filter by type
const loginCiphers = ciphers.filter(c => c.type === CipherType.Login);

// Filter by organization
const orgCiphers = ciphers.filter(c => c.organizationId === orgId);

// Filter by collection
const collectionCiphers = ciphers.filter(c =>
  c.collectionIds?.includes(collectionId)
);

// Search by name/username
const searchResults = ciphers.filter(c =>
  c.name.toLowerCase().includes(query.toLowerCase()) ||
  (isLoginCipher(c) && c.login.username?.toLowerCase().includes(query.toLowerCase()))
);
```

### 3. URI Matching for Autofill
```typescript
function findMatchingCiphers(
  url: string,
  ciphers: CipherView[]
): CipherView[] {
  return ciphers
    .filter(isLoginCipher)
    .filter(cipher =>
      cipher.login.uris?.some(uri =>
        matchesUri(url, uri.uri, uri.match)
      )
    )
    .sort((a, b) => {
      // Sort by last used, then by name
      const aLastUsed = a.localData?.lastUsedDate || new Date(0);
      const bLastUsed = b.localData?.lastUsedDate || new Date(0);

      if (aLastUsed !== bLastUsed) {
        return bLastUsed.getTime() - aLastUsed.getTime();
      }

      return a.name.localeCompare(b.name);
    });
}
```

## Testing Strategies

### 1. Unit Testing Cipher Models
```typescript
describe('CipherView', () => {
  it('should create login cipher correctly', () => {
    const cipher = new CipherView();
    cipher.type = CipherType.Login;
    cipher.name = 'Test Login';
    cipher.login = new LoginView();
    cipher.login.username = 'testuser';
    cipher.login.password = 'testpass';

    expect(cipher.type).toBe(CipherType.Login);
    expect(cipher.login.username).toBe('testuser');
    expect(cipher.login.maskedPassword).toBe('••••••••');
  });

  it('should handle empty cipher gracefully', () => {
    const cipher = new CipherView();
    expect(cipher.name).toBeNull();
    expect(cipher.login).toBeDefined();
    expect(cipher.login.username).toBeNull();
  });
});
```

### 2. Integration Testing with CipherService
```typescript
describe('CipherService Integration', () => {
  let cipherService: CipherService;
  let mockApiService: jasmine.SpyObj<ApiService>;
  let mockEncryptService: jasmine.SpyObj<EncryptService>;

  beforeEach(() => {
    // Setup mocks and service
  });

  it('should create and encrypt cipher', async () => {
    const cipherView = createTestLoginCipher();
    const encryptionContext = await cipherService.encrypt(cipherView, userId);

    expect(encryptionContext.cipher.name).toBeInstanceOf(EncString);
    expect(encryptionContext.cipher.login.username).toBeInstanceOf(EncString);
  });

  it('should decrypt cipher correctly', async () => {
    const encryptedCipher = createTestEncryptedCipher();
    const decryptedView = await cipherService.decrypt(encryptedCipher, userId);

    expect(decryptedView.name).toBe('Test Login');
    expect(decryptedView.login.username).toBe('testuser');
  });
});
```

### 3. E2E Testing Cipher Operations
```typescript
describe('Cipher E2E Operations', () => {
  it('should create, update, and delete cipher', async () => {
    // Create
    const cipherView = createTestLoginCipher();
    const created = await cipherService.createWithServer(
      await cipherService.encrypt(cipherView, userId)
    );
    expect(created.id).toBeDefined();

    // Update
    const decrypted = await cipherService.decrypt(created, userId);
    decrypted.name = 'Updated Name';
    const updated = await cipherService.updateWithServer(
      await cipherService.encrypt(decrypted, userId)
    );

    // Verify update
    const retrieved = await cipherService.get(updated.id, userId);
    const retrievedView = await cipherService.decrypt(retrieved, userId);
    expect(retrievedView.name).toBe('Updated Name');

    // Delete
    await cipherService.deleteWithServer(updated.id, userId);

    // Verify deletion
    const deleted = await cipherService.get(updated.id, userId);
    expect(deleted).toBeNull();
  });
});
```

---

This guide provides a comprehensive foundation for understanding and working with ciphers in the Bitwarden codebase. The three-layer architecture, type-specific implementations, and service patterns form the core of how Bitwarden securely manages user data across all platforms.
