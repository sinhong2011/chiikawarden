#[cfg(test)]
mod crypto_consolidation_tests {
    use super::super::{
        secure_memory::{SecureBytes, SecureKey, KeyType, MemorySecurity},
        device_trust::{DeviceKeyPair, DeviceTrustService},
    };
    use crate::debug_config::CorrelationId;

    #[test]
    fn test_aws_lc_rs_random_generation() {
        // Test that aws-lc-rs random generation works correctly
        let secure_bytes1 = SecureBytes::random(32, "test_key_1").expect("Failed to generate random bytes");
        let secure_bytes2 = SecureBytes::random(32, "test_key_2").expect("Failed to generate random bytes");
        
        // Ensure different random values are generated
        assert_ne!(secure_bytes1.as_bytes(), secure_bytes2.as_bytes());
        assert_eq!(secure_bytes1.as_bytes().len(), 32);
        assert_eq!(secure_bytes2.as_bytes().len(), 32);
    }

    #[test]
    fn test_aws_lc_rs_hkdf_derivation() {
        // Test HKDF key derivation with aws-lc-rs
        let master_key = SecureKey::new(
            vec![0x01; 32], 
            KeyType::MasterKey, 
            "test_master_key"
        );
        
        let derived_key = master_key.derive_key(
            b"test_info", 
            32, 
            KeyType::UserKey, 
            "derived_user_key"
        ).expect("Failed to derive key");
        
        assert_eq!(derived_key.as_bytes().len(), 32);
        assert_ne!(master_key.as_bytes(), derived_key.as_bytes());
    }

    #[test]
    fn test_device_key_generation() {
        // Test device key generation using aws-lc-rs
        let device_key_pair1 = DeviceKeyPair::generate().expect("Failed to generate device key pair");
        let device_key_pair2 = DeviceKeyPair::generate().expect("Failed to generate device key pair");
        
        // Ensure different keys are generated
        assert_ne!(device_key_pair1.device_key, device_key_pair2.device_key);
        assert_ne!(device_key_pair1.device_id, device_key_pair2.device_id);
        assert_eq!(device_key_pair1.device_key.len(), 32); // 256-bit key
    }

    #[test]
    fn test_constant_time_comparison() {
        // Test that constant-time comparison still works
        let data1 = vec![0x01, 0x02, 0x03, 0x04];
        let data2 = vec![0x01, 0x02, 0x03, 0x04];
        let data3 = vec![0x01, 0x02, 0x03, 0x05];
        
        assert!(MemorySecurity::constant_time_eq(&data1, &data2));
        assert!(!MemorySecurity::constant_time_eq(&data1, &data3));
    }

    #[test]
    fn test_secure_salt_generation() {
        // Test secure salt generation
        let correlation_id = CorrelationId::new();
        let salt1 = MemorySecurity::generate_salt(32, &correlation_id).expect("Failed to generate salt");
        let salt2 = MemorySecurity::generate_salt(32, &correlation_id).expect("Failed to generate salt");
        
        assert_ne!(salt1.as_bytes(), salt2.as_bytes());
        assert_eq!(salt1.as_bytes().len(), 32);
    }

    #[test]
    fn test_hkdf_deterministic() {
        // Test that HKDF produces deterministic results with same inputs
        let master_key = SecureKey::new(
            vec![0x42; 32], 
            KeyType::MasterKey, 
            "deterministic_test"
        );
        
        let derived1 = master_key.derive_key(
            b"same_info", 
            32, 
            KeyType::UserKey, 
            "derived1"
        ).expect("Failed to derive key 1");
        
        let derived2 = master_key.derive_key(
            b"same_info", 
            32, 
            KeyType::UserKey, 
            "derived2"
        ).expect("Failed to derive key 2");
        
        // Same inputs should produce same outputs
        assert_eq!(derived1.as_bytes(), derived2.as_bytes());
    }

    #[test]
    fn test_hkdf_different_info() {
        // Test that different info produces different keys
        let master_key = SecureKey::new(
            vec![0x42; 32], 
            KeyType::MasterKey, 
            "info_test"
        );
        
        let derived1 = master_key.derive_key(
            b"info_1", 
            32, 
            KeyType::UserKey, 
            "derived1"
        ).expect("Failed to derive key 1");
        
        let derived2 = master_key.derive_key(
            b"info_2", 
            32, 
            KeyType::UserKey, 
            "derived2"
        ).expect("Failed to derive key 2");
        
        // Different info should produce different keys
        assert_ne!(derived1.as_bytes(), derived2.as_bytes());
    }

    #[test]
    fn test_memory_zeroization() {
        // Test that memory is properly zeroized
        let mut test_data = vec![0xFF; 32];
        MemorySecurity::zeroize_bytes(&mut test_data);
        
        assert!(MemorySecurity::validate_zeroized(&test_data));
    }
}
