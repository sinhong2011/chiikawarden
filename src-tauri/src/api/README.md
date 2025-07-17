# API Architecture Documentation

## Overview

The API module has been refactored to separate concerns and improve maintainability using the **Repository Pattern** with a **Service Layer**. This architecture provides clean separation between HTTP operations, data access, and business logic.

## Architecture Layers

### 1. HTTP Client Layer (`client.rs`)
- **Purpose**: Low-level HTTP operations
- **Responsibilities**: 
  - Making HTTP requests (GET, POST, PUT, DELETE)
  - Handling authentication headers
  - Managing response parsing and error handling
  - Environment-specific URL resolution

### 2. Repository Layer (`repositories/`)
- **Purpose**: Data access abstraction
- **Responsibilities**:
  - Define interfaces for data operations
  - Implement API-specific data access
  - Handle request/response mapping
  - Provide testable data access contracts

### 3. Service Layer (`services/`)
- **Purpose**: Business logic orchestration
- **Responsibilities**:
  - Complex business operations
  - Data validation and transformation
  - Cross-cutting concerns (logging, caching)
  - High-level API workflows

## Module Structure

```
src/api/
├── client.rs              # HTTP client implementation
├── repositories/
│   ├── mod.rs             # Repository module exports
│   ├── traits.rs          # Repository trait definitions
│   ├── auth_repository.rs # Authentication data access
│   ├── vault_repository.rs# Vault data access
│   └── folder_repository.rs # Folder data access
├── services/
│   ├── mod.rs             # Service module exports
│   ├── auth_service.rs    # Authentication business logic
│   ├── vault_service.rs   # Vault business logic
│   └── sync_service.rs    # Synchronization business logic
├── examples.rs            # Usage examples
└── README.md             # This documentation
```

## Key Benefits

### 1. **Separation of Concerns**
- HTTP operations are isolated from business logic
- Data access is abstracted behind interfaces
- Business logic is centralized in services

### 2. **Testability**
- Each layer can be tested independently
- Repository traits enable easy mocking
- Business logic can be tested without HTTP calls

### 3. **Maintainability**
- Changes to API endpoints only affect repositories
- Business logic changes are isolated to services
- HTTP client changes don't affect higher layers

### 4. **Flexibility**
- Easy to swap implementations (e.g., mock for testing)
- Can support multiple data sources
- Business logic can be reused across different contexts

## Usage Examples

### Basic Setup

```rust
use crate::api::{ApiClient, ApiAuthRepository, ApiAuthService};
use std::sync::Arc;

// 1. Create HTTP client
let api_client = Arc::new(ApiClient::new(app_handle, environment_service));

// 2. Create repository
let auth_repository = Arc::new(ApiAuthRepository::new(api_client));

// 3. Create service
let auth_service = Arc::new(ApiAuthService::new(auth_repository));
```

### Authentication Flow

```rust
use crate::api::services::LoginRequest;

// Create login request
let login_request = LoginRequest {
    email: "user@example.com".to_string(),
    password_hash: "hashed_password".to_string(),
    two_factor_token: None,
};

// Authenticate user
let login_response = auth_service.authenticate(login_request).await?;

// Get user profile
let user_profile = auth_service.get_user_profile(&login_response.access_token).await?;
```

### Vault Operations

```rust
use crate::api::services::CipherData;

// Get all ciphers
let ciphers = vault_service.get_ciphers(access_token).await?;

// Create new cipher
let new_cipher = CipherData {
    id: None,
    name: "My Login".to_string(),
    cipher_type: 1, // Login type
    // ... other fields
};

let created_cipher = vault_service.create_cipher(new_cipher, access_token).await?;
```

### Sync Operations

```rust
use crate::api::services::SyncRequest;

// Perform incremental sync
let sync_result = sync_service.incremental_sync(access_token, last_revision).await?;

// Check sync status
let sync_status = sync_service.get_sync_status(access_token).await?;
```

## Repository Traits

