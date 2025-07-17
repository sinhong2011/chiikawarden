# Authentication API Documentation - Tauri Best Practices

## Overview

The Authentication API handles user login, logout, password management, and SSO integration. **All API calls must be implemented in the Rust backend** for security and proper token management.

## Security Architecture

### ✅ Correct Implementation Pattern
```
SolidJS Frontend → invoke('auth_command') → Rust Backend → Bitwarden API
```

### ❌ Never Do This
```typescript
// WRONG: Direct API calls from frontend expose tokens
const response = await fetch('https://api.bitwarden.com/accounts/prelogin');
```

## Authentication Flow

### 1. **Prelogin - Get KDF Settings**

**Endpoint:** `POST /accounts/prelogin`
**Authentication:** None required
**Purpose:** Retrieve user's Key Derivation Function (KDF) settings before authentication

#### Tauri Command Implementation

```rust
// src-tauri/src/auth/commands.rs
#[tauri::command]
pub async fn auth_prelogin(
    email: String,
    api_client: State<'_, ApiClientState>
) -> Result<PreloginResponse, String> {
    let request = PreloginRequest { email };

    api_client
        .make_request(
            reqwest::Method::POST,
            "/accounts/prelogin",
            Some(request),
            false // No auth required
        )
        .await
        .map_err(|e| e.to_string())
}
```

#### Frontend Usage

```typescript
// src/services/auth.service.ts
import { invoke } from '@tauri-apps/api/tauri';

export class AuthService {
    async getKdfSettings(email: string): Promise<PreloginResponse> {
        return await invoke('auth_prelogin', { email });
    }
}
```

#### Request/Response Types

```typescript
interface PreloginRequest {
    email: string;
}

interface PreloginResponse {
    kdf: number;           // 0 = PBKDF2, 1 = Argon2id
    kdfIterations: number;
    kdfMemory?: number;    // For Argon2id only
    kdfParallelism?: number; // For Argon2id only
}
```

---

### 2. User Authentication - Login

**Endpoint:** `POST /identity/connect/token`
**Authentication:** None required
**Purpose:** Authenticate user and receive access tokens

#### Tauri Command Implementation

```rust
#[tauri::command]
pub async fn auth_login(
    email: String,
    master_password_hash: String,
    two_factor_token: Option<String>,
    two_factor_provider: Option<u8>,
    api_client: State<'_, ApiClientState>
) -> Result<AuthResponse, String> {
    let mut form_data = vec![
        ("grant_type", "password".to_string()),
        ("username", email),
        ("password", master_password_hash),
        ("scope", "api offline_access".to_string()),
        ("client_id", "desktop".to_string()),
        ("deviceType", "6".to_string()), // Desktop
        ("deviceIdentifier", get_device_identifier()?),
        ("deviceName", get_device_name()?),
    ];

    // Add 2FA if provided
    if let Some(token) = two_factor_token {
        form_data.push(("twoFactorToken", token));
        form_data.push(("twoFactorProvider", two_factor_provider.unwrap_or(0).to_string()));
        form_data.push(("twoFactorRemember", "1".to_string()));
    }

    let response: AuthResponse = api_client
        .make_form_request(
            reqwest::Method::POST,
            "/identity/connect/token",
            form_data
        )
        .await
        .map_err(|e| e.to_string())?;

    // Store tokens securely in system keychain
    store_access_token(&response.access_token).await?;
    if let Some(refresh_token) = &response.refresh_token {
        store_refresh_token(refresh_token).await?;
    }

    // Update API client with new token
    api_client.set_access_token(response.access_token.clone()).await;

    Ok(response)
}

// Helper function for device identification
fn get_device_identifier() -> Result<String, String> {
    // Generate or retrieve persistent device ID
    use uuid::Uuid;
    let device_id = Uuid::new_v4().to_string();
    Ok(device_id)
}

fn get_device_name() -> Result<String, String> {
    use hostname::get;
    let hostname = get()
        .map_err(|e| format!("Failed to get hostname: {}", e))?
        .to_string_lossy()
        .to_string();
    Ok(format!("Bitwarden Desktop - {}", hostname))
}
```

#### Frontend Usage

```typescript
export class AuthService {
    async login(
        email: string,
        masterPasswordHash: string,
        twoFactorToken?: string,
        twoFactorProvider?: number
    ): Promise<AuthResponse> {
        return await invoke('auth_login', {
            email,
            masterPasswordHash,
            twoFactorToken,
            twoFactorProvider
        });
    }
}
```

