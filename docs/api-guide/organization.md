# Organization API Documentation - Tauri Best Practices

## Overview

The Organization API handles enterprise features including collections, policies, member management, and organizational vault items. **All organization operations must be implemented in the Rust backend** for security, proper permission handling, and enterprise compliance.

## Security Architecture

### ✅ Correct Implementation Pattern
```
SolidJS Frontend → invoke('org_command') → Rust Backend → Permission Check → Bitwarden API
```

### ❌ Never Do This
```typescript
// WRONG: Direct organization API calls from frontend
const org = await fetch(`/organizations/${id}`, { headers: { Authorization: token } });
```

## Organization Operations

### 1. Get Organization Details

**Endpoint:** `GET /organizations/{id}`
**Authentication:** Bearer token required (handled in Rust)
**Purpose:** Retrieve organization information with proper permission validation

#### Tauri Command Implementation

```rust
// src-tauri/src/organization/commands.rs
use tauri::State;
use crate::database::Database;
use crate::crypto::CryptoService;

#[tauri::command]
pub async fn get_organization(
    org_id: String,
    api_client: State<'_, ApiClientState>,
    database: State<'_, Database>
) -> Result<OrganizationView, String> {
    // Check if user has access to this organization
    let user_orgs = database.get_user_organizations().await
        .map_err(|e| e.to_string())?;

    if !user_orgs.iter().any(|org| org.id == org_id) {
        return Err("Access denied to organization".to_string());
    }

    // Try to get from local cache first
    if let Ok(cached_org) = database.get_cached_organization(&org_id).await {
        if !cached_org.is_expired() {
            return Ok(cached_org);
        }
    }

    // Fetch from API
    let organization: OrganizationResponse = api_client
        .make_authenticated_request(
            reqwest::Method::GET,
            &format!("/organizations/{}", org_id),
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    // Cache for offline access
    database.cache_organization(&organization).await
        .map_err(|e| e.to_string())?;

    Ok(organization.into())
}

#[tauri::command]
pub async fn get_organization_collections(
    org_id: String,
    api_client: State<'_, ApiClientState>,
    crypto_service: State<'_, CryptoService>
) -> Result<Vec<CollectionView>, String> {
    // Verify organization access
    verify_organization_access(&org_id).await?;

    let collections: CollectionListResponse = api_client
        .make_authenticated_request(
            reqwest::Method::GET,
            &format!("/organizations/{}/collections", org_id),
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    // Decrypt collection names
    let mut decrypted_collections = Vec::new();
    for collection in collections.data {
        let decrypted = crypto_service
            .decrypt_collection(collection)
            .await
            .map_err(|e| format!("Failed to decrypt collection: {}", e))?;
        decrypted_collections.push(decrypted);
    }

    Ok(decrypted_collections)
}

#[tauri::command]
pub async fn get_organization_members(
    org_id: String,
    api_client: State<'_, ApiClientState>
) -> Result<Vec<OrganizationMember>, String> {
    // Verify admin access
    verify_organization_admin_access(&org_id).await?;

    let members: OrganizationMembersResponse = api_client
        .make_authenticated_request(
            reqwest::Method::GET,
            &format!("/organizations/{}/members", org_id),
            None::<()>
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(members.data)
}

#[tauri::command]
pub async fn invite_organization_member(
    org_id: String,
    email: String,
    role: OrganizationRole,
    collection_ids: Vec<String>,
    api_client: State<'_, ApiClientState>
) -> Result<(), String> {
    // Verify admin access
    verify_organization_admin_access(&org_id).await?;

    let request = InviteMemberRequest {
        emails: vec![email],
        type_: role as u8,
        access_all: false,
        collections: collection_ids.into_iter().map(|id| CollectionAccess {
            id,
            read_only: false,
            hide_passwords: false,
        }).collect(),
    };

    api_client
        .make_authenticated_request(
            reqwest::Method::POST,
            &format!("/organizations/{}/members", org_id),
            Some(request)
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
pub async fn create_organization_collection(
    org_id: String,
    name: String,
    api_client: State<'_, ApiClientState>,
    crypto_service: State<'_, CryptoService>
) -> Result<CollectionView, String> {
    // Verify admin access
    verify_organization_admin_access(&org_id).await?;

    // Encrypt collection name
    let encrypted_name = crypto_service
        .encrypt_string(&name)
        .await
        .map_err(|e| e.to_string())?;

    let request = CreateCollectionRequest {
        name: encrypted_name,
        groups: vec![],
    };

    let created_collection: CollectionResponse = api_client
        .make_authenticated_request(
            reqwest::Method::POST,
            &format!("/organizations/{}/collections", org_id),
            Some(request)
        )
        .await
        .map_err(|e| e.to_string())?;

    // Decrypt and return
    let decrypted_collection = crypto_service
        .decrypt_collection(created_collection)
        .await
        .map_err(|e| e.to_string())?;

    Ok(decrypted_collection)
}

// Helper functions for permission verification
async fn verify_organization_access(org_id: &str) -> Result<(), String> {
    let user_orgs = get_user_organizations().await?;

    if !user_orgs.iter().any(|org| org.id == org_id) {
        return Err("Access denied to organization".to_string());
    }

    Ok(())
}

async fn verify_organization_admin_access(org_id: &str) -> Result<(), String> {
    let user_orgs = get_user_organizations().await?;

    let user_org = user_orgs.iter()
        .find(|org| org.id == org_id)
        .ok_or("Access denied to organization")?;

    if !user_org.is_admin() {
        return Err("Admin access required".to_string());
    }

    Ok(())
}
```

