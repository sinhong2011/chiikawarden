// Database module - organized database functionality
pub mod core;
pub mod migrations;
pub mod queries;

// Re-export the main database interface
pub use core::AppDatabase;
