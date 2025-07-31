use crate::crypto::{
    cipher_crypto::{CipherCrypto, EncryptedString},
    encryption::EncryptionService,
    kdf::{HashPurpose, KdfService},
    EncryptionType, KdfConfig, KdfType, UserKey,
};
use crate::error::{AppError, AppResult};
use crate::utils::device;
use dotenvy::dotenv;
use serde::{Deserialize, Serialize};
use serde_json;
use std::collections::HashMap;
use std::env;
use tauri_plugin_http::reqwest;
use tracing::{debug, error, info};
use uuid;

/// Prelogin response structure matching the API
#[derive(Debug, Serialize, Deserialize)]
struct PreloginResponse {
    pub kdf: u32,
    #[serde(rename = "kdfIterations")]
    pub kdf_iterations: u32,
    #[serde(rename = "kdfMemory")]
    pub kdf_memory: Option<u32>,
    #[serde(rename = "kdfParallelism")]
    pub kdf_parallelism: Option<u32>,
}

/// Login response structure matching the API
#[derive(Debug, Serialize, Deserialize)]
struct LoginResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: u64,
    #[serde(rename = "Key")]
    pub encrypted_user_key: Option<String>,
}

/// Test credentials loaded from environment
#[derive(Debug)]
struct TestCredentials {
    email: String,
    password: String,
    base_url: String,
}

impl TestCredentials {
    /// Load test credentials from .env.local file
    fn load() -> AppResult<Self> {
        // Load .env.local file from project root (one level up from src-tauri)
        let env_path = std::path::Path::new("../.env.local");
        if env_path.exists() {
            dotenvy::from_path(env_path).ok();
        } else {
            // Fallback to current directory
            dotenv().ok();
        }

        let email = env::var("REAL_EMAIL").map_err(|_| AppError::ConfigurationError {
            message: "REAL_EMAIL not found in .env.local".to_string(),
        })?;

        let password = env::var("REAL_PASSWORD")
            .map_err(|_| AppError::ConfigurationError {
                message: "REAL_PASSWORD not found in .env.local".to_string(),
            })?
            // Remove surrounding quotes if present
            .trim_matches('"')
            .to_string();

        let base_url = env::var("REAL_BASE_URL").map_err(|_| AppError::ConfigurationError {
            message: "REAL_BASE_URL not found in .env.local".to_string(),
        })?;

        Ok(Self {
            email,
            password,
            base_url,
        })
    }
}

/// HTTP client for making API requests during testing
struct TestApiClient {
    client: reqwest::Client,
    base_url: String,
}

impl TestApiClient {
    fn new(base_url: String) -> Self {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .user_agent("Chiikawarden/1.0.0")
            .build()
            .expect("Failed to create HTTP client");

        Self { client, base_url }
    }