#### Complete Login Flow Example

```typescript
// src/components/LoginForm.tsx
import { createSignal } from 'solid-js';
import { invoke } from '@tauri-apps/api/tauri';

export function LoginForm() {
    const [email, setEmail] = createSignal('');
    const [password, setPassword] = createSignal('');
    const [isLoading, setIsLoading] = createSignal(false);
    const [error, setError] = createSignal('');

    const handleLogin = async () => {
        setIsLoading(true);
        setError('');

        try {
            // Step 1: Get KDF settings
            const kdfSettings = await invoke('auth_prelogin', {
                email: email()
            });

            // Step 2: Hash password (done in Rust for security)
            const passwordHash = await invoke('crypto_hash_password', {
                password: password(),
                salt: email(),
                kdf: kdfSettings.kdf,
                iterations: kdfSettings.kdfIterations,
                memory: kdfSettings.kdfMemory,
                parallelism: kdfSettings.kdfParallelism
            });

            // Step 3: Authenticate
            const authResult = await invoke('auth_login', {
                email: email(),
                masterPasswordHash: passwordHash
            });

            // Step 4: Handle successful login
            console.log('Login successful:', authResult);
            // Navigate to vault or handle 2FA if required

        } catch (err) {
            setError(err as string);
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <form onSubmit={(e) => { e.preventDefault(); handleLogin(); }}>
            <input
                type="email"
                value={email()}
                onInput={(e) => setEmail(e.currentTarget.value)}
                placeholder="Email"
                required
            />
            <input
                type="password"
                value={password()}
                onInput={(e) => setPassword(e.currentTarget.value)}
                placeholder="Master Password"
                required
            />
            <button type="submit" disabled={isLoading()}>
                {isLoading() ? 'Logging in...' : 'Login'}
            </button>
            {error() && <div class="error">{error()}</div>}
        </form>
    );
}
redirect_uri=bitwarden://sso-callback&
deviceType=8&
deviceIdentifier=unique_device_id&
deviceName=My Desktop
```

#### API Key Authentication Request

```
grant_type=client_credentials&
scope=api&
client_id=organization.client_id&
client_secret=client_secret
```

#### Successful Response

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 3600,
  "token_type": "Bearer",
  "refresh_token": "refresh_token_string",
  "scope": "api offline_access",
  "Kdf": 0,
  "KdfIterations": 100000,
  "KdfMemory": null,
  "KdfParallelism": null,
  "ResetMasterPassword": false,
  "PrivateKey": "encrypted_private_key",
  "Key": "encrypted_user_key",
  "TwoFactorToken": null,
  "MasterPasswordPolicy": null
}
```

#### Two-Factor Required Response

```json
{
  "error": "invalid_grant",
  "error_description": "Two factor required.",
  "TwoFactorProviders": [0, 1, 3],
  "TwoFactorProviders2": {
    "0": null,
    "1": {
      "Email": "u***@example.com"
    },
    "3": null
  }
}
```

#### Two-Factor Provider Types
- `0` - Authenticator (TOTP)
- `1` - Email
- `2` - Duo (deprecated)
- `3` - YubiKey
- `4` - U2F (deprecated)
- `5` - Remember (device)
- `6` - Duo Organization
- `7` - WebAuthn

#### Device Types
- `0` - Android
- `1` - iOS
- `2` - Chrome Extension
- `3` - Firefox Extension
- `4` - Opera Extension
- `5` - Edge Extension
- `6` - Windows Desktop
- `7` - macOS Desktop
- `8` - Linux Desktop
- `9` - Chrome Browser
- `10` - Firefox Browser
- `11` - Opera Browser
- `12` - Edge Browser
- `13` - Safari Browser
- `14` - Vivaldi Browser
- `15` - Unknown Browser

#### Implementation Example

```typescript
async function authenticateWithPassword(
  email: string,
  hashedPassword: string,
  deviceInfo: DeviceInfo,
  twoFactor?: TwoFactorInfo
): Promise<TokenResponse> {
  const params = new URLSearchParams({
    grant_type: 'password',
    username: email,
    password: hashedPassword,
    scope: 'api offline_access',
    client_id: 'desktop',
    deviceType: deviceInfo.type.toString(),
    deviceIdentifier: deviceInfo.identifier,
    deviceName: deviceInfo.name
  });

  if (twoFactor) {
    params.append('twoFactorToken', twoFactor.token);
    params.append('twoFactorProvider', twoFactor.provider.toString());
    if (twoFactor.remember) {
      params.append('twoFactorRemember', '1');
    }
  }

  const response = await fetch('/identity/connect/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString()
  });

  const data = await response.json();

  if (!response.ok) {
    if (data.error === 'invalid_grant' && data.TwoFactorProviders) {
      throw new TwoFactorRequiredError(data.TwoFactorProviders, data.TwoFactorProviders2);
    }
    throw new AuthenticationError(data.error_description || 'Authentication failed');
  }

  return data;
}
```

#### Error Responses

- `400 Bad Request` - Invalid credentials or malformed request
- `429 Too Many Requests` - Rate limiting applied
- `500 Internal Server Error` - Server error

---

### 3. Password Hint

**Endpoint:** `POST /accounts/password-hint`
**Authentication:** None required
**Purpose:** Send password hint to user's email address

#### Request

```json
{
  "email": "user@example.com"
}
```

#### Response

```
200 OK
```
*No response body - hint sent via email*

#### Implementation Example

```typescript
async function sendPasswordHint(email: string): Promise<void> {
  const response = await fetch('/accounts/password-hint', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email })
  });

  if (!response.ok) {
    throw new Error('Failed to send password hint');
  }
}
```

#### Error Responses

- `400 Bad Request` - Invalid email format
- `404 Not Found` - Email not found
- `429 Too Many Requests` - Rate limiting applied

---

### 4. Token Refresh

**Endpoint:** `POST /identity/connect/token`
**Authentication:** None required (uses refresh token)
**Purpose:** Refresh expired access token

#### Request

```
grant_type=refresh_token&
refresh_token=existing_refresh_token&
client_id=desktop
```

#### Response

Same as login response with new tokens.

#### Rust Implementation Example

```rust
// src-tauri/src/auth/token_refresh.rs
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Serialize)]
struct RefreshTokenRequest {
    grant_type: String,
    refresh_token: String,
    client_id: String,
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: u32,
    token_type: String,
    refresh_token: Option<String>,
    scope: String,
}

