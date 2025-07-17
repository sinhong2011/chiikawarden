# Account Management API Documentation - Tauri Best Practices

## Overview

The Account Management API handles user profile information, account settings, preferences, and account-level operations. **All account operations must be implemented in the Rust backend** for security and proper data management.

## Security Architecture

### ✅ Correct Implementation Pattern
```
SolidJS Frontend → invoke('account_command') → Rust Backend → Bitwarden API
```

### ❌ Never Do This
```typescript
// WRONG: Direct account API calls from frontend
const profile = await fetch('/accounts/profile', { headers: { Authorization: token } });
```

## Account Operations

### 1. Get User Profile

**Endpoint:** `GET /accounts/profile`
**Authentication:** Bearer token required (handled in Rust)
**Purpose:** Retrieve and cache user profile information

#### Tauri Command Implementation

```rust
// src-tauri/src/account/commands.rs
use tauri::State;
use crate::database::Database;
use crate::crypto::CryptoService;

#[tauri::command]
pub async fn get_user_profile(
    api_client: State<'_, ApiClientState>,
    database: State<'_, Database>
) -> Result<UserProfile, String> {
    // Try to get from local cache first
    if let Ok(cached_profile) = database.get_cached_profile().await {
        if !cached_profile.is_expired() {
            return Ok(cached_profile);
        }
    }

    // Fetch from API
    let profile: UserProfileResponse = api_client
        .make_authenticated_request(
            reqwest::Method::GET,
            "/accounts/profile",
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    // Cache profile for offline access
    database.cache_profile(&profile).await
        .map_err(|e| e.to_string())?;

    Ok(profile.into())
}

#[tauri::command]
pub async fn update_user_profile(
    profile_update: ProfileUpdateRequest,
    api_client: State<'_, ApiClientState>,
    database: State<'_, Database>
) -> Result<UserProfile, String> {
    // Validate input
    validate_profile_update(&profile_update)?;

    // Update via API
    let updated_profile: UserProfileResponse = api_client
        .make_authenticated_request(
            reqwest::Method::PUT,
            "/accounts/profile",
            Some(profile_update)
        )
        .await
        .map_err(|e| e.to_string())?;

    // Update local cache
    database.cache_profile(&updated_profile).await
        .map_err(|e| e.to_string())?;

    Ok(updated_profile.into())
}
```

#### Frontend Usage

```typescript
// src/services/account.service.ts
import { invoke } from '@tauri-apps/api/tauri';

export class AccountService {
    async getUserProfile(): Promise<UserProfile> {
        return await invoke('get_user_profile');
    }

    async updateProfile(updates: ProfileUpdateRequest): Promise<UserProfile> {
        return await invoke('update_user_profile', { profileUpdate: updates });
    }

    async changePassword(currentPassword: string, newPassword: string): Promise<void> {
        return await invoke('change_master_password', {
            currentPassword,
            newPassword
        });
    }
}
```

#### Frontend Profile Component

