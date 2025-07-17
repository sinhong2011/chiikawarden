# Two-Factor Authentication API Documentation - Tauri Best Practices

## Overview

The Two-Factor Authentication (2FA) API manages setup, configuration, and verification of additional authentication factors. **All 2FA operations must be implemented in the Rust backend** for security and proper integration with system authentication methods.

## Security Architecture

### ✅ Correct Implementation Pattern
```
SolidJS Frontend → invoke('2fa_command') → Rust Backend → System Auth → Bitwarden API
```

### ❌ Never Do This
```typescript
// WRONG: Direct 2FA setup from frontend
const setup = await fetch('/two-factor/authenticator', { method: 'POST' });
```

## Two-Factor Authentication Operations

### 1. Get Two-Factor Providers

**Endpoint:** `GET /two-factor`
**Authentication:** Bearer token required (handled in Rust)
**Purpose:** Retrieve all available and configured 2FA providers

#### Tauri Command Implementation

```rust
// src-tauri/src/two_factor/commands.rs
use tauri::State;
use crate::crypto::CryptoService;

#[tauri::command]
pub async fn get_two_factor_providers(
    api_client: State<'_, ApiClientState>
) -> Result<Vec<TwoFactorProvider>, String> {
    let providers: TwoFactorProvidersResponse = api_client
        .make_authenticated_request(
            reqwest::Method::GET,
            "/two-factor",
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(providers.data)
}

#[tauri::command]
pub async fn setup_totp_authenticator(
    api_client: State<'_, ApiClientState>,
    crypto_service: State<'_, CryptoService>
) -> Result<TotpSetupResponse, String> {
    // Get TOTP setup data
    let setup_data: TotpSetupData = api_client
        .make_authenticated_request(
            reqwest::Method::POST,
            "/two-factor/authenticator",
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(TotpSetupResponse {
        qr_code_uri: setup_data.qr_code_uri,
        secret: setup_data.secret,
        manual_entry_key: setup_data.manual_entry_key,
    })
}

#[tauri::command]
pub async fn verify_totp_setup(
    token: String,
    master_password: String,
    api_client: State<'_, ApiClientState>,
    crypto_service: State<'_, CryptoService>
) -> Result<TwoFactorRecoveryCodes, String> {
    // Hash master password for verification
    let password_hash = crypto_service
        .hash_password(&master_password)
        .await
        .map_err(|e| e.to_string())?;

    let request = VerifyTotpRequest {
        token,
        master_password_hash: password_hash,
    };

    let response: TotpVerificationResponse = api_client
        .make_authenticated_request(
            reqwest::Method::PUT,
            "/two-factor/authenticator",
            Some(request)
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(TwoFactorRecoveryCodes {
        recovery_codes: response.recovery_codes,
    })
}

#[tauri::command]
pub async fn setup_webauthn(
    api_client: State<'_, ApiClientState>
) -> Result<WebAuthnSetupResponse, String> {
    let setup_data: WebAuthnSetupData = api_client
        .make_authenticated_request(
            reqwest::Method::POST,
            "/two-factor/webauthn",
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    // Use system WebAuthn API for credential creation
    let credential = create_webauthn_credential(setup_data.challenge).await?;

    let verify_request = VerifyWebAuthnRequest {
        id: credential.id,
        raw_id: credential.raw_id,
        response: credential.response,
        type_: "public-key".to_string(),
    };

    let response: WebAuthnVerificationResponse = api_client
        .make_authenticated_request(
            reqwest::Method::PUT,
            "/two-factor/webauthn",
            Some(verify_request)
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(WebAuthnSetupResponse {
        enabled: response.enabled,
        keys: response.keys,
    })
}

#[tauri::command]
pub async fn disable_two_factor(
    provider_type: u8,
    master_password: String,
    api_client: State<'_, ApiClientState>,
    crypto_service: State<'_, CryptoService>
) -> Result<(), String> {
    // Hash master password for verification
    let password_hash = crypto_service
        .hash_password(&master_password)
        .await
        .map_err(|e| e.to_string())?;

    let request = DisableTwoFactorRequest {
        master_password_hash: password_hash,
        type_: provider_type,
    };

    api_client
        .make_authenticated_request(
            reqwest::Method::DELETE,
            &format!("/two-factor/{}", provider_type),
            Some(request)
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}

// Platform-specific WebAuthn implementation
#[cfg(target_os = "windows")]
async fn create_webauthn_credential(challenge: String) -> Result<WebAuthnCredential, String> {
    // Use Windows Hello WebAuthn API
    use windows::Security::Credentials::WebAuthenticationCore::*;

    // Implementation for Windows Hello
    todo!("Implement Windows Hello WebAuthn")
}

#[cfg(target_os = "macos")]
async fn create_webauthn_credential(challenge: String) -> Result<WebAuthnCredential, String> {
    // Use macOS Touch ID WebAuthn API
    use core_foundation::*;

    // Implementation for Touch ID
    todo!("Implement Touch ID WebAuthn")
}

#[cfg(target_os = "linux")]
async fn create_webauthn_credential(challenge: String) -> Result<WebAuthnCredential, String> {
    // Use Linux FIDO2 implementation
    todo!("Implement Linux FIDO2")
}
```