#### Frontend Usage

```typescript
// src/services/organization.service.ts
import { invoke } from '@tauri-apps/api/tauri';

export class OrganizationService {
    async getOrganization(orgId: string): Promise<OrganizationView> {
        return await invoke('get_organization', { orgId });
    }

    async getCollections(orgId: string): Promise<CollectionView[]> {
        return await invoke('get_organization_collections', { orgId });
    }

    async getMembers(orgId: string): Promise<OrganizationMember[]> {
        return await invoke('get_organization_members', { orgId });
    }

    async inviteMember(
        orgId: string,
        email: string,
        role: OrganizationRole,
        collectionIds: string[]
    ): Promise<void> {
        return await invoke('invite_organization_member', {
            orgId,
            email,
            role,
            collectionIds
        });
    }

    async createCollection(orgId: string, name: string): Promise<CollectionView> {
        return await invoke('create_organization_collection', { orgId, name });
    }
}
  "useResetPassword": true,
  "useSecretsManager": false,
  "usePasswordManager": true,
  "usersGetPremium": true,
  "selfHost": false,
  "hasPublicAndPrivateKeys": true,
  "object": "organization"
}
```

#### Plan Types
- `0` - Free
- `1` - Families
- `2` - Teams
- `3` - Enterprise

#### Implementation Example

```typescript
interface OrganizationResponse {
  id: string;
  name: string;
  businessName?: string;
  businessAddress1?: string;
  businessAddress2?: string;
  businessAddress3?: string;
  businessCountry?: string;
  businessTaxNumber?: string;
  billingEmail: string;
  plan: string;
  planType: number;
  seats: number;
  maxCollections: number;
  maxStorageGb?: number;
  usePolicies: boolean;
  useGroups: boolean;
  useDirectory: boolean;
  useEvents: boolean;
  useTotp: boolean;
  use2fa: boolean;
  useApi: boolean;
  useSso: boolean;
  useKeyConnector: boolean;
  useScim: boolean;
  useCustomPermissions: boolean;
  useResetPassword: boolean;
  useSecretsManager: boolean;
  usePasswordManager: boolean;
  usersGetPremium: boolean;
  selfHost: boolean;
  hasPublicAndPrivateKeys: boolean;
  object: 'organization';
}

async function getOrganization(id: string): Promise<OrganizationResponse> {
  const response = await fetch(`/organizations/${id}`, {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    }
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('Organization not found');
    }
    throw new Error('Failed to fetch organization');
  }

  return response.json();
}
```

---

### 2. Get Organization Collections