    /// Call prelogin API to get KDF settings
    async fn prelogin(&self, email: &str) -> AppResult<PreloginResponse> {
        let url = format!(
            "{}/api/accounts/prelogin",
            self.base_url.trim_end_matches('/')
        );

        let json_data = serde_json::json!({
            "email": email
        });

        info!(
            email = email,
            url = %url,
            "[test_api] Making prelogin API call"
        );

        let response = self
            .client
            .post(&url)
            .json(&json_data)
            .send()
            .await
            .map_err(|e| AppError::NetworkError {
                status: 0,
                message: format!("Prelogin request failed: {}", e),
            })?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::NetworkError {
                status: status.as_u16(),
                message: format!("Prelogin failed with status {}: {}", status, error_text),
            });
        }

        // First get the response text to debug the structure
        let response_text = response.text().await.map_err(|e| AppError::NetworkError {
            status: 200,
            message: format!("Failed to read prelogin response text: {}", e),
        })?;

        debug!(
            response_text = %response_text,
            "[test_api] Raw prelogin response received"
        );

        let prelogin_response: PreloginResponse =
            serde_json::from_str(&response_text).map_err(|e| AppError::NetworkError {
                status: 200,
                message: format!(
                    "Failed to parse prelogin response: {} - Response: {}",
                    e, response_text
                ),
            })?;

        debug!(
            kdf = prelogin_response.kdf,
            kdf_iterations = prelogin_response.kdf_iterations,
            kdf_memory = ?prelogin_response.kdf_memory,
            kdf_parallelism = ?prelogin_response.kdf_parallelism,
            "[test_api] Prelogin response received"
        );

        Ok(prelogin_response)
    }

    /// Call login API with email and password hash
    async fn login(&self, email: &str, password_hash: &str) -> AppResult<LoginResponse> {
        let url = format!(
            "{}/identity/connect/token",
            self.base_url.trim_end_matches('/')
        );

        // Generate device information exactly like core app
        let device_identifier = format!("test-device-{}", uuid::Uuid::new_v4()); // For test, use random UUID
        let device_name = format!(
            "Chiikawarden Desktop - {}",
            hostname::get()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string()
        );

        let mut form_data = HashMap::new();
        form_data.insert("grant_type".to_string(), "password".to_string());
        form_data.insert("username".to_string(), email.to_string());
        form_data.insert("password".to_string(), password_hash.to_string());
        form_data.insert("scope".to_string(), "api offline_access".to_string());
        form_data.insert("client_id".to_string(), "desktop".to_string()); // Match core app
        form_data.insert(
            "deviceType".to_string(),
            device::get_device_type().to_string(),
        ); // Use core app's device type
        form_data.insert("deviceIdentifier".to_string(), device_identifier.clone());
        form_data.insert("deviceName".to_string(), device_name.clone());

        debug!(
            form_data = ?form_data,
            device_type = device::get_device_type(),
            "[test_api] Form data prepared for login request"
        );

        info!(
            email = email,
            url = %url,
            "[test_api] Making login API call"
        );

        // Build headers similar to core app
        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(
            reqwest::header::CONTENT_TYPE,
            "application/x-www-form-urlencoded".parse().unwrap(),
        );
        headers.insert(reqwest::header::ACCEPT, "application/json".parse().unwrap());
        headers.insert(
            reqwest::header::USER_AGENT,
            "Chiikawarden/1.0.0".parse().unwrap(),
        );
        headers.insert("Bitwarden-Client-Name", "Chiikawarden".parse().unwrap());
        headers.insert("Bitwarden-Client-Version", "1.0.0".parse().unwrap());
        headers.insert(reqwest::header::CACHE_CONTROL, "no-store".parse().unwrap());
        headers.insert(reqwest::header::PRAGMA, "no-cache".parse().unwrap());

        let response = self
            .client
            .post(&url)
            .headers(headers)
            .form(&form_data)
            .send()
            .await
            .map_err(|e| AppError::NetworkError {
                status: 0,
                message: format!("Login request failed: {}", e),
            })?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::NetworkError {
                status: status.as_u16(),
                message: format!("Login failed with status {}: {}", status, error_text),
            });
        }

        let login_response: LoginResponse =
            response.json().await.map_err(|e| AppError::NetworkError {
                status: 200,
                message: format!("Failed to parse login response: {}", e),
            })?;

        debug!(
            has_encrypted_user_key = login_response.encrypted_user_key.is_some(),
            encrypted_user_key_preview = login_response
                .encrypted_user_key
                .as_ref()
                .map(|k| &k[..std::cmp::min(50, k.len())]),
            "[test_api] Login response received"
        );

        Ok(login_response)
    }
}

