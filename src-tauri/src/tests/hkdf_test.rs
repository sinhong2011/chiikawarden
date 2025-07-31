use crate::crypto::encryption::KeyDerivationService;
use crate::crypto::CryptoResult;
use crate::error::AppResult;
use tracing::info;

/// Simple test to validate HKDF key stretching functionality
/// This test focuses on the specific MAC verification issue that was causing
/// "Failed to fill stretched key: Unspecified" errors
#[tokio::test]
async fn test_hkdf_key_stretching_simple() -> AppResult<()> {
    // Initialize logging for detailed debugging (ignore if already initialized)
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .with_test_writer()
        .try_init();

    info!("🧪 Testing HKDF key stretching functionality");

    // Use a test master key that was failing in the main application
    let test_master_key =
        hex::decode("0ae52cf00d45b2b039d413628cb2b2c012aec6ce9e1a44954a3168fe71bc478c")
            .expect("Failed to decode test master key");

    info!("🔑 Test master key:");
    info!("   Length: {} bytes", test_master_key.len());
    info!("   Hex: {}", hex::encode(&test_master_key));

    // Test the HKDF key stretching that was failing
    let stretched_keys = KeyDerivationService::stretch_key_hkdf(&test_master_key)
        .await
        .map_err(|e| crate::error::AppError::crypto_error(e.to_string()))?;

    info!("✅ HKDF key stretching successful:");
    info!("   Encryption key length: {} bytes", stretched_keys.0.len());
    info!("   MAC key length: {} bytes", stretched_keys.1.len());
    info!("   Encryption key hex: {}", hex::encode(&stretched_keys.0));
    info!("   MAC key hex: {}", hex::encode(&stretched_keys.1));

    // Validate the stretched keys
    assert_eq!(
        stretched_keys.0.len(),
        32,
        "Encryption key should be 32 bytes"
    );
    assert_eq!(stretched_keys.1.len(), 32, "MAC key should be 32 bytes");
    assert_ne!(
        stretched_keys.0, stretched_keys.1,
        "Encryption and MAC keys should be different"
    );

    info!("🎊 HKDF key stretching test passed!");

    Ok(())
}

/// Test the specific HKDF implementation that was causing issues
#[tokio::test]
async fn test_hkdf_with_real_master_key() -> AppResult<()> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .with_test_writer()
        .try_init();

    info!("🔬 Testing HKDF with real master key from failing authentication");

    // This is the actual master key that was generated during the failing authentication
    // It was derived from the user's password using PBKDF2 with the correct parameters
    let master_key_hex = "0ae52cf00d45b2b039d413628cb2b2c012aec6ce9e1a44954a3168fe71bc478c";
    let master_key = hex::decode(master_key_hex).expect("Failed to decode master key");

    info!("🔑 Master key details:");
    info!("   Original hex: {}", master_key_hex);
    info!("   Decoded length: {} bytes", master_key.len());
    info!("   First 8 bytes: {:02x?}", &master_key[..8]);
    info!(
        "   Last 8 bytes: {:02x?}",
        &master_key[master_key.len() - 8..]
    );

    // Test the HKDF key stretching process
    info!("🔧 Starting HKDF key stretching process...");

    let result = KeyDerivationService::stretch_key_hkdf(&master_key)
        .await
        .map_err(|e| crate::error::AppError::crypto_error(e.to_string()));

    match result {
        Ok((enc_key, mac_key)) => {
            info!("✅ HKDF key stretching succeeded!");
            info!("   Encryption key: {} bytes", enc_key.len());
            info!("   MAC key: {} bytes", mac_key.len());
            info!("   Encryption key hex: {}", hex::encode(&enc_key));
            info!("   MAC key hex: {}", hex::encode(&mac_key));

            // Validate the results
            assert_eq!(enc_key.len(), 32, "Encryption key should be 32 bytes");
            assert_eq!(mac_key.len(), 32, "MAC key should be 32 bytes");
            assert_ne!(enc_key, mac_key, "Keys should be different");

            info!("🎉 All validations passed!");
        }
        Err(e) => {
            info!("❌ HKDF key stretching failed with error: {:?}", e);
            return Err(e);
        }
    }

    Ok(())
}

/// Test HKDF with various key sizes to ensure robustness
#[tokio::test]
async fn test_hkdf_with_different_key_sizes() -> AppResult<()> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .with_test_writer()
        .try_init();

    info!("🧪 Testing HKDF with different key sizes");

    // Test with 32-byte key (standard)
    let key_32 = vec![0x42u8; 32];
    info!("Testing with 32-byte key...");
    let result_32 = KeyDerivationService::stretch_key_hkdf(&key_32)
        .await
        .map_err(|e| crate::error::AppError::crypto_error(e.to_string()))?;
    assert_eq!(result_32.0.len(), 32);
    assert_eq!(result_32.1.len(), 32);
    info!("✅ 32-byte key test passed");

    // Test with 16-byte key
    let key_16 = vec![0x42u8; 16];
    info!("Testing with 16-byte key...");
    let result_16 = KeyDerivationService::stretch_key_hkdf(&key_16)
        .await
        .map_err(|e| crate::error::AppError::crypto_error(e.to_string()))?;
    assert_eq!(result_16.0.len(), 32);
    assert_eq!(result_16.1.len(), 32);
    info!("✅ 16-byte key test passed");

    // Test with 64-byte key
    let key_64 = vec![0x42u8; 64];
    info!("Testing with 64-byte key...");
    let result_64 = KeyDerivationService::stretch_key_hkdf(&key_64)
        .await
        .map_err(|e| crate::error::AppError::crypto_error(e.to_string()))?;
    assert_eq!(result_64.0.len(), 32);
    assert_eq!(result_64.1.len(), 32);
    info!("✅ 64-byte key test passed");

    info!("🎊 All key size tests passed!");

    Ok(())
}