#### Frontend Usage

```typescript
// src/services/two-factor.service.ts
import { invoke } from '@tauri-apps/api/tauri';

export class TwoFactorService {
    async getProviders(): Promise<TwoFactorProvider[]> {
        return await invoke('get_two_factor_providers');
    }

    async setupTOTP(): Promise<TotpSetupResponse> {
        return await invoke('setup_totp_authenticator');
    }

    async verifyTOTPSetup(token: string, masterPassword: string): Promise<TwoFactorRecoveryCodes> {
        return await invoke('verify_totp_setup', { token, masterPassword });
    }

    async setupWebAuthn(): Promise<WebAuthnSetupResponse> {
        return await invoke('setup_webauthn');
    }

    async disableTwoFactor(providerType: number, masterPassword: string): Promise<void> {
        return await invoke('disable_two_factor', { providerType, masterPassword });
    }
}
```

#### Two-Factor Provider Types
- `0` - Authenticator (TOTP)
- `1` - Email
- `2` - Duo (deprecated)
- `3` - YubiKey OTP
- `4` - U2F (deprecated, use WebAuthn)
- `5` - Remember Device
- `6` - Duo Organization
- `7` - WebAuthn (FIDO2)

#### Implementation Example

```typescript
interface TwoFactorProviderResponse {
  type: number;
  enabled: boolean;
  object: 'twoFactorProvider';
}

interface TwoFactorListResponse {
  data: TwoFactorProviderResponse[];
  object: 'list';
}

// Rust Implementation Example
async fn get_two_factor_providers(access_token: &str) -> Result<Vec<TwoFactorProviderResponse>, reqwest::Error> {
    let client = reqwest::Client::new();

    let response = client
        .get("https://api.bitwarden.com/two-factor")
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    let result: TwoFactorListResponse = response.json().await?;
    Ok(result.data)
}
```

---

### 2. Enable Authenticator (TOTP)

**Endpoint:** `POST /two-factor/authenticator`
**Authentication:** Bearer token required
**Purpose:** Enable TOTP authenticator 2FA

#### Request

```json
{
  "masterPasswordHash": "hashed_master_password",
  "token": "123456",
  "key": "JBSWY3DPEHPK3PXP"
}
```

#### Response

```json
{
  "enabled": true,
  "key": "JBSWY3DPEHPK3PXP",
  "qr": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAASwAAAEsCAYAAAB5fY51...",
  "object": "twoFactorAuthenticator"
}
```

#### Implementation Example