async fn refresh_token(refresh_token: String) -> Result<TokenResponse, reqwest::Error> {
    let client = Client::new();

    let form_data = RefreshTokenRequest {
        grant_type: "refresh_token".to_string(),
        refresh_token,
        client_id: "desktop".to_string(),
    };

    let response = client
        .post("https://api.bitwarden.com/identity/connect/token")
        .header("Content-Type", "application/x-www-form-urlencoded")
        .form(&form_data)
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    response.json::<TokenResponse>().await
}
```

## Security Considerations

### Password Hashing
The password sent to the server must be hashed using the user's KDF settings:

```typescript
async function hashPassword(
  password: string,
  email: string,
  kdfSettings: PreloginResponse
): Promise<string> {
  // 1. Derive master key from password
  const masterKey = await deriveMasterKey(password, email, kdfSettings);

  // 2. Hash master key for server authentication
  const hashedPassword = await pbkdf2(masterKey, password, 1, 256);

  return base64Encode(hashedPassword);
}
```

### Device Identification
Generate a unique, persistent device identifier:

```typescript
function generateDeviceIdentifier(): string {
  // Use a combination of hardware/software characteristics
  // Store persistently for the same device
  return crypto.randomUUID();
}
```

### Token Storage
- Store access tokens in memory only
- Store refresh tokens in secure platform storage
- Clear all tokens on logout
- Implement automatic token refresh

### Rate Limiting
- Implement exponential backoff for failed attempts
- Respect 429 responses with Retry-After headers
- Cache successful prelogin responses briefly

## Error Handling Best Practices

```typescript
class AuthenticationError extends Error {
  constructor(message: string, public code?: string) {
    super(message);
    this.name = 'AuthenticationError';
  }
}

class TwoFactorRequiredError extends Error {
  constructor(
    public providers: number[],
    public providerData: Record<string, any>
  ) {
    super('Two-factor authentication required');
    this.name = 'TwoFactorRequiredError';
  }
}

function handleAuthError(error: any): never {
  if (error.status === 429) {
    throw new Error('Too many login attempts. Please try again later.');
  } else if (error.error === 'invalid_grant') {
    if (error.TwoFactorProviders) {
      throw new TwoFactorRequiredError(error.TwoFactorProviders, error.TwoFactorProviders2);
    }
    throw new AuthenticationError('Invalid email or password');
  } else {
    throw new AuthenticationError(error.error_description || 'Authentication failed');
  }
}
```
