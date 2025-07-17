# Tauri Key Management Security Guide

## 🔒 Security Best Practices

### 1. Memory Management

**Rust Backend:**
```rust
use zeroize::{Zeroize, ZeroizeOnDrop};

#[derive(ZeroizeOnDrop)]
struct SensitiveData {
    key: Vec<u8>,
}

// Always clear sensitive data
fn handle_sensitive_data() {
    let mut secret = vec![1, 2, 3, 4];
    // ... use secret
    secret.zeroize(); // Explicitly clear
}
```

**TypeScript Frontend:**
```typescript
class SecureBuffer {
    private buffer: Uint8Array;
    
    constructor(size: number) {
        this.buffer = new Uint8Array(size);
    }
    
    clear(): void {
        this.buffer.fill(0);
    }
    
    // Always clear when done
    dispose(): void {
        this.clear();
    }
}
```

### 2. Key Storage Security

**✅ DO:**
- Store master key hash (not master key) for verification
- Use platform keychain for biometric keys
- Encrypt user keys before storage
- Clear master key from memory on lock

**❌ DON'T:**
- Store master password in any form
- Keep master key in memory when locked
- Store unencrypted sensitive data
- Log sensitive information

### 3. Encryption Standards

**Key Derivation:**
- PBKDF2: Minimum 600,000 iterations
- Argon2id: 3 iterations, 64MB memory, 4 parallelism
- Always use user's email as salt (normalized)

**Symmetric Encryption:**
- AES-256-CBC with HMAC-SHA256 for authenticated encryption
- Generate random IV for each encryption
- Verify HMAC before decryption

### 4. Error Handling

```rust
// ❌ Wrong - leaks information
match decrypt_result {
    Err(CryptoError::Decryption(msg)) => {
        return Err(format!("Decryption failed: {}", msg));
    }
}

// ✅ Correct - generic error
match decrypt_result {
    Err(_) => {
        log::error!("Decryption failed"); // Log internally
        return Err("Unable to decrypt data".to_string()); // Generic message
    }
}
```

## 🧪 Testing Strategy

### 1. Unit Tests

**Crypto Functions:**
```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_key_derivation_consistency() {
        let password = "test_password";
        let email = "test@example.com";
        let config = KdfConfig::default();
        
        let key1 = KdfService::derive_master_key(password, email, &config).unwrap();
        let key2 = KdfService::derive_master_key(password, email, &config).unwrap();
        
        assert_eq!(key1.as_bytes(), key2.as_bytes());
    }
    
    #[test]
    fn test_encryption_roundtrip() {
        let data = b"sensitive data";
        let key = EncryptionService::generate_key(64).unwrap();
        
        let encrypted = EncryptionService::encrypt(
            data, 
            &key, 
            EncryptionType::AesCbc256HmacSha256B64
        ).unwrap();
        
        let decrypted = EncryptionService::decrypt(
            &encrypted, 
            &key, 
            EncryptionType::AesCbc256HmacSha256B64
        ).unwrap();
        
        assert_eq!(data, decrypted.as_slice());
    }
}
```

### 2. Integration Tests

**Frontend-Backend Communication:**
```typescript
describe('Key Management Integration', () => {
    test('should derive and verify master key', async () => {
        const password = 'test_password_123';
        const email = 'test@example.com';
        const kdfConfig = {
            kdf_type: 'Pbkdf2Sha256' as const,
            iterations: 600000,
        };
        
        const cryptoService = new CryptoFunctionService();
        
        // Derive master key
        const masterKey = await cryptoService.deriveKeyFromPassword(
            password, 
            email, 
            kdfConfig
        );
        
        // Generate hash
        const hash = await cryptoService.hashMasterKey(
            password, 
            masterKey, 
            'local'
        );
        
        expect(masterKey).toHaveLength(32);
        expect(hash).toBeTruthy();
    });
});
```

### 3. Security Tests

**Timing Attack Prevention:**
```rust
#[test]
fn test_constant_time_comparison() {
    let key1 = vec![1u8; 32];
    let key2 = vec![2u8; 32];
    let key3 = vec![1u8; 32];
    
    let start = std::time::Instant::now();
    let _ = constant_time_eq(&key1, &key2);
    let time1 = start.elapsed();
    
    let start = std::time::Instant::now();
    let _ = constant_time_eq(&key1, &key3);
    let time2 = start.elapsed();
    
    // Times should be similar (within reasonable variance)
    let diff = if time1 > time2 { time1 - time2 } else { time2 - time1 };
    assert!(diff < std::time::Duration::from_millis(1));
}
```

## ⚡ Performance Optimization

