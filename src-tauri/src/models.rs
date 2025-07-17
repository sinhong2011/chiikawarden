// Re-export all models from their respective modules
pub mod auth;
pub mod cipher;
pub mod server_provider;
pub mod settings;
pub mod user;

pub use cipher::*;
pub use server_provider::*;
pub use settings::*;
pub use user::*;

use uuid::Uuid;

/// Helper function to generate new UUID
pub fn new_uuid() -> String {
    Uuid::new_v4().to_string()
}