```typescript
interface EnableAuthenticatorRequest {
  masterPasswordHash: string;
  token: string;
  key: string;
}

interface TwoFactorAuthenticatorResponse {
  enabled: boolean;
  key: string;
  qr: string;
  object: 'twoFactorAuthenticator';
}

async function enableAuthenticator(
  masterPassword: string,
  totpToken: string,
  totpKey: string
): Promise<TwoFactorAuthenticatorResponse> {
  // Hash master password
  const userKey = await getUserKey();
  const masterPasswordHash = await hashPassword(masterPassword, userKey);

  const request: EnableAuthenticatorRequest = {
    masterPasswordHash,
    token: totpToken,
    key: totpKey
  };

  const response = await fetch('/two-factor/authenticator', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(request)
  });

  if (!response.ok) {
    throw new Error('Failed to enable authenticator');
  }

  return response.json();
}

// Helper function to generate TOTP key and setup
async function setupAuthenticator(): Promise<{ key: string; qrCode: string }> {
  // Generate a random TOTP key
  const key = generateTotpKey();

  // Get user email for QR code
  const profile = await getUserProfile();
  const issuer = 'Bitwarden';
  const accountName = profile.email;

  // Generate QR code URL
  const otpAuthUrl = `otpauth://totp/${encodeURIComponent(issuer)}:${encodeURIComponent(accountName)}?secret=${key}&issuer=${encodeURIComponent(issuer)}`;

  // Generate QR code image
  const qrCode = await generateQRCode(otpAuthUrl);

  return { key, qrCode };
}
```

---

### 3. Disable Two-Factor Provider

**Endpoint:** `DELETE /two-factor/{type}`
**Authentication:** Bearer token required
**Purpose:** Disable a specific 2FA provider

#### Request

```json
{
  "masterPasswordHash": "hashed_master_password"
}
```

#### Response

```
200 OK
```

#### Implementation Example

```typescript
async function disableTwoFactorProvider(
  providerType: number,
  masterPassword: string
): Promise<void> {
  const userKey = await getUserKey();
  const masterPasswordHash = await hashPassword(masterPassword, userKey);

  const response = await fetch(`/two-factor/${providerType}`, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      masterPasswordHash
    })
  });

  if (!response.ok) {
    throw new Error('Failed to disable two-factor provider');
  }
}
```

---

### 4. Enable Email 2FA

**Endpoint:** `POST /two-factor/email`
**Authentication:** Bearer token required
**Purpose:** Enable email-based 2FA

#### Request

```json
{
  "masterPasswordHash": "hashed_master_password",
  "email": "user@example.com",
  "token": "123456"
}
```

#### Response

```json
{
  "enabled": true,
  "email": "user@example.com",
  "object": "twoFactorEmail"
}
```

#### Implementation Example

```typescript
interface EnableEmailTwoFactorRequest {
  masterPasswordHash: string;
  email: string;
  token: string;
}

interface TwoFactorEmailResponse {
  enabled: boolean;
  email: string;
  object: 'twoFactorEmail';
}