```typescript
// src/components/UserProfile.tsx
import { createSignal, createResource, Show } from 'solid-js';
import { invoke } from '@tauri-apps/api/tauri';

export function UserProfile() {
    const [isEditing, setIsEditing] = createSignal(false);
    const [profileForm, setProfileForm] = createSignal({
        name: '',
        masterPasswordHint: '',
        culture: 'en-US'
    });

    // Reactive resource for user profile
    const [profile, { refetch }] = createResource(
        () => invoke('get_user_profile')
    );

    const handleSaveProfile = async () => {
        try {
            await invoke('update_user_profile', {
                profileUpdate: profileForm()
            });

            setIsEditing(false);
            refetch(); // Refresh profile data
            showToast('Profile updated successfully');
        } catch (error) {
            showToast(`Failed to update profile: ${error}`);
        }
    };

    return (
        <div class="user-profile">
            <Show when={profile.loading}>
                <div class="loading">Loading profile...</div>
            </Show>

            <Show when={profile.error}>
                <div class="error">Error: {profile.error}</div>
            </Show>

            <Show when={profile()}>
                <div class="profile-content">
                    <div class="profile-header">
                        <h2>Account Settings</h2>
                        <button
                            onClick={() => setIsEditing(!isEditing())}
                            class="edit-button"
                        >
                            {isEditing() ? 'Cancel' : 'Edit'}
                        </button>
                    </div>

                    <div class="profile-fields">
                        <div class="field">
                            <label>Email</label>
                            <input
                                type="email"
                                value={profile()?.email || ''}
                                disabled
                            />
                            <small>Email cannot be changed</small>
                        </div>

                        <div class="field">
                            <label>Name</label>
                            <input
                                type="text"
                                value={isEditing() ? profileForm().name : profile()?.name || ''}
                                disabled={!isEditing()}
                                onInput={(e) => setProfileForm(prev => ({
                                    ...prev,
                                    name: e.currentTarget.value
                                }))}
                            />
                        </div>

                        <div class="field">
                            <label>Master Password Hint</label>
                            <input
                                type="text"
                                value={isEditing() ? profileForm().masterPasswordHint : profile()?.masterPasswordHint || ''}
                                disabled={!isEditing()}
                                onInput={(e) => setProfileForm(prev => ({
                                    ...prev,
                                    masterPasswordHint: e.currentTarget.value
                                }))}
                            />
                        </div>

                        <div class="field">
                            <label>Premium Status</label>
                            <div class="premium-status">
                                {profile()?.premium ? '✅ Premium' : '❌ Free'}
                                {profile()?.premiumFromOrganization && ' (via Organization)'}
                            </div>
                        </div>

                        <div class="field">
                            <label>Two-Factor Authentication</label>
                            <div class="2fa-status">
                                {profile()?.twoFactorEnabled ? '✅ Enabled' : '❌ Disabled'}
                                <button class="setup-2fa-button">
                                    {profile()?.twoFactorEnabled ? 'Manage' : 'Setup'} 2FA
                                </button>
                            </div>
                        </div>
                    </div>

                    <Show when={isEditing()}>
                        <div class="profile-actions">
                            <button
                                onClick={handleSaveProfile}
                                class="save-button"
                            >
                                Save Changes
                            </button>
                        </div>
                    </Show>
                </div>
            </Show>
        </div>
    );
}
```

### 2. Password Management

#### Change Master Password

```rust
#[tauri::command]
pub async fn change_master_password(
    current_password: String,
    new_password: String,
    api_client: State<'_, ApiClientState>,
    crypto_service: State<'_, CryptoService>
) -> Result<(), String> {
    // Verify current password
    let current_hash = crypto_service
        .hash_password(&current_password)
        .await
        .map_err(|e| e.to_string())?;

    // Generate new password hash
    let new_hash = crypto_service
        .hash_password(&new_password)
        .await
        .map_err(|e| e.to_string())?;

    // Re-encrypt user key with new password
    let re_encrypted_key = crypto_service
        .re_encrypt_user_key(&current_password, &new_password)
        .await
        .map_err(|e| e.to_string())?;

    let request = ChangePasswordRequest {
        master_password_hash: current_hash,
        new_master_password_hash: new_hash,
        key: re_encrypted_key,
    };

    api_client
        .make_authenticated_request(
            reqwest::Method::POST,
            "/accounts/password",
            Some(request)
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}
```

### 3. Account Deletion

```rust
#[tauri::command]
pub async fn delete_account(
    master_password: String,
    api_client: State<'_, ApiClientState>,
    database: State<'_, Database>
) -> Result<(), String> {
    // Hash password for verification
    let password_hash = crypto_service
        .hash_password(&master_password)
        .await
        .map_err(|e| e.to_string())?;

    let request = DeleteAccountRequest {
        master_password_hash: password_hash,
    };

    // Delete account via API
    api_client
        .make_authenticated_request(
            reqwest::Method::DELETE,
            "/accounts",
            Some(request)
        )
        .await
        .map_err(|e| e.to_string())?;

    // Clear all local data
    database.clear_all_data().await
        .map_err(|e| e.to_string())?;

    // Clear stored tokens
    clear_all_stored_tokens().await?;

    Ok(())
}
```

