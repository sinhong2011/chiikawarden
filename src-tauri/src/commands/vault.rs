use crate::app_state::AppState;
use crate::error::AppError;
use crate::models::{CipherView, Collection, Folder};
use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::{command, State};

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct GetCiphersRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SaveCipherRequest {
    pub cipher: CipherView,
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct DeleteCipherRequest {
    pub cipher_id: String,
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SearchCiphersRequest {
    pub query: String,
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct GetFoldersRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SaveFolderRequest {
    pub folder: Folder,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct DeleteFolderRequest {
    pub folder_id: String,
    pub user_id: String,
}

#[derive(Debug, Serialize, Deserialize, Type)]
pub struct GetCollectionsRequest {
    pub organization_id: String,
}

/// Get all ciphers for a user
#[command]
#[specta::specta]
pub async fn get_all_ciphers(
    request: GetCiphersRequest,
    state: State<'_, AppState>,
) -> Result<Vec<CipherView>, AppError> {
    state
        .vault_service()
        .get_all_ciphers(&request.user_id)
        .await
}

/// Save a cipher
#[command]
#[specta::specta]
pub async fn save_cipher(
    request: SaveCipherRequest,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    state
        .vault_service()
        .save_cipher(request.cipher, &request.user_id)
        .await
}

/// Delete a cipher
#[command]
#[specta::specta]
pub async fn delete_cipher(
    request: DeleteCipherRequest,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    state
        .vault_service()
        .delete_cipher(&request.cipher_id, &request.user_id)
        .await
}

/// Search ciphers
#[command]
#[specta::specta]
pub async fn search_ciphers(
    request: SearchCiphersRequest,
    state: State<'_, AppState>,
) -> Result<Vec<CipherView>, AppError> {
    state
        .vault_service()
        .search_ciphers(&request.query, &request.user_id)
        .await
}

/// Get folders for a user
#[command]
#[specta::specta]
pub async fn get_folders(
    request: GetFoldersRequest,
    state: State<'_, AppState>,
) -> Result<Vec<Folder>, AppError> {
    state.vault_service().get_folders(&request.user_id).await
}

/// Save a folder
#[command]
#[specta::specta]
pub async fn save_folder(
    request: SaveFolderRequest,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    state.vault_service().save_folder(&request.folder).await
}

/// Delete a folder
#[command]
#[specta::specta]
pub async fn delete_folder(
    request: DeleteFolderRequest,
    state: State<'_, AppState>,
) -> Result<(), AppError> {
    state
        .vault_service()
        .delete_folder(&request.folder_id, &request.user_id)
        .await
}

/// Get collections for an organization
#[command]
#[specta::specta]
pub async fn get_collections(
    request: GetCollectionsRequest,
    state: State<'_, AppState>,
) -> Result<Vec<Collection>, AppError> {
    state
        .vault_service()
        .get_collections(&request.organization_id)
        .await
}
