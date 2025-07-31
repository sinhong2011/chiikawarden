// Storage layer module organization
pub mod database;
pub mod key_definition;
pub mod memory_cache;
pub mod secure_key_store;

// Re-export main types for convenience
pub use database::AppDatabase;
pub use secure_key_store::SecureKeyStore;

// Re-export existing modules
pub use memory_cache::*;