This implementation ensures all account management operations are secure and properly handled through the Rust backend.
      "selfHost": false,
      "seats": 50,
      "maxCollections": 100,
      "maxStorageGb": 1,
      "key": "encrypted_org_key",
      "status": 2,
      "type": 2,
      "enabled": true,
      "ssoBound": false,
      "identifier": "acme-corp",
      "permissions": {
        "accessEventLogs": false,
        "accessImportExport": false,
        "accessReports": false,
        "createNewCollections": true,
        "editAnyCollection": false,
        "deleteAnyCollection": false,
        "editAssignedCollections": true,
        "deleteAssignedCollections": false,
        "manageGroups": false,
        "managePolicies": false,
        "manageSso": false,
        "manageUsers": false,
        "manageResetPassword": false,
        "manageScim": false
      },
      "resetPasswordEnrolled": true,
      "userId": "12345678-1234-1234-1234-123456789012",
      "hasPublicAndPrivateKeys": true,
      "providerId": null,
      "providerName": null,
      "familySponsorshipFriendlyName": null,
      "familySponsorshipAvailable": false,
      "planProductType": 3,
      "keyConnectorEnabled": false,
      "keyConnectorUrl": null,
      "familySponsorshipLastSyncDate": null,
      "familySponsorshipValidUntil": null,
      "familySponsorshipToDelete": null,
      "accessSecretsManager": false,
      "limitCollectionCreationDeletion": false,
      "allowAdminAccessToAllCollectionItems": true,
      "flexibleCollections": true,
      "object": "profileOrganization"
    }
  ],
  "providers": [],
  "providerOrganizations": [],
  "object": "profile"
}
```

#### Organization Status Types
- `0` - Invited
- `1` - Accepted
- `2` - Confirmed

#### Organization User Types
- `0` - Owner
- `1` - Admin
- `2` - User
- `3` - Manager
- `4` - Custom

#### Implementation Example

```typescript
interface ProfileResponse {
  id: string;
  name: string;
  email: string;
  emailVerified: boolean;
  premium: boolean;
  premiumFromOrganization: boolean;
  masterPasswordHint?: string;
  culture: string;
  twoFactorEnabled: boolean;
  key: string;
  privateKey: string;
  securityStamp: string;
  forcePasswordReset: boolean;
  usesKeyConnector: boolean;
  organizations: ProfileOrganization[];
  providers: ProfileProvider[];
  providerOrganizations: ProfileProviderOrganization[];
  object: 'profile';
}

// Rust Implementation Example
async fn get_user_profile(access_token: &str) -> Result<ProfileResponse, reqwest::Error> {
    let client = reqwest::Client::new();

    let response = client
        .get("https://api.bitwarden.com/accounts/profile")
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    response.json::<ProfileResponse>().await
}
```

---

### 2. Update User Profile

**Endpoint:** `PUT /accounts/profile`
**Authentication:** Bearer token required
**Purpose:** Update user profile information

#### Request

```json
{
  "name": "John Smith",
  "masterPasswordHint": "Updated hint",
  "culture": "en-GB"
}
```

#### Response

```json
{
  "id": "12345678-1234-1234-1234-123456789012",
  "name": "John Smith",
  "email": "john.doe@example.com",
  "emailVerified": true,
  "premium": true,
  "premiumFromOrganization": false,
  "masterPasswordHint": "Updated hint",
  "culture": "en-GB",
  "twoFactorEnabled": true,
  "key": "encrypted_user_key",
  "privateKey": "encrypted_private_key",
  "securityStamp": "security_stamp_value",
  "forcePasswordReset": false,
  "usesKeyConnector": false,
  "organizations": [],
  "providers": [],
  "providerOrganizations": [],
  "object": "profile"
}
```

#### Implementation Example

```typescript
interface UpdateProfileRequest {
  name?: string;
  masterPasswordHint?: string;
  culture?: string;
}

