use crate::api::client::ApiClient;
use crate::api::repositories::traits::VaultRepository;
use crate::error::AppResult;
use async_trait::async_trait;
use serde_json::Value;
use std::sync::Arc;

/// API-based vault repository implementation
pub struct ApiVaultRepository {
    client: Arc<ApiClient>,
}

impl ApiVaultRepository {
    pub fn new(client: Arc<ApiClient>) -> Self {
        Self { client }
    }
}

#[async_trait]
impl VaultRepository for ApiVaultRepository {
    async fn sync_vault(
        &self,
        access_token: &str,
        last_revision: Option<&str>,
    ) -> AppResult<Value> {
        let mut endpoint = "/sync".to_string();
        if let Some(revision) = last_revision {
            endpoint.push_str(&format!("?lastRevisionDate={}", revision));
        }

        self.client.get(&endpoint, Some(access_token)).await
    }

    async fn get_ciphers(&self, access_token: &str) -> AppResult<Value> {
        self.client.get("/ciphers", Some(access_token)).await
    }

    async fn get_cipher(&self, cipher_id: &str, access_token: &str) -> AppResult<Value> {
        let endpoint = format!("/ciphers/{}", cipher_id);
        self.client.get(&endpoint, Some(access_token)).await
    }

    async fn create_cipher(&self, cipher_data: &Value, access_token: &str) -> AppResult<Value> {
        self.client
            .post("/ciphers", cipher_data, Some(access_token))
            .await
    }

    async fn update_cipher(
        &self,
        cipher_id: &str,
        cipher_data: &Value,
        access_token: &str,
    ) -> AppResult<Value> {
        let endpoint = format!("/ciphers/{}", cipher_id);
        self.client
            .put(&endpoint, cipher_data, Some(access_token))
            .await
    }

    async fn delete_cipher(&self, cipher_id: &str, access_token: &str) -> AppResult<Value> {
        let endpoint = format!("/ciphers/{}", cipher_id);
        self.client.delete(&endpoint, Some(access_token)).await
    }

    async fn send_to_trash(&self, cipher_id: &str, access_token: &str) -> AppResult<Value> {
        let endpoint = format!("/ciphers/{}/delete", cipher_id);
        self.client
            .put(&endpoint, &serde_json::json!({}), Some(access_token))
            .await
    }

    async fn restore_from_trash(&self, cipher_id: &str, access_token: &str) -> AppResult<Value> {
        let endpoint = format!("/ciphers/{}/restore", cipher_id);
        self.client
            .put(&endpoint, &serde_json::json!({}), Some(access_token))
            .await
    }

    async fn permanently_delete(&self, cipher_id: &str, access_token: &str) -> AppResult<Value> {
        let endpoint = format!("/ciphers/{}/delete-admin", cipher_id);
        self.client.delete(&endpoint, Some(access_token)).await
    }

    async fn get_collections(&self, access_token: &str) -> AppResult<Value> {
        self.client.get("/collections", Some(access_token)).await
    }
}
