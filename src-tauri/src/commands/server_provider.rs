use crate::app_state::AppState;

use crate::models::{ConnectivityStatus, ServerProvider, ServerProviderInfo, ServerProviderUrls};
use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::{command, State};

/// Request to add a new custom server provider
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct AddCustomProviderRequest {
    pub label: String,
    pub base_url: String,
}

/// Request to add a new custom server provider with custom URLs
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct AddCustomProviderWithUrlsRequest {
    pub label: String,
    pub urls: ServerProviderUrls,
}

/// Request to update an existing server provider
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct UpdateProviderRequest {
    pub provider_id: String,
    pub label: Option<String>,
    pub urls: Option<ServerProviderUrls>,
}

/// Request to set the current server provider
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct SetCurrentProviderRequest {
    pub provider_id: String,
}

/// Request to remove a server provider
#[derive(Debug, Serialize, Deserialize, Type)]
pub struct RemoveProviderRequest {
    pub provider_id: String,
}

/// Get all available server providers
#[command]
#[specta::specta]
pub async fn get_all_server_providers(
    state: State<'_, AppState>,
) -> Result<Vec<ServerProvider>, String> {
    let providers = state.server_provider_service.get_all_providers().await;
    Ok(providers)
}

/// Get the current active server provider
#[command]
#[specta::specta]
pub async fn get_current_server_provider(
    state: State<'_, AppState>,
) -> Result<Option<ServerProvider>, String> {
    let provider = state.server_provider_service.get_current_provider().await;
    Ok(provider)
}

/// Get server provider information for frontend
#[command]
#[specta::specta]
pub async fn get_server_provider_info(
    state: State<'_, AppState>,
) -> Result<ServerProviderInfo, String> {
    let current_provider = state.server_provider_service.get_current_provider().await;

    let all_providers = state.server_provider_service.get_all_providers().await;

    let preset_providers = state.server_provider_service.get_preset_providers().await;

    let custom_providers = state.server_provider_service.get_custom_providers().await;

    Ok(ServerProviderInfo {
        current_provider,
        all_providers,
        preset_providers,
        custom_providers,
    })
}

/// Set the current active server provider
#[command]
#[specta::specta]
pub async fn set_current_server_provider(
    request: SetCurrentProviderRequest,
    state: State<'_, AppState>,
) -> Result<(), String> {
    state
        .server_provider_service
        .set_current_provider(request.provider_id)
        .await
        .map_err(|e| e.to_string())
}

/// Add a new custom server provider
#[command]
#[specta::specta]
pub async fn add_custom_server_provider(
    request: AddCustomProviderRequest,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let provider_id = state
        .server_provider_service
        .add_custom_provider(request.label, request.base_url)
        .await
        .map_err(|e| e.to_string())?;

    Ok(provider_id)
}

/// Add a new custom server provider with custom URLs
#[command]
#[specta::specta]
pub async fn add_custom_server_provider_with_urls(
    request: AddCustomProviderWithUrlsRequest,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let provider_id = state
        .server_provider_service
        .add_custom_provider_with_urls(request.label, request.urls)
        .await
        .map_err(|e| e.to_string())?;

    Ok(provider_id)
}

/// Update an existing server provider
#[command]
#[specta::specta]
pub async fn update_server_provider(
    request: UpdateProviderRequest,
    state: State<'_, AppState>,
) -> Result<(), String> {
    state
        .server_provider_service
        .update_provider(request.provider_id, request.label, request.urls)
        .await
        .map_err(|e| e.to_string())
}

/// Remove a custom server provider
#[command]
#[specta::specta]
pub async fn remove_server_provider(
    request: RemoveProviderRequest,
    state: State<'_, AppState>,
) -> Result<(), String> {
    state
        .server_provider_service
        .remove_provider(request.provider_id)
        .await
        .map_err(|e| e.to_string())
}

/// Test connectivity to the current server provider
#[command]
#[specta::specta]
pub async fn test_server_provider_connectivity(
    state: State<'_, AppState>,
) -> Result<ConnectivityStatus, String> {
    let status = state
        .server_provider_service
        .test_connectivity()
        .await
        .map_err(|e| e.to_string())?;

    Ok(status)
}

/// Get API URL for the current server provider
#[command]
#[specta::specta]
pub async fn get_server_provider_api_url(state: State<'_, AppState>) -> Result<String, String> {
    let url = state.server_provider_service.get_api_url().await;

    Ok(url)
}

/// Get identity URL for the current server provider
#[command]
#[specta::specta]
pub async fn get_server_provider_identity_url(
    state: State<'_, AppState>,
) -> Result<String, String> {
    let url = state.server_provider_service.get_identity_url().await;

    Ok(url)
}

/// Get web vault URL for the current server provider
#[command]
#[specta::specta]
pub async fn get_server_provider_web_vault_url(
    state: State<'_, AppState>,
) -> Result<String, String> {
    let url = state.server_provider_service.get_web_vault_url().await;

    Ok(url)
}

/// Get icons URL for the current server provider
#[command]
#[specta::specta]
pub async fn get_server_provider_icons_url(state: State<'_, AppState>) -> Result<String, String> {
    let url = state.server_provider_service.get_icons_url().await;

    Ok(url)
}

/// Get notifications URL for the current server provider
#[command]
#[specta::specta]
pub async fn get_server_provider_notifications_url(
    state: State<'_, AppState>,
) -> Result<String, String> {
    let url = state.server_provider_service.get_notifications_url().await;

    Ok(url)
}

/// Get events URL for the current server provider
#[command]
#[specta::specta]
pub async fn get_server_provider_events_url(state: State<'_, AppState>) -> Result<String, String> {
    let url = state.server_provider_service.get_events_url().await;

    Ok(url)
}
