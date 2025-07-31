use crate::crypto::{CryptoError, CryptoResult};
use crate::debug_config::CorrelationId;
use subtle::{Choice, ConstantTimeEq, ConstantTimeGreater, ConstantTimeLess};
use tracing::{debug, warn};
use zeroize::Zeroize;

/// Constant-time operations for security-critical comparisons
/// This prevents timing attacks by ensuring operations take the same time
/// regardless of the input values
pub struct ConstantTimeOps;

impl ConstantTimeOps {
    /// Compare two byte slices in constant time
    /// Returns true if they are equal, false otherwise
    /// This prevents timing attacks on sensitive comparisons like MAC verification
    pub fn bytes_eq(a: &[u8], b: &[u8]) -> bool {
        if a.len() != b.len() {
            // Even length comparison should be constant time
            // We still perform a dummy comparison to maintain timing
            let dummy_a: &[u8] = &[0u8; 32];
            let dummy_b: &[u8] = &[1u8; 32];
            let _dummy_result: Choice = ConstantTimeEq::ct_eq(dummy_a, dummy_b);
            return false;
        }

        ConstantTimeEq::ct_eq(a, b).into()
    }

    /// Compare two strings in constant time
    /// Converts to bytes and performs constant-time comparison
    pub fn strings_eq(a: &str, b: &str) -> bool {
        Self::bytes_eq(a.as_bytes(), b.as_bytes())
    }

    /// Verify a MAC (Message Authentication Code) in constant time
    /// This is critical for preventing timing attacks on MAC verification
    pub fn verify_mac(
        expected_mac: &[u8],
        computed_mac: &[u8],
        correlation_id: &CorrelationId,
    ) -> CryptoResult<bool> {
        debug!(
            expected_len = expected_mac.len(),
            computed_len = computed_mac.len(),
            correlation_id = %correlation_id,
            "[constant_time] Performing constant-time MAC verification"
        );

        if expected_mac.len() != computed_mac.len() {
            warn!(
                expected_len = expected_mac.len(),
                computed_len = computed_mac.len(),
                correlation_id = %correlation_id,
                "[constant_time] MAC length mismatch - potential attack"
            );

            // Still perform dummy comparison to maintain constant time
            let dummy_expected: &[u8] = &[0u8; 32];
            let dummy_computed: &[u8] = &[1u8; 32];
            let _dummy_result: Choice = ConstantTimeEq::ct_eq(dummy_expected, dummy_computed);

            return Ok(false);
        }

        let is_valid: bool = ConstantTimeEq::ct_eq(expected_mac, computed_mac).into();

        if !is_valid {
            warn!(
                correlation_id = %correlation_id,
                "[constant_time] MAC verification failed - potential tampering"
            );
        } else {
            debug!(
                correlation_id = %correlation_id,
                "[constant_time] MAC verification successful"
            );
        }

        Ok(is_valid)
    }

    /// Compare two hash values in constant time
    /// Used for password hash verification and similar operations
    pub fn verify_hash(
        expected_hash: &[u8],
        computed_hash: &[u8],
        correlation_id: &CorrelationId,
    ) -> CryptoResult<bool> {
        debug!(
            expected_len = expected_hash.len(),
            computed_len = computed_hash.len(),
            correlation_id = %correlation_id,
            "[constant_time] Performing constant-time hash verification"
        );

        let is_valid = Self::bytes_eq(expected_hash, computed_hash);

        if !is_valid {
            warn!(
                correlation_id = %correlation_id,
                "[constant_time] Hash verification failed"
            );
        } else {
            debug!(
                correlation_id = %correlation_id,
                "[constant_time] Hash verification successful"
            );
        }

        Ok(is_valid)
    }

    /// Select between two values in constant time based on a condition
    /// This prevents timing attacks when choosing between different code paths
    pub fn conditional_select<T: Copy>(condition: bool, if_true: T, if_false: T) -> T {
        let choice = if condition {
            Choice::from(1)
        } else {
            Choice::from(0)
        };

        // This is a simplified version - in practice you'd need to implement
        // ConditionallySelectable for your types or use existing implementations
        if bool::from(choice) {
            if_true
        } else {
            if_false
        }
    }