// Rust Implementation Example
async fn update_profile(
    updates: UpdateProfileRequest,
    access_token: &str
) -> Result<ProfileResponse, reqwest::Error> {
    let client = reqwest::Client::new();

    let response = client
        .put("https://api.bitwarden.com/accounts/profile")
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .json(&updates)
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    response.json::<ProfileResponse>().await
}
```

---

### 3. Get Account Revision Date

**Endpoint:** `GET /accounts/revision-date`
**Authentication:** Bearer token required
**Purpose:** Get the last revision timestamp for the account (used for sync optimization)

#### Request

```http
GET /accounts/revision-date
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```json
1640995200000
```

*Returns Unix timestamp in milliseconds*

#### Implementation Example

```rust
// src-tauri/src/account/revision.rs
async fn get_account_revision_date(access_token: &str) -> Result<u64, reqwest::Error> {
    let client = reqwest::Client::new();

    let response = client
        .get("https://api.bitwarden.com/accounts/revision-date")
        .header("Authorization", format!("Bearer {}", access_token))
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    response.json::<u64>().await
}

// Usage for sync optimization
async function shouldSync(): Promise<boolean> {
  const serverRevisionDate = await getAccountRevisionDate();
  const localRevisionDate = await getLocalRevisionDate();

  return serverRevisionDate > localRevisionDate;
}
```

---

### 4. Change Password

**Endpoint:** `POST /accounts/password`
**Authentication:** Bearer token required
**Purpose:** Change user's master password

#### Request

```json
{
  "masterPasswordHash": "current_password_hash",
  "newMasterPasswordHash": "new_password_hash",
  "key": "re_encrypted_user_key"
}
```

#### Response

```
200 OK
```

#### Implementation Example

```typescript
interface ChangePasswordRequest {
  masterPasswordHash: string;
  newMasterPasswordHash: string;
  key: string;
}

async function changePassword(
  currentPassword: string,
  newPassword: string,
  email: string,
  kdfSettings: KdfSettings
): Promise<void> {
  // 1. Derive current master key and hash
  const currentMasterKey = await deriveMasterKey(currentPassword, email, kdfSettings);
  const currentPasswordHash = await hashPassword(currentPassword, currentMasterKey);

  // 2. Derive new master key and hash
  const newMasterKey = await deriveMasterKey(newPassword, email, kdfSettings);
  const newPasswordHash = await hashPassword(newPassword, newMasterKey);

  // 3. Re-encrypt user key with new master key
  const currentUserKey = await decryptUserKey(currentMasterKey);
  const reEncryptedUserKey = await encryptUserKey(currentUserKey, newMasterKey);

  const request: ChangePasswordRequest = {
    masterPasswordHash: currentPasswordHash,
    newMasterPasswordHash: newPasswordHash,
    key: reEncryptedUserKey
  };

  // Rust implementation
  let client = reqwest::Client::new();

  let response = client
      .post("https://api.bitwarden.com/accounts/password")
      .header("Authorization", format!("Bearer {}", access_token))
      .header("Content-Type", "application/json")
      .json(&request)
      .send()
      .await?;

  if !response.status().is_success() {
      return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
  }
}
```

---

### 5. Delete Account

**Endpoint:** `DELETE /accounts`
**Authentication:** Bearer token required
**Purpose:** Permanently delete user account

#### Request

```json
{
  "masterPasswordHash": "password_hash_for_verification"
}
```

#### Response

```
200 OK
```

#### Implementation Example