async function enableEmailTwoFactor(
  masterPassword: string,
  email: string,
  token: string
): Promise<TwoFactorEmailResponse> {
  const userKey = await getUserKey();
  const masterPasswordHash = await hashPassword(masterPassword, userKey);

  const request: EnableEmailTwoFactorRequest = {
    masterPasswordHash,
    email,
    token
  };

  const response = await fetch('/two-factor/email', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(request)
  });

  if (!response.ok) {
    throw new Error('Failed to enable email two-factor');
  }

  return response.json();
}
```

---

### 5. Send Email 2FA Token

**Endpoint:** `POST /two-factor/send-email`
**Authentication:** Bearer token required
**Purpose:** Send 2FA token to configured email address

#### Request

```
POST /two-factor/send-email
```

*No request body required*

#### Response

```
200 OK
```

#### Implementation Example

```typescript
async function sendEmailTwoFactorToken(): Promise<void> {
  const response = await fetch('/two-factor/send-email', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`
    }
  });

  if (!response.ok) {
    throw new Error('Failed to send email token');
  }
}
```

---

### 6. Enable YubiKey 2FA

**Endpoint:** `POST /two-factor/yubikey`
**Authentication:** Bearer token required
**Purpose:** Enable YubiKey OTP 2FA

#### Request

```json
{
  "masterPasswordHash": "hashed_master_password",
  "key1": "yubikey_otp_1",
  "key2": "yubikey_otp_2",
  "key3": "yubikey_otp_3",
  "key4": "yubikey_otp_4",
  "key5": "yubikey_otp_5",
  "nfc": true
}
```

#### Response

```json
{
  "enabled": true,
  "keys": [
    "yubikey_otp_1",
    "yubikey_otp_2"
  ],
  "nfc": true,
  "object": "twoFactorYubiKey"
}
```

#### Implementation Example

```typescript
interface EnableYubiKeyRequest {
  masterPasswordHash: string;
  key1?: string;
  key2?: string;
  key3?: string;
  key4?: string;
  key5?: string;
  nfc: boolean;
}

interface TwoFactorYubiKeyResponse {
  enabled: boolean;
  keys: string[];
  nfc: boolean;
  object: 'twoFactorYubiKey';
}

async function enableYubiKey(
  masterPassword: string,
  yubiKeys: string[],
  nfcEnabled: boolean = false
): Promise<TwoFactorYubiKeyResponse> {
  const userKey = await getUserKey();
  const masterPasswordHash = await hashPassword(masterPassword, userKey);

  const request: EnableYubiKeyRequest = {
    masterPasswordHash,
    nfc: nfcEnabled
  };

  // Add up to 5 YubiKeys
  yubiKeys.forEach((key, index) => {
    if (index < 5) {
      (request as any)[`key${index + 1}`] = key;
    }
  });

  const response = await fetch('/two-factor/yubikey', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(request)
  });

  if (!response.ok) {
    throw new Error('Failed to enable YubiKey');
  }

  return response.json();
}
```

---

### 7. Enable WebAuthn (FIDO2)

**Endpoint:** `POST /two-factor/webauthn`
**Authentication:** Bearer token required
**Purpose:** Enable WebAuthn/FIDO2 2FA

#### Request

```json
{
  "masterPasswordHash": "hashed_master_password",
  "deviceResponse": {
    "id": "credential_id",
    "rawId": "raw_credential_id",
    "response": {
      "attestationObject": "attestation_object",
      "clientDataJSON": "client_data_json"
    },
    "type": "public-key"
  },
  "name": "My Security Key"
}
```

#### Response

```json
{
  "enabled": true,
  "keys": [
    {
      "id": "1",
      "name": "My Security Key",
      "migrated": false
    }
  ],
  "object": "twoFactorWebAuthn"
}
```

#### Implementation Example

```typescript
interface WebAuthnCredential {
  id: string;
  rawId: string;
  response: {
    attestationObject: string;
    clientDataJSON: string;
  };
  type: 'public-key';
}

interface EnableWebAuthnRequest {
  masterPasswordHash: string;
  deviceResponse: WebAuthnCredential;
  name: string;
}

interface TwoFactorWebAuthnResponse {
  enabled: boolean;
  keys: Array<{
    id: string;
    name: string;
    migrated: boolean;
  }>;
  object: 'twoFactorWebAuthn';
}

async function enableWebAuthn(
  masterPassword: string,
  credentialName: string
): Promise<TwoFactorWebAuthnResponse> {
  // 1. Get challenge from server
  const challenge = await getWebAuthnChallenge();

  // 2. Create credential using WebAuthn API
  const credential = await navigator.credentials.create({
    publicKey: {
      challenge: base64ToArrayBuffer(challenge),
      rp: { name: 'Bitwarden' },
      user: {
        id: new TextEncoder().encode(await getUserId()),
        name: await getUserEmail(),
        displayName: await getUserName()
      },
      pubKeyCredParams: [{ alg: -7, type: 'public-key' }],
      authenticatorSelection: {
        authenticatorAttachment: 'cross-platform',
        userVerification: 'discouraged'
      },
      timeout: 60000
    }
  }) as PublicKeyCredential;

  // 3. Prepare request
  const userKey = await getUserKey();
  const masterPasswordHash = await hashPassword(masterPassword, userKey);

  const request: EnableWebAuthnRequest = {
    masterPasswordHash,
    deviceResponse: {
      id: credential.id,
      rawId: arrayBufferToBase64(credential.rawId),
      response: {
        attestationObject: arrayBufferToBase64(
          (credential.response as AuthenticatorAttestationResponse).attestationObject
        ),
        clientDataJSON: arrayBufferToBase64(credential.response.clientDataJSON)
      },
      type: 'public-key'
    },
    name: credentialName
  };

  const response = await fetch('/two-factor/webauthn', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(request)
  });

  if (!response.ok) {
    throw new Error('Failed to enable WebAuthn');
  }

  return response.json();
}
```

## Two-Factor Authentication Management

### 1. 2FA Setup Wizard

```typescript
class TwoFactorSetupWizard {
  async getAvailableProviders(): Promise<TwoFactorProviderInfo[]> {
    const providers = await getTwoFactorProviders();

    return [
      {
        type: 0,
        name: 'Authenticator App',
        description: 'Use an authenticator app like Authy, Google Authenticator, or Microsoft Authenticator',
        enabled: providers.find(p => p.type === 0)?.enabled || false,
        recommended: true,
        setup: () => this.setupAuthenticator()
      },
      {
        type: 1,
        name: 'Email',
        description: 'Receive codes via email',
        enabled: providers.find(p => p.type === 1)?.enabled || false,
        recommended: false,
        setup: () => this.setupEmail()
      },
      {
        type: 3,
        name: 'YubiKey',
        description: 'Use a YubiKey hardware token',
        enabled: providers.find(p => p.type === 3)?.enabled || false,
        recommended: true,
        setup: () => this.setupYubiKey()
      },
      {
        type: 7,
        name: 'FIDO2 WebAuthn',
        description: 'Use a FIDO2 security key or built-in authenticator',
        enabled: providers.find(p => p.type === 7)?.enabled || false,
        recommended: true,
        setup: () => this.setupWebAuthn()
      }
    ];
  }

  private async setupAuthenticator(): Promise<void> {
    // 1. Generate TOTP key and QR code
    const { key, qrCode } = await setupAuthenticator();

    // 2. Show QR code to user
    await this.showQRCode(qrCode, key);

    // 3. Get verification token from user
    const token = await this.getTokenFromUser();

    // 4. Get master password for verification
    const masterPassword = await this.getMasterPassword();

    // 5. Enable authenticator
    await enableAuthenticator(masterPassword, token, key);
  }

  private async setupEmail(): Promise<void> {
    // 1. Get email address
    const email = await this.getEmailFromUser();

    // 2. Send test token
    await sendEmailTwoFactorToken();

    // 3. Get verification token
    const token = await this.getTokenFromUser();

    // 4. Get master password
    const masterPassword = await this.getMasterPassword();

    // 5. Enable email 2FA
    await enableEmailTwoFactor(masterPassword, email, token);
  }

  private async setupYubiKey(): Promise<void> {
    // 1. Get YubiKey OTPs from user
    const yubiKeys = await this.getYubiKeysFromUser();

    // 2. Get master password
    const masterPassword = await this.getMasterPassword();

    // 3. Enable YubiKey
    await enableYubiKey(masterPassword, yubiKeys);
  }

  private async setupWebAuthn(): Promise<void> {
    // 1. Get credential name
    const name = await this.getCredentialNameFromUser();

    // 2. Get master password
    const masterPassword = await this.getMasterPassword();

    // 3. Enable WebAuthn (handles credential creation)
    await enableWebAuthn(masterPassword, name);
  }
}

interface TwoFactorProviderInfo {
  type: number;
  name: string;
  description: string;
  enabled: boolean;
  recommended: boolean;
  setup: () => Promise<void>;
}
```

### 2. Recovery Codes

```typescript
class TwoFactorRecoveryService {
  async generateRecoveryCodes(): Promise<string[]> {
    const response = await fetch('/two-factor/recover', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      }
    });

    if (!response.ok) {
      throw new Error('Failed to generate recovery codes');
    }

    const result = await response.json();
    return result.codes;
  }

  async useRecoveryCode(code: string): Promise<boolean> {
    const response = await fetch('/two-factor/recover', {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ code })
    });

    return response.ok;
  }

  formatRecoveryCodes(codes: string[]): string {
    return codes.map((code, index) => `${index + 1}. ${code}`).join('\n');
  }

  downloadRecoveryCodes(codes: string[]): void {
    const content = `Bitwarden Recovery Codes\n\nGenerated: ${new Date().toISOString()}\n\n${this.formatRecoveryCodes(codes)}\n\nKeep these codes safe and secure. Each code can only be used once.`;

    const blob = new Blob([content], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'bitwarden-recovery-codes.txt';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }
}
```

### 3. 2FA Verification During Login

```typescript
class TwoFactorVerificationService {
  async verifyTwoFactor(
    provider: number,
    token: string,
    remember: boolean = false
  ): Promise<TokenResponse> {
    // This is called during the login process when 2FA is required
    const loginRequest = this.getStoredLoginRequest();

    loginRequest.twoFactorToken = token;
    loginRequest.twoFactorProvider = provider;
    loginRequest.twoFactorRemember = remember ? 1 : 0;

    const response = await fetch('/identity/connect/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: new URLSearchParams(loginRequest).toString()
    });

    if (!response.ok) {
      throw new Error('Two-factor verification failed');
    }

    return response.json();
  }

  async requestWebAuthnChallenge(): Promise<PublicKeyCredentialRequestOptions> {
    const response = await fetch('/two-factor/webauthn/challenge', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      }
    });

    if (!response.ok) {
      throw new Error('Failed to get WebAuthn challenge');
    }

    return response.json();
  }

  async verifyWebAuthn(assertion: PublicKeyCredential): Promise<TokenResponse> {
    const token = JSON.stringify({
      id: assertion.id,
      rawId: arrayBufferToBase64(assertion.rawId),
      response: {
        authenticatorData: arrayBufferToBase64(
          (assertion.response as AuthenticatorAssertionResponse).authenticatorData
        ),
        clientDataJSON: arrayBufferToBase64(assertion.response.clientDataJSON),
        signature: arrayBufferToBase64(
          (assertion.response as AuthenticatorAssertionResponse).signature
        )
      },
      type: 'public-key'
    });

    return this.verifyTwoFactor(7, token);
  }
}
```

## Error Handling

### Two-Factor Specific Errors

```typescript
class TwoFactorError extends Error {
  constructor(
    message: string,
    public code: string,
    public providerType?: number
  ) {
    super(message);
    this.name = 'TwoFactorError';
  }
}

async function handleTwoFactorOperation<T>(
  operation: () => Promise<T>,
  providerType?: number
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    if (error.status === 400) {
      if (error.message?.includes('invalid token')) {
        throw new TwoFactorError('Invalid verification code', 'INVALID_TOKEN', providerType);
      } else if (error.message?.includes('already enabled')) {
        throw new TwoFactorError('Two-factor authentication already enabled', 'ALREADY_ENABLED', providerType);
      } else {
        throw new TwoFactorError('Invalid request', 'INVALID_REQUEST', providerType);
      }
    } else if (error.status === 401) {
      throw new TwoFactorError('Invalid master password', 'INVALID_PASSWORD', providerType);
    } else if (error.status === 429) {
      throw new TwoFactorError('Too many attempts. Please try again later.', 'RATE_LIMITED', providerType);
    } else {
      throw new TwoFactorError('Two-factor operation failed', 'OPERATION_FAILED', providerType);
    }
  }
}
```

## Security Best Practices

### 1. Master Password Verification
Always require master password verification when:
- Enabling new 2FA providers
- Disabling existing 2FA providers
- Viewing recovery codes
- Changing 2FA settings

### 2. Recovery Code Management
- Generate recovery codes when enabling first 2FA method
- Encourage users to download and store codes securely
- Invalidate old codes when generating new ones
- Track usage to prevent reuse

### 3. Provider Recommendations
- Recommend TOTP authenticators as primary method
- Suggest hardware keys (YubiKey, WebAuthn) for high security
- Use email 2FA only as backup method
- Encourage multiple 2FA methods for redundancy

### 4. User Experience
- Provide clear setup instructions for each provider
- Show QR codes for easy authenticator app setup
- Test 2FA before fully enabling
- Provide fallback options during verification

### 5. Device Management
- Track trusted devices when "Remember" is used
- Allow users to view and revoke trusted devices
- Implement device-specific 2FA bypass policies
- Monitor for suspicious device activity
```