### AuthRepository
- `login()` - Authenticate user
- `refresh_access_token()` - Refresh tokens
- `get_profile()` - Get user profile
- `logout()` - Revoke tokens

### VaultRepository
- `sync_vault()` - Sync vault data
- `get_ciphers()` - Get all ciphers
- `create_cipher()` - Create new cipher
- `update_cipher()` - Update existing cipher
- `delete_cipher()` - Delete cipher
- `send_to_trash()` - Soft delete cipher
- `restore_from_trash()` - Restore cipher
- `permanently_delete()` - Hard delete cipher

### FolderRepository
- `get_folders()` - Get all folders
- `create_folder()` - Create new folder
- `update_folder()` - Update existing folder
- `delete_folder()` - Delete folder

## Service Classes

### ApiAuthService
- Complex authentication workflows
- Token validation and refresh
- User profile management
- Response parsing and validation

### ApiVaultService
- Vault synchronization
- Cipher management
- Folder operations
- Data transformation

### ApiSyncService
- Intelligent sync strategies
- Sync priority calculation
- Data validation
- Error handling and recovery

## Error Handling

The architecture uses consistent error handling patterns:

```rust
use crate::error::{AppError, AppResult};

// Repository level - basic error translation
async fn get_profile(&self, access_token: &str) -> AppResult<Value> {
    self.client.get("/accounts/profile", Some(access_token)).await
}

// Service level - business logic error handling
async fn validate_token(&self, access_token: &str) -> AppResult<bool> {
    match self.auth_repository.get_profile(access_token).await {
        Ok(_) => Ok(true),
        Err(AppError::NetworkError { status: 401, .. }) => Ok(false),
        Err(e) => Err(e),
    }
}
```

## Testing Strategy

### Unit Testing
- Test each service independently
- Mock repository dependencies
- Focus on business logic validation

### Integration Testing
- Test repository implementations
- Verify HTTP client behavior
- Test error handling scenarios

### Example Test Structure
```rust
#[cfg(test)]
mod tests {
    use super::*;
    use mockall::predicate::*;

    #[tokio::test]
    async fn test_authenticate_success() {
        let mut mock_repo = MockAuthRepository::new();
        mock_repo
            .expect_login()
            .returning(|_, _, _| Ok(mock_login_response()));

        let auth_service = ApiAuthService::new(Arc::new(mock_repo));
        let result = auth_service.authenticate(mock_login_request()).await;
        
        assert!(result.is_ok());
    }
}
```

## Migration Guide

### From Old ApiClient
```rust
// Old approach
let response = api_client.login(email, password_hash, two_factor_token).await?;

// New approach
let login_request = LoginRequest {
    email: email.to_string(),
    password_hash: password_hash.to_string(),
    two_factor_token: two_factor_token.map(|s| s.to_string()),
};
let response = auth_service.authenticate(login_request).await?;
```

### Benefits of Migration
1. **Type Safety**: Structured request/response types
2. **Business Logic**: Centralized validation and processing
3. **Error Handling**: Consistent error patterns
4. **Testing**: Mockable dependencies
5. **Maintainability**: Clear separation of concerns

## Best Practices

1. **Repository Implementation**
   - Keep repositories focused on data access
   - Avoid business logic in repositories
   - Use consistent error handling

2. **Service Implementation**
   - Encapsulate complex business workflows
   - Validate inputs and outputs
   - Handle edge cases gracefully

3. **Error Handling**
   - Use specific error types
   - Provide meaningful error messages
   - Log errors appropriately

4. **Testing**
   - Mock external dependencies
   - Test business logic thoroughly
   - Use integration tests for critical paths

## Future Enhancements

1. **Caching Layer**: Add repository-level caching
2. **Retry Logic**: Implement automatic retry for failed requests
3. **Rate Limiting**: Add rate limiting to prevent API abuse
4. **Metrics**: Add performance and usage metrics
5. **Circuit Breaker**: Implement circuit breaker pattern for resilience 