**Endpoint:** `GET /organizations/{id}/collections`
**Authentication:** Bearer token required
**Purpose:** Retrieve all collections within an organization

#### Request

```http
GET /organizations/org-12345678-1234-1234-1234-123456789012/collections
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```json
{
  "data": [
    {
      "id": "collection-12345678-1234-1234-1234-123456789012",
      "organizationId": "org-12345678-1234-1234-1234-123456789012",
      "name": "2.encrypted_collection_name|base64_encoded_data",
      "externalId": "external_system_id",
      "groups": [
        {
          "id": "group-12345678-1234-1234-1234-123456789012",
          "readOnly": false,
          "hidePasswords": false,
          "manage": true
        }
      ],
      "users": [
        {
          "id": "user-12345678-1234-1234-1234-123456789012",
          "readOnly": false,
          "hidePasswords": false,
          "manage": false
        }
      ],
      "object": "collection"
    }
  ],
  "object": "list"
}
```

#### Implementation Example

```typescript
interface CollectionGroupResponse {
  id: string;
  readOnly: boolean;
  hidePasswords: boolean;
  manage: boolean;
}

interface CollectionUserResponse {
  id: string;
  readOnly: boolean;
  hidePasswords: boolean;
  manage: boolean;
}

interface CollectionResponse {
  id: string;
  organizationId: string;
  name: string;
  externalId?: string;
  groups: CollectionGroupResponse[];
  users: CollectionUserResponse[];
  object: 'collection';
}

interface CollectionListResponse {
  data: CollectionResponse[];
  object: 'list';
}

async function getOrganizationCollections(organizationId: string): Promise<CollectionResponse[]> {
  const response = await fetch(`/organizations/${organizationId}/collections`, {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    }
  });

  if (!response.ok) {
    throw new Error('Failed to fetch organization collections');
  }

  const result: CollectionListResponse = await response.json();
  return result.data;
}
```

---

### 3. Create Collection

**Endpoint:** `POST /organizations/{id}/collections`
**Authentication:** Bearer token required
**Purpose:** Create a new collection within an organization

#### Request

```json
{
  "name": "2.encrypted_collection_name|base64_encoded_data",
  "externalId": "external_system_id",
  "groups": [
    {
      "id": "group-12345678-1234-1234-1234-123456789012",
      "readOnly": false,
      "hidePasswords": false,
      "manage": true
    }
  ],
  "users": [
    {
      "id": "user-12345678-1234-1234-1234-123456789012",
      "readOnly": false,
      "hidePasswords": false,
      "manage": false
    }
  ]
}
```

#### Response

Returns the created collection with the same structure as the GET response.

#### Implementation Example

```typescript
interface CreateCollectionRequest {
  name: string;
  externalId?: string;
  groups: CollectionGroupRequest[];
  users: CollectionUserRequest[];
}

interface CollectionGroupRequest {
  id: string;
  readOnly: boolean;
  hidePasswords: boolean;
  manage: boolean;
}

interface CollectionUserRequest {
  id: string;
  readOnly: boolean;
  hidePasswords: boolean;
  manage: boolean;
}

async function createCollection(
  organizationId: string,
  collectionData: CreateCollectionRequest
): Promise<CollectionResponse> {
  const response = await fetch(`/organizations/${organizationId}/collections`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(collectionData)
  });

  if (!response.ok) {
    throw new Error('Failed to create collection');
  }

  return response.json();
}