### 1. Key Derivation

```rust
// Use async for CPU-intensive operations
pub async fn derive_master_key_async(
    password: String,
    email: String,
    kdf_config: KdfConfig,
) -> CryptoResult<MasterKey> {
    tokio::task::spawn_blocking(move || {
        KdfService::derive_master_key(&password, &email, &kdf_config)
    }).await.unwrap()
}
```

### 2. Memory Pool for Crypto Operations

```rust
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct CryptoPool {
    buffers: Arc<Mutex<Vec<Vec<u8>>>>,
}

impl CryptoPool {
    pub async fn get_buffer(&self, size: usize) -> Vec<u8> {
        let mut buffers = self.buffers.lock().await;
        buffers.pop().unwrap_or_else(|| vec![0u8; size])
    }
    
    pub async fn return_buffer(&self, mut buffer: Vec<u8>) {
        buffer.zeroize();
        let mut buffers = self.buffers.lock().await;
        if buffers.len() < 10 { // Limit pool size
            buffers.push(buffer);
        }
    }
}
```

### 3. Frontend Optimization

```typescript
// Use Web Workers for crypto operations
class CryptoWorker {
    private worker: Worker;
    
    constructor() {
        this.worker = new Worker('/crypto-worker.js');
    }
    
    async deriveKey(password: string, salt: string): Promise<Uint8Array> {
        return new Promise((resolve, reject) => {
            this.worker.postMessage({ password, salt });
            this.worker.onmessage = (e) => {
                if (e.data.error) {
                    reject(new Error(e.data.error));
                } else {
                    resolve(new Uint8Array(e.data.key));
                }
            };
        });
    }
}
```

## 🔍 Security Audit Checklist

### Code Review
- [ ] No hardcoded secrets or keys
- [ ] Proper error handling without information leakage
- [ ] Memory cleared after use (zeroize)
- [ ] Constant-time comparisons for sensitive data
- [ ] Input validation on all crypto functions
- [ ] Secure random number generation

### Crypto Implementation
- [ ] KDF parameters meet security requirements
- [ ] Proper IV generation (random, unique)
- [ ] HMAC verification before decryption
- [ ] Key stretching for HMAC variants
- [ ] Secure key storage (keychain integration)

### Platform Security
- [ ] Biometric authentication properly implemented
- [ ] Secure storage APIs used correctly
- [ ] Platform-specific security features enabled
- [ ] Proper permission handling

### Testing Coverage
- [ ] Unit tests for all crypto functions
- [ ] Integration tests for key flows
- [ ] Security tests for timing attacks
- [ ] Error condition testing
- [ ] Platform-specific testing

## 🚨 Common Vulnerabilities to Avoid

### 1. Timing Attacks
```rust
// ❌ Wrong - vulnerable to timing attacks
fn compare_hashes(hash1: &str, hash2: &str) -> bool {
    hash1 == hash2
}

// ✅ Correct - constant time comparison
fn compare_hashes_secure(hash1: &[u8], hash2: &[u8]) -> bool {
    use subtle::ConstantTimeEq;
    hash1.ct_eq(hash2).into()
}
```

### 2. Side-Channel Attacks
```rust
// Clear sensitive data from memory
impl Drop for SensitiveData {
    fn drop(&mut self) {
        self.data.zeroize();
    }
}
```

### 3. Weak Random Number Generation
```rust
// ❌ Wrong - predictable
use rand::prelude::*;
let mut rng = StdRng::seed_from_u64(12345);

// ✅ Correct - cryptographically secure
use rand::rngs::OsRng;
let mut rng = OsRng;
```

## 📊 Performance Benchmarks

Run these benchmarks to ensure performance:

```bash
# Rust benchmarks
cargo bench

# Key derivation should complete within reasonable time:
# PBKDF2 (600k iterations): < 1 second
# Argon2id (3 iterations, 64MB): < 2 seconds

# Encryption/decryption should be fast:
# AES-256-CBC: < 1ms for typical vault data
# RSA-2048: < 10ms for key operations
```

## 🔧 Deployment Security

### Production Build
```bash
# Enable security features
cargo build --release --features security-hardening

# Strip debug symbols
strip target/release/bitwarden-tauri
```

### Environment Variables
```bash
# Never commit these to version control
export BITWARDEN_API_KEY="..."
export ENCRYPTION_SALT="..."
```

### Code Signing
```bash
# Sign the application
codesign --sign "Developer ID" --timestamp target/release/bitwarden-tauri
```

This comprehensive security guide ensures your Tauri key management implementation follows industry best practices and maintains the highest security standards.
