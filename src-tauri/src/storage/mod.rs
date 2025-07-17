// Storage layer module organization
pub mod database;
pub mod memory_cache;
pub mod stronghold;

// Re-export main types for convenience
pub use database::AppDatabase;

// Re-export existing modules
pub use memory_cache::*;
pub use stronghold::*;