// Helper function to create collection with encryption
async function createCollectionFromView(
  organizationId: string,
  name: string,
  groups: CollectionGroupRequest[] = [],
  users: CollectionUserRequest[] = []
): Promise<CollectionResponse> {
  const orgKey = await getOrganizationKey(organizationId);

  const request: CreateCollectionRequest = {
    name: await encryptString(name, orgKey),
    groups,
    users
  };

  return createCollection(organizationId, request);
}
```

---

### 4. Get Organization Members

**Endpoint:** `GET /organizations/{id}/users`
**Authentication:** Bearer token required
**Purpose:** Retrieve all members of an organization

#### Request

```http
GET /organizations/org-12345678-1234-1234-1234-123456789012/users
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```json
{
  "data": [
    {
      "id": "user-12345678-1234-1234-1234-123456789012",
      "userId": "12345678-1234-1234-1234-123456789012",
      "name": "John Doe",
      "email": "john.doe@acme.com",
      "twoFactorEnabled": true,
      "status": 2,
      "type": 2,
      "accessAll": false,
      "externalId": "employee_123",
      "resetPasswordEnrolled": true,
      "collections": [
        {
          "id": "collection-12345678-1234-1234-1234-123456789012",
          "readOnly": false,
          "hidePasswords": false,
          "manage": false
        }
      ],
      "groups": [
        "group-12345678-1234-1234-1234-123456789012"
      ],
      "object": "organizationUser"
    }
  ],
  "object": "list"
}
```

#### User Status Types
- `0` - Invited
- `1` - Accepted
- `2` - Confirmed

#### User Types
- `0` - Owner
- `1` - Admin
- `2` - User
- `3` - Manager
- `4` - Custom

#### Implementation Example

```typescript
interface OrganizationUserCollectionResponse {
  id: string;
  readOnly: boolean;
  hidePasswords: boolean;
  manage: boolean;
}

interface OrganizationUserResponse {
  id: string;
  userId?: string;
  name?: string;
  email: string;
  twoFactorEnabled: boolean;
  status: number;
  type: number;
  accessAll: boolean;
  externalId?: string;
  resetPasswordEnrolled: boolean;
  collections: OrganizationUserCollectionResponse[];
  groups: string[];
  object: 'organizationUser';
}

interface OrganizationUserListResponse {
  data: OrganizationUserResponse[];
  object: 'list';
}

async function getOrganizationUsers(organizationId: string): Promise<OrganizationUserResponse[]> {
  const response = await fetch(`/organizations/${organizationId}/users`, {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    }
  });

  if (!response.ok) {
    throw new Error('Failed to fetch organization users');
  }

  const result: OrganizationUserListResponse = await response.json();
  return result.data;
}
```

---

### 5. Invite User to Organization

**Endpoint:** `POST /organizations/{id}/users/invite`
**Authentication:** Bearer token required
**Purpose:** Invite a user to join the organization

#### Request

```json
{
  "emails": [
    "newuser@acme.com",
    "another@acme.com"
  ],
  "type": 2,
  "accessAll": false,
  "collections": [
    {
      "id": "collection-12345678-1234-1234-1234-123456789012",
      "readOnly": false,
      "hidePasswords": false,
      "manage": false
    }
  ],
  "groups": [
    "group-12345678-1234-1234-1234-123456789012"
  ]
}
```

#### Response

```
200 OK
```

#### Implementation Example

```typescript
interface InviteUserRequest {
  emails: string[];
  type: number;
  accessAll: boolean;
  collections: OrganizationUserCollectionRequest[];
  groups: string[];
}

interface OrganizationUserCollectionRequest {
  id: string;
  readOnly: boolean;
  hidePasswords: boolean;
  manage: boolean;
}

async function inviteUsersToOrganization(
  organizationId: string,
  inviteData: InviteUserRequest
): Promise<void> {
  const response = await fetch(`/organizations/${organizationId}/users/invite`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(inviteData)
  });

  if (!response.ok) {
    throw new Error('Failed to invite users');
  }
}
```

---

### 6. Get Organization Policies

**Endpoint:** `GET /organizations/{id}/policies`
**Authentication:** Bearer token required
**Purpose:** Retrieve all policies configured for an organization

#### Request