```typescript
async function deleteAccount(password: string, email: string, kdfSettings: KdfSettings): Promise<void> {
  const masterKey = await deriveMasterKey(password, email, kdfSettings);
  const passwordHash = await hashPassword(password, masterKey);

  // Rust implementation
  let client = reqwest::Client::new();

  let request_body = serde_json::json!({
      "masterPasswordHash": password_hash
  });

  let response = client
      .delete("https://api.bitwarden.com/accounts")
      .header("Authorization", format!("Bearer {}", access_token))
      .header("Content-Type", "application/json")
      .json(&request_body)
      .send()
      .await?;

  if !response.status().is_success() {
      return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
  }
}
```

---

### 6. Verify Email

**Endpoint:** `POST /accounts/verify-email`
**Authentication:** Bearer token required
**Purpose:** Send email verification

#### Request

```
POST /accounts/verify-email
```

*No request body required*

#### Response

```
200 OK
```

#### Implementation Example

```rust
// src-tauri/src/account/email_verification.rs
async fn send_email_verification(access_token: &str) -> Result<(), reqwest::Error> {
    let client = reqwest::Client::new();

    let response = client
        .post("https://api.bitwarden.com/accounts/verify-email")
        .header("Authorization", format!("Bearer {}", access_token))
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    Ok(())
}
```

---

### 7. Verify Email Token

**Endpoint:** `POST /accounts/verify-email-token`
**Authentication:** Bearer token required
**Purpose:** Verify email with token from email

#### Request

```json
{
  "userId": "12345678-1234-1234-1234-123456789012",
  "token": "email_verification_token"
}
```

#### Response

```
200 OK
```

#### Implementation Example

```rust
// src-tauri/src/account/email_verification.rs
use serde::Serialize;

#[derive(Serialize)]
struct VerifyEmailTokenRequest {
    #[serde(rename = "userId")]
    user_id: String,
    token: String,
}

async fn verify_email_token(
    user_id: String,
    token: String,
    access_token: &str
) -> Result<(), reqwest::Error> {
    let client = reqwest::Client::new();

    let request_body = VerifyEmailTokenRequest { user_id, token };

    let response = client
        .post("https://api.bitwarden.com/accounts/verify-email-token")
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .json(&request_body)
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    Ok(())
}
```

## Error Handling

### Common Error Responses

- `400 Bad Request` - Invalid request data or validation errors
- `401 Unauthorized` - Invalid or expired access token
- `403 Forbidden` - Insufficient permissions
- `404 Not Found` - Resource not found
- `429 Too Many Requests` - Rate limiting applied

### Implementation Example

```typescript
class AccountError extends Error {
  constructor(message: string, public status?: number) {
    super(message);
    this.name = 'AccountError';
  }
}

async function handleAccountRequest<T>(request: Promise<Response>): Promise<T> {
  try {
    const response = await request;

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));

      switch (response.status) {
        case 400:
          throw new AccountError('Invalid request data', 400);
        case 401:
          throw new AccountError('Authentication required', 401);
        case 403:
          throw new AccountError('Access denied', 403);
        case 404:
          throw new AccountError('Resource not found', 404);
        case 429:
          throw new AccountError('Too many requests', 429);
        default:
          throw new AccountError(errorData.message || 'Request failed', response.status);
      }
    }

    return response.json();
  } catch (error) {
    if (error instanceof AccountError) {
      throw error;
    }
    throw new AccountError('Network error occurred');
  }
}
```

## Security Considerations

### Password Verification
Always verify the current password before making sensitive changes:

```typescript
async function verifyCurrentPassword(password: string): Promise<boolean> {
  try {
    // Attempt to derive keys with current password
    const masterKey = await deriveMasterKey(password, userEmail, kdfSettings);
    const userKey = await decryptUserKey(masterKey);
    return userKey !== null;
  } catch {
    return false;
  }
}
```

### Data Encryption
When updating profile data that affects encryption:

1. Verify current password
2. Re-encrypt all user data with new keys
3. Update server with new encrypted data
4. Clear old keys from memory

### Session Management
- Refresh tokens before making critical account changes
- Clear all sessions after password changes
- Implement proper logout on account deletion
