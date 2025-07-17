// Server provider types for frontend

export enum ServerProviderType {
  Preset = "Preset",
  Custom = "Custom",
}

export type Region = string | null;

export interface ServerProviderUrls {
  base?: string;
  api?: string;
  identity?: string;
  icons?: string;
  web_vault?: string;
  notifications?: string;
  events?: string;
  key_connector?: string;
  scim?: string;
}

export interface ServerProvider {
  id: string;
  provider_type: ServerProviderType;
  label: string;
  region: Region; // Only for preset providers
  urls: ServerProviderUrls;
  created_at: string;
  updated_at: string;
}

export interface ServerProviderInfo {
  current_provider?: ServerProvider;
  all_providers: ServerProvider[];
  preset_providers: ServerProvider[];
  custom_providers: ServerProvider[];
}

export interface ConnectivityStatus {
  api_reachable: boolean;
  identity_reachable: boolean;
  overall_status: boolean;
}

// Request types for Tauri commands
export interface AddCustomProviderRequest {
  label: string;
  base_url: string;
}

export interface AddCustomProviderWithUrlsRequest {
  label: string;
  urls: ServerProviderUrls;
}

export interface UpdateProviderRequest {
  provider_id: string;
  label?: string;
  urls?: ServerProviderUrls;
}

export interface SetCurrentProviderRequest {
  provider_id: string;
}

export interface RemoveProviderRequest {
  provider_id: string;
}

// Form types for UI components
export interface ServerProviderFormData {
  label: string;
  base_url: string;
  advanced_mode?: boolean;
  custom_urls?: ServerProviderUrls;
}

export interface ServerProviderSelectOption {
  value: string;
  label: string;
  provider_type: ServerProviderType;
  is_current?: boolean;
}