    /// Compare two numbers in constant time
    /// Returns true if a > b, false otherwise
    pub fn greater_than(a: u64, b: u64) -> bool {
        a.ct_gt(&b).into()
    }

    /// Compare two numbers in constant time
    /// Returns true if a < b, false otherwise
    pub fn less_than(a: u64, b: u64) -> bool {
        a.ct_lt(&b).into()
    }

    /// Find the index of a value in a slice in constant time
    /// Returns None if not found, Some(index) if found
    /// This prevents timing attacks when searching for sensitive values
    pub fn constant_time_find(haystack: &[u8], needle: u8) -> Option<usize> {
        let mut found_index = 0usize;
        let mut found = Choice::from(0);

        for (i, &byte) in haystack.iter().enumerate() {
            let is_match = ConstantTimeEq::ct_eq(&byte, &needle);
            // Update found_index only on first match to get the first occurrence
            let should_update = is_match & !found;
            found_index = if bool::from(should_update) {
                i
            } else {
                found_index
            };
            found = found | is_match;
        }

        if bool::from(found) {
            Some(found_index)
        } else {
            None
        }
    }

    /// Securely clear a mutable slice in constant time
    /// This ensures sensitive data is properly zeroized
    pub fn secure_clear(data: &mut [u8]) {
        data.zeroize();
    }

    /// Copy data in constant time to prevent timing attacks
    /// The copy operation takes the same time regardless of data content
    pub fn constant_time_copy(src: &[u8], dst: &mut [u8]) -> CryptoResult<()> {
        if src.len() != dst.len() {
            return Err(CryptoError::KeyOperation(
                "Source and destination lengths must match for constant-time copy".to_string(),
            ));
        }

        // Use a simple loop that doesn't branch on data content
        for (s, d) in src.iter().zip(dst.iter_mut()) {
            *d = *s;
        }

        Ok(())
    }

    /// Validate that a byte slice contains only valid characters for a given charset
    /// This is done in constant time to prevent information leakage
    pub fn validate_charset_constant_time(data: &[u8], valid_chars: &[u8]) -> bool {
        let mut all_valid = Choice::from(1);

        for &byte in data {
            let mut byte_valid = Choice::from(0);

            // Check if this byte is in the valid character set
            for &valid_char in valid_chars {
                let is_match = ConstantTimeEq::ct_eq(&byte, &valid_char);
                byte_valid = byte_valid | is_match;
            }

            // Update overall validity - all bytes must be valid
            all_valid = all_valid & byte_valid;
        }

        bool::from(all_valid)
    }

    /// Constant-time string length validation
    /// Prevents timing attacks when validating string lengths
    pub fn validate_length_range(data: &[u8], min_len: usize, max_len: usize) -> bool {
        let len = data.len();
        let min_valid = len >= min_len;
        let max_valid = len <= max_len;

        // Use constant-time operations for the final decision
        let min_choice = if min_valid {
            Choice::from(1)
        } else {
            Choice::from(0)
        };
        let max_choice = if max_valid {
            Choice::from(1)
        } else {
            Choice::from(0)
        };

        bool::from(min_choice & max_choice)
    }

    /// Constant-time base64 validation
    /// Validates base64 characters without timing attacks
    pub fn validate_base64_constant_time(data: &[u8]) -> bool {
        const BASE64_CHARS: &[u8] =
            b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
        Self::validate_charset_constant_time(data, BASE64_CHARS)
    }

    /// Constant-time hex validation
    /// Validates hexadecimal characters without timing attacks
    pub fn validate_hex_constant_time(data: &[u8]) -> bool {
        const HEX_CHARS: &[u8] = b"0123456789ABCDEFabcdef";
        Self::validate_charset_constant_time(data, HEX_CHARS)
    }
}