```http
GET /organizations/org-12345678-1234-1234-1234-123456789012/policies
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Response

```json
{
  "data": [
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
    },
    {
      "id": "policy-87654321-4321-4321-4321-210987654321",
      "organizationId": "org-12345678-1234-1234-1234-123456789012",
      "type": 2,
      "data": {
        "requireTwoFactor": true
      },
      "enabled": true,
      "object": "policy"
    }
  ],
  "object": "list"
}
```

#### Policy Types
- `0` - Two-step Login
- `1` - Master Password
- `2` - Password Generator
- `3` - Single Org
- `4` - Require SSO
- `5` - Personal Ownership
- `6` - Disable Send
- `7` - Send Options
- `8` - Reset Password
- `9` - Maximum Vault Timeout
- `10` - Disable Personal Vault Export

#### Implementation Example

```typescript
interface PolicyResponse {
  id: string;
  organizationId: string;
  type: number;
  data: Record<string, any>;
  enabled: boolean;
  object: 'policy';
}

interface PolicyListResponse {
  data: PolicyResponse[];
  object: 'list';
}

async function getOrganizationPolicies(organizationId: string): Promise<PolicyResponse[]> {
  const response = await fetch(`/organizations/${organizationId}/policies`, {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    }
  });

  if (!response.ok) {
    throw new Error('Failed to fetch organization policies');
  }

  const result: PolicyListResponse = await response.json();
  return result.data;
}
```

---

### 7. Update Organization Policy

**Endpoint:** `PUT /organizations/{id}/policies/{type}`
**Authentication:** Bearer token required
**Purpose:** Update or create a specific policy for an organization

#### Request

```json
{
  "enabled": true,
  "data": {
    "minComplexity": 4,
    "minLength": 12,
    "requireUpper": true,
    "requireLower": true,
    "requireNumbers": true,
    "requireSpecial": true
  }
}
```

#### Response

Returns the updated policy with the same structure as the GET response.

#### Implementation Example

```typescript
interface UpdatePolicyRequest {
  enabled: boolean;
  data: Record<string, any>;
}

async function updateOrganizationPolicy(
  organizationId: string,
  policyType: number,
  policyData: UpdatePolicyRequest
): Promise<PolicyResponse> {
  const response = await fetch(`/organizations/${organizationId}/policies/${policyType}`, {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(policyData)
  });

  if (!response.ok) {
    throw new Error('Failed to update policy');
  }

  return response.json();
}

// Helper functions for specific policies
async function updateMasterPasswordPolicy(
  organizationId: string,
  minLength: number = 8,
  minComplexity: number = 3,
  requireUpper: boolean = true,
  requireLower: boolean = true,
  requireNumbers: boolean = true,
  requireSpecial: boolean = false
): Promise<PolicyResponse> {
  return updateOrganizationPolicy(organizationId, 1, {
    enabled: true,
    data: {
      minLength,
      minComplexity,
      requireUpper,
      requireLower,
      requireNumbers,
      requireSpecial
    }
  });
}

async function updateTwoFactorPolicy(
  organizationId: string,
  enabled: boolean
): Promise<PolicyResponse> {
  return updateOrganizationPolicy(organizationId, 0, {
    enabled,
    data: {}
  });
}
```

## Organization Management

### 1. Collection Management Service

```typescript
class OrganizationCollectionService {
  async createCollectionWithPermissions(
    organizationId: string,
    name: string,
    groupPermissions: Array<{ groupId: string; permissions: CollectionPermissions }> = [],
    userPermissions: Array<{ userId: string; permissions: CollectionPermissions }> = []
  ): Promise<CollectionResponse> {
    const orgKey = await getOrganizationKey(organizationId);

    const request: CreateCollectionRequest = {
      name: await encryptString(name, orgKey),
      groups: groupPermissions.map(gp => ({
        id: gp.groupId,
        readOnly: gp.permissions.readOnly,
        hidePasswords: gp.permissions.hidePasswords,
        manage: gp.permissions.manage
      })),
      users: userPermissions.map(up => ({
        id: up.userId,
        readOnly: up.permissions.readOnly,
        hidePasswords: up.permissions.hidePasswords,
        manage: up.permissions.manage
      }))
    };

    return createCollection(organizationId, request);
  }

  async getCollectionCiphers(organizationId: string, collectionId: string): Promise<CipherResponse[]> {
    const response = await fetch(`/organizations/${organizationId}/collections/${collectionId}/ciphers`, {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      }
    });

    if (!response.ok) {
      throw new Error('Failed to fetch collection ciphers');
    }