/// Comprehensive test that decrypts a real user's master key using actual login API response data
#[tokio::test]
async fn test_real_master_key_decryption() -> AppResult<()> {
    // Initialize logging for detailed debugging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .with_test_writer()
        .init();

    info!("🧪 Starting comprehensive real master key decryption test");
    info!("📋 This test will:");
    info!("   1. Load real credentials from .env.local");
    info!("   2. Make actual API call to prelogin endpoint");
    info!("   3. Derive master key using real password and KDF settings");
    info!("   4. Hash master key for authentication");
    info!("   5. Make actual API call to login endpoint");
    info!("   6. Decrypt user key from login response using AWS-LC-RS");
    info!("   7. Verify decryption results with comprehensive assertions");

    // Step 1: Load real credentials from .env.local
    info!("📁 Step 1: Loading real credentials from .env.local file");
    let credentials = TestCredentials::load()?;

    info!(
        email = %credentials.email,
        base_url = %credentials.base_url,
        password_length = credentials.password.len(),
        master_password = %credentials.password,
        "✅ Credentials loaded successfully"
    );

    // Step 2: Create HTTP client and call prelogin API
    info!("🌐 Step 2: Making prelogin API call to get KDF settings");
    let api_client = TestApiClient::new(credentials.base_url);
    let prelogin_response = api_client.prelogin(&credentials.email).await?;

    info!(
        kdf_type = prelogin_response.kdf,
        kdf_iterations = prelogin_response.kdf_iterations,
        "✅ Prelogin API call successful"
    );

    // Step 3: Derive master key using KDF settings
    info!("🔑 Step 3: Deriving master key from password using KDF settings");
    let kdf_config = KdfConfig {
        kdf_type: match prelogin_response.kdf {
            0 => KdfType::Pbkdf2Sha256,
            1 => KdfType::Argon2id,
            _ => {
                return Err(AppError::CryptographyError {
                    operation: format!("Unsupported KDF type: {}", prelogin_response.kdf),
                })
            }
        },
        iterations: prelogin_response.kdf_iterations,
        memory: prelogin_response.kdf_memory,
        parallelism: prelogin_response.kdf_parallelism,
    };

    let master_key =
        KdfService::derive_master_key(&credentials.password, &credentials.email, &kdf_config)?;

    info!(
        master_key_length = master_key.as_bytes().len(),
        master_key_preview = format!("{:02x?}", &master_key.as_bytes()[..8]),
        "✅ Master key derived successfully using AWS-LC-RS"
    );

    // Step 4: Hash master key for authentication (EXACTLY like core app)
    info!("🔐 Step 4: Hashing master key for server authentication");
    let password_hash = KdfService::hash_master_key(
        &credentials.password,
        &master_key,
        HashPurpose::ServerAuthorization, // This uses 1 iteration, not 2
    )?;

    debug!(
        password_hash_length = password_hash.len(),
        password_hash_preview = &password_hash[..std::cmp::min(20, password_hash.len())],
        password_hash_full = %password_hash,
        master_password = %credentials.password,
        master_key_preview = format!("{:02x?}", &master_key.as_bytes()[..8]),
        master_key_full = format!("{:02x?}", master_key.as_bytes()),
        expected_core_app_hash = "3KwYqK1E+JQSvet73WAtZ+yuo6U26xC3H+Jiky/tRgk=",
        "✅ Master key hashed for authentication"
    );

    // DEBUGGING: Let's also try the CryptoService method to see if it gives different results
    let crypto_service = crate::crypto::CryptoService::new();
    let crypto_service_hash = crypto_service.hash_master_key(&master_key, &credentials.password)?;
    debug!(
        crypto_service_hash = %crypto_service_hash,
        "🔍 CryptoService hash_master_key result (uses LocalAuthorization)"
    );

    // DEBUGGING: Let's try to manually recreate the expected hash
    // Expected: "3KwYqK1E+JQSvet73WAtZ+yuo6U26xC3H+Jiky/tRgk="
    // Let's try different parameter orders or methods

    // Try with different parameter order (master_key as salt, password as key)
    use aws_lc_rs::pbkdf2::{derive, PBKDF2_HMAC_SHA256};
    use std::num::NonZeroU32;

    let mut manual_hash = [0u8; 32];
    let iterations_nz = NonZeroU32::new(1).unwrap();

    // Try: master_key as salt, password as key (opposite of current)
    derive(
        PBKDF2_HMAC_SHA256,
        iterations_nz,
        master_key.as_bytes(),           // salt
        credentials.password.as_bytes(), // password
        &mut manual_hash,
    );

    use base64::{engine::general_purpose, Engine as _};
    let manual_hash_b64 = general_purpose::STANDARD.encode(manual_hash);
    debug!(
        manual_hash_reversed = %manual_hash_b64,
        "🔍 Manual hash with reversed parameters"
    );

    // Step 5: Make login API call
    info!("🚪 Step 5: Making login API call with hashed password");

    debug!(
        email = %credentials.email,
        password_hash_length = password_hash.len(),
        password_hash_preview = &password_hash[..std::cmp::min(20, password_hash.len())],
        password_hash_full = %password_hash,
        "[test_api] Login request details"
    );

    let login_response = api_client.login(&credentials.email, &password_hash).await
        .map_err(|e| {
            error!(
                email = %credentials.email,
                error = %e,
                "[test_api] Login failed - this might be due to incorrect credentials or server configuration"
            );
            e
        })?;

    let encrypted_user_key =
        login_response
            .encrypted_user_key
            .ok_or_else(|| AppError::CryptographyError {
                operation: "No encrypted user key in login response".to_string(),
            })?;

    info!(
        encrypted_user_key_length = encrypted_user_key.len(),
        encrypted_user_key_preview =
            &encrypted_user_key[..std::cmp::min(50, encrypted_user_key.len())],
        "✅ Login API call successful, encrypted user key received"
    );

    // Step 6: Decrypt user key using master key and AWS-LC-RS
    info!("🔓 Step 6: Decrypting user key from login response using AWS-LC-RS");

    // Parse the encrypted string
    let encrypted_string = EncryptedString::from_string(&encrypted_user_key)?;

    debug!(
        encryption_type = ?encrypted_string.encryption_type,
        iv_length = encrypted_string.iv.len(),
        data_length = encrypted_string.data.len(),
        has_mac = encrypted_string.mac.is_some(),
        mac_length = encrypted_string.mac.as_ref().map(|m| m.len()),
        "📊 Encrypted string parsed successfully"
    );

    // Decrypt user key using the appropriate method based on encryption type
    let user_key = match encrypted_string.encryption_type {
        EncryptionType::AesCbc256B64 => {
            info!("🔧 Using AesCbc256B64 decryption (no key stretching)");
            let decrypted_bytes =
                CipherCrypto::decrypt_bytes(&encrypted_string, master_key.as_bytes())?;
            UserKey::new(decrypted_bytes)
        }
        EncryptionType::AesCbc256HmacSha256B64 => {
            info!("🔧 Using AesCbc256HmacSha256B64 decryption (with key stretching)");
            let stretched_key = EncryptionService::stretch_master_key_for_user_key(&master_key)?;
            let decrypted_bytes = CipherCrypto::decrypt_bytes(&encrypted_string, &stretched_key)?;
            UserKey::new(decrypted_bytes)
        }
    };

    info!(
        user_key_length = user_key.as_bytes().len(),
        user_key_preview = format!("{:02x?}", &user_key.as_bytes()[..8]),
        "✅ User key decrypted successfully using AWS-LC-RS"
    );

    // Step 7: Comprehensive verification and assertions
    info!("✅ Step 7: Performing comprehensive verification of decryption results");

    // Verify user key length (should be 64 bytes for Bitwarden)
    assert_eq!(
        user_key.as_bytes().len(),
        64,
        "User key should be 64 bytes long"
    );

    // Verify user key is not all zeros
    assert!(
        !user_key.as_bytes().iter().all(|&b| b == 0),
        "User key should not be all zeros"
    );

    // Verify user key has sufficient entropy (basic check)
    let unique_bytes: std::collections::HashSet<u8> = user_key.as_bytes().iter().cloned().collect();
    assert!(
        unique_bytes.len() > 10,
        "User key should have sufficient entropy (found {} unique bytes)",
        unique_bytes.len()
    );

    // Log final success
    info!("🎉 Comprehensive real master key decryption test completed successfully!");
    info!("📊 Test Results Summary:");
    info!("   ✅ Real credentials loaded from .env.local");
    info!("   ✅ Prelogin API call successful");
    info!("   ✅ Master key derived using real password and KDF settings");
    info!("   ✅ Master key hashed for authentication");
    info!("   ✅ Login API call successful");
    info!("   ✅ User key decrypted using AWS-LC-RS cryptographic library");
    info!("   ✅ All assertions passed - decryption verified with real data");
    info!("🔐 End-to-end cryptographic flow validated with production-like data");

    Ok(())
}