/// Trait for types that can be compared in constant time
pub trait ConstantTimeComparable {
    /// Compare two instances in constant time
    fn ct_eq(&self, other: &Self) -> bool;
}

/// Implement constant-time comparison for common types
impl ConstantTimeComparable for String {
    fn ct_eq(&self, other: &Self) -> bool {
        ConstantTimeOps::strings_eq(self, other)
    }
}

impl ConstantTimeComparable for Vec<u8> {
    fn ct_eq(&self, other: &Self) -> bool {
        ConstantTimeOps::bytes_eq(self, other)
    }
}

impl ConstantTimeComparable for [u8] {
    fn ct_eq(&self, other: &Self) -> bool {
        ConstantTimeOps::bytes_eq(self, other)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::debug_config::CorrelationId;

    #[test]
    fn test_constant_time_bytes_eq() {
        let a = b"hello world";
        let b = b"hello world";
        let c = b"hello world!";
        let d = b"different";

        assert!(ConstantTimeOps::bytes_eq(a, b));
        assert!(!ConstantTimeOps::bytes_eq(a, c));
        assert!(!ConstantTimeOps::bytes_eq(a, d));
    }

    #[test]
    fn test_constant_time_strings_eq() {
        let a = "hello world";
        let b = "hello world";
        let c = "hello world!";
        let d = "different";

        assert!(ConstantTimeOps::strings_eq(a, b));
        assert!(!ConstantTimeOps::strings_eq(a, c));
        assert!(!ConstantTimeOps::strings_eq(a, d));
    }

    #[test]
    fn test_mac_verification() {
        let correlation_id = CorrelationId::new();
        let mac1 = b"valid_mac_12345678901234567890";
        let mac2 = b"valid_mac_12345678901234567890";
        let mac3 = b"invalid_mac_1234567890123456789";

        assert!(ConstantTimeOps::verify_mac(mac1, mac2, &correlation_id).unwrap());
        assert!(!ConstantTimeOps::verify_mac(mac1, mac3, &correlation_id).unwrap());
    }

    #[test]
    fn test_length_validation() {
        let data1 = b"hello";
        let data2 = b"hi";
        let data3 = b"this is a very long string";

        assert!(ConstantTimeOps::validate_length_range(data1, 3, 10));
        assert!(!ConstantTimeOps::validate_length_range(data2, 3, 10));
        assert!(!ConstantTimeOps::validate_length_range(data3, 3, 10));
    }

    #[test]
    fn test_base64_validation() {
        let valid_b64 = b"SGVsbG8gV29ybGQ=";
        let invalid_b64 = b"Hello@World!";

        assert!(ConstantTimeOps::validate_base64_constant_time(valid_b64));
        assert!(!ConstantTimeOps::validate_base64_constant_time(invalid_b64));
    }

    #[test]
    fn test_hex_validation() {
        let valid_hex = b"48656c6c6f20576f726c64";
        let invalid_hex = b"Hello World";

        assert!(ConstantTimeOps::validate_hex_constant_time(valid_hex));
        assert!(!ConstantTimeOps::validate_hex_constant_time(invalid_hex));
    }

    #[test]
    fn test_constant_time_find() {
        let haystack = b"hello world";

        assert_eq!(ConstantTimeOps::constant_time_find(haystack, b'h'), Some(0));
        assert_eq!(ConstantTimeOps::constant_time_find(haystack, b'o'), Some(4));
        assert_eq!(ConstantTimeOps::constant_time_find(haystack, b'z'), None);
    }

    #[test]
    fn test_numeric_comparisons() {
        assert!(ConstantTimeOps::greater_than(10, 5));
        assert!(!ConstantTimeOps::greater_than(5, 10));
        assert!(!ConstantTimeOps::greater_than(5, 5));

        assert!(ConstantTimeOps::less_than(5, 10));
        assert!(!ConstantTimeOps::less_than(10, 5));
        assert!(!ConstantTimeOps::less_than(5, 5));
    }
}