    const result = await response.json();
    return result.data;
  }

  async addCiphersToCollection(
    organizationId: string,
    collectionId: string,
    cipherIds: string[]
  ): Promise<void> {
    const response = await fetch(`/organizations/${organizationId}/collections/${collectionId}/ciphers`, {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ cipherIds })
    });

    if (!response.ok) {
      throw new Error('Failed to add ciphers to collection');
    }
  }

  async removeCiphersFromCollection(
    organizationId: string,
    collectionId: string,
    cipherIds: string[]
  ): Promise<void> {
    const response = await fetch(`/organizations/${organizationId}/collections/${collectionId}/ciphers`, {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ cipherIds })
    });

    if (!response.ok) {
      throw new Error('Failed to remove ciphers from collection');
    }
  }
}

interface CollectionPermissions {
  readOnly: boolean;
  hidePasswords: boolean;
  manage: boolean;
}
```

### 2. Member Management Service

```typescript
class OrganizationMemberService {
  async inviteMembers(
    organizationId: string,
    emails: string[],
    userType: number = 2, // User by default
    collections: OrganizationUserCollectionRequest[] = [],
    groups: string[] = []
  ): Promise<void> {
    const inviteData: InviteUserRequest = {
      emails,
      type: userType,
      accessAll: false,
      collections,
      groups
    };

    await inviteUsersToOrganization(organizationId, inviteData);
  }

