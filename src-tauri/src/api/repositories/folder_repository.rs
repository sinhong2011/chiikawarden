use crate::api::client::ApiClient;
use crate::api::repositories::traits::FolderRepository;
use crate::error::AppResult;
use async_trait::async_trait;
use serde_json::Value;
use std::sync::Arc;

/// API-based folder repository implementation
pub struct ApiFolderRepository {
    client: Arc<ApiClient>,
}

impl ApiFolderRepository {
    pub fn new(client: Arc<ApiClient>) -> Self {
        Self { client }
    }
}

#[async_trait]
impl FolderRepository for ApiFolderRepository {
    async fn get_folders(&self, access_token: &str) -> AppResult<Value> {
        self.client.get("/folders", Some(access_token)).await
    }

    async fn create_folder(&self, folder_data: &Value, access_token: &str) -> AppResult<Value> {
        self.client
            .post("/folders", folder_data, Some(access_token))
            .await
    }

    async fn update_folder(
        &self,
        folder_id: &str,
        folder_data: &Value,
        access_token: &str,
    ) -> AppResult<Value> {
        let endpoint = format!("/folders/{}", folder_id);
        self.client
            .put(&endpoint, folder_data, Some(access_token))
            .await
    }

    async fn delete_folder(&self, folder_id: &str, access_token: &str) -> AppResult<Value> {
        let endpoint = format!("/folders/{}", folder_id);
        self.client.delete(&endpoint, Some(access_token)).await
    }
}