  async updateMemberRole(
    organizationId: string,
    userId: string,
    newType: number,
    collections: OrganizationUserCollectionRequest[] = [],
    groups: string[] = []
  ): Promise<void> {
    const response = await fetch(`/organizations/${organizationId}/users/${userId}`, {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        type: newType,
        accessAll: false,
        collections,
        groups
      })
    });

    if (!response.ok) {
      throw new Error('Failed to update member role');
    }
  }

  async removeMember(organizationId: string, userId: string): Promise<void> {
    const response = await fetch(`/organizations/${organizationId}/users/${userId}`, {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${accessToken}`
      }
    });

    if (!response.ok) {
      throw new Error('Failed to remove member');
    }
  }

  async confirmMember(organizationId: string, userId: string, key: string): Promise<void> {
    const response = await fetch(`/organizations/${organizationId}/users/${userId}/confirm`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ key })
    });

    if (!response.ok) {
      throw new Error('Failed to confirm member');
    }
  }

  async bulkConfirmMembers(
    organizationId: string,
    confirmations: Array<{ id: string; key: string }>
  ): Promise<void> {
    const response = await fetch(`/organizations/${organizationId}/users/confirm`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ keys: confirmations })
    });

    if (!response.ok) {
      throw new Error('Failed to bulk confirm members');
    }
  }
}
```

### 3. Policy Management Service

```typescript
class OrganizationPolicyService {
  async enableMasterPasswordPolicy(
    organizationId: string,
    requirements: MasterPasswordPolicyData
  ): Promise<PolicyResponse> {
    return updateOrganizationPolicy(organizationId, 1, {
      enabled: true,
      data: requirements
    });
  }

  async enableTwoFactorPolicy(organizationId: string): Promise<PolicyResponse> {
    return updateOrganizationPolicy(organizationId, 0, {
      enabled: true,
      data: {}
    });
  }

  async enableSingleOrgPolicy(organizationId: string): Promise<PolicyResponse> {
    return updateOrganizationPolicy(organizationId, 3, {
      enabled: true,
      data: {}
    });
  }

  async enableVaultTimeoutPolicy(
    organizationId: string,
    maxVaultTimeoutHours: number
  ): Promise<PolicyResponse> {
    return updateOrganizationPolicy(organizationId, 9, {
      enabled: true,
      data: {
        hours: maxVaultTimeoutHours
      }
    });
  }

  async disablePersonalVaultExport(organizationId: string): Promise<PolicyResponse> {
    return updateOrganizationPolicy(organizationId, 10, {
      enabled: true,
      data: {}
    });
  }

  async getPolicyByType(organizationId: string, policyType: number): Promise<PolicyResponse | null> {
    const policies = await getOrganizationPolicies(organizationId);
    return policies.find(p => p.type === policyType) || null;
  }

  async isPolicyEnabled(organizationId: string, policyType: number): Promise<boolean> {
    const policy = await this.getPolicyByType(organizationId, policyType);
    return policy?.enabled || false;
  }
}

interface MasterPasswordPolicyData {
  minComplexity?: number;
  minLength?: number;
  requireUpper?: boolean;
  requireLower?: boolean;
  requireNumbers?: boolean;
  requireSpecial?: boolean;
}
```

### 4. Organization Events and Audit

```typescript
class OrganizationEventService {
  async getOrganizationEvents(
    organizationId: string,
    start?: Date,
    end?: Date,
    actingUserId?: string,
    itemId?: string,
    eventType?: number
  ): Promise<EventResponse[]> {
    const params = new URLSearchParams();
    if (start) params.append('start', start.toISOString());
    if (end) params.append('end', end.toISOString());
    if (actingUserId) params.append('actingUserId', actingUserId);
    if (itemId) params.append('itemId', itemId);
    if (eventType !== undefined) params.append('type', eventType.toString());

    const response = await fetch(`/organizations/${organizationId}/events?${params}`, {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      }
    });

    if (!response.ok) {
      throw new Error('Failed to fetch organization events');
    }

    const result = await response.json();
    return result.data;
  }

  async exportOrganizationEvents(
    organizationId: string,
    start: Date,
    end: Date,
    format: 'csv' | 'json' = 'csv'
  ): Promise<Blob> {
    const params = new URLSearchParams({
      start: start.toISOString(),
      end: end.toISOString(),
      format
    });

    const response = await fetch(`/organizations/${organizationId}/events/export?${params}`, {
      headers: {
        'Authorization': `Bearer ${accessToken}`
      }
    });

    if (!response.ok) {
      throw new Error('Failed to export organization events');
    }

    return response.blob();
  }
}

interface EventResponse {
  type: number;
  userId?: string;
  organizationId?: string;
  cipherId?: string;
  collectionId?: string;
  groupId?: string;
  policyId?: string;
  actingUserId?: string;
  date: string;
  device: number;
  ipAddress: string;
  object: 'event';
}
```

## Error Handling

### Organization-Specific Errors

```typescript
class OrganizationError extends Error {
  constructor(
    message: string,
    public code: string,
    public organizationId?: string
  ) {
    super(message);
    this.name = 'OrganizationError';
  }
}

async function handleOrganizationOperation<T>(
  operation: () => Promise<T>,
  organizationId?: string
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    if (error.status === 403) {
      throw new OrganizationError('Insufficient organization permissions', 'INSUFFICIENT_PERMISSIONS', organizationId);
    } else if (error.status === 404) {
      throw new OrganizationError('Organization not found', 'ORGANIZATION_NOT_FOUND', organizationId);
    } else if (error.status === 402) {
      throw new OrganizationError('Organization plan upgrade required', 'PLAN_UPGRADE_REQUIRED', organizationId);
    } else if (error.status === 400) {
      throw new OrganizationError('Invalid organization request', 'INVALID_REQUEST', organizationId);
    } else {
      throw new OrganizationError('Organization operation failed', 'OPERATION_FAILED', organizationId);
    }
  }
}
```

## Best Practices

### 1. Permission Management
- Use principle of least privilege for user assignments
- Regularly audit collection and user permissions
- Implement role-based access control through groups
- Monitor policy compliance across the organization

### 2. Security Policies
- Enable two-factor authentication policy for all users
- Set appropriate master password complexity requirements
- Configure vault timeout policies for sensitive environments
- Disable personal vault export for compliance requirements

### 3. Member Lifecycle
- Implement proper onboarding with appropriate collection access
- Regularly review and update member permissions
- Promptly remove access for departing employees
- Use groups for efficient permission management

### 4. Audit and Compliance
- Enable event logging for security monitoring
- Regular export and review of organization events
- Monitor policy violations and enforcement
- Maintain documentation of access control decisions
```
