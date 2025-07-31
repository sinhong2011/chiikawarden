use crate::error::{AppError, AppResult};
use crate::services::ServerProviderService;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use specta::Type;
use std::sync::Arc;
use std::time::Duration;
use tauri::{AppHandle, Emitter};
use tokio::sync::{broadcast, RwLock};
use tokio::time::{interval, sleep};
use tracing::{debug, error, info, warn};

/// Network connectivity state
#[derive(Debug, Clone, Serialize, Deserialize, Type, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum NetworkState {
    Online,
    Offline,
    Limited, // Network available but server unreachable
    Unknown,
}

impl std::fmt::Display for NetworkState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            NetworkState::Online => write!(f, "online"),
            NetworkState::Offline => write!(f, "offline"),
            NetworkState::Limited => write!(f, "limited"),
            NetworkState::Unknown => write!(f, "unknown"),
        }
    }
}

/// Connection quality metrics
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct ConnectionQuality {
    pub latency_ms: Option<u32>,
    pub last_successful_ping: Option<DateTime<Utc>>,
    pub consecutive_failures: u32,
    pub success_rate: f32, // 0.0 to 1.0
}

impl Default for ConnectionQuality {
    fn default() -> Self {
        Self {
            latency_ms: None,
            last_successful_ping: None,
            consecutive_failures: 0,
            success_rate: 0.0,
        }
    }
}

/// Network status information
#[derive(Debug, Clone, Serialize, Deserialize, Type)]
pub struct NetworkStatus {
    pub state: NetworkState,
    pub server_reachable: bool,
    pub last_check: DateTime<Utc>,
    pub quality: ConnectionQuality,
    pub retry_count: u32,
    pub next_retry_at: Option<DateTime<Utc>>,
}

impl Default for NetworkStatus {
    fn default() -> Self {
        Self {
            state: NetworkState::Unknown,
            server_reachable: false,
            last_check: Utc::now(),
            quality: ConnectionQuality::default(),
            retry_count: 0,
            next_retry_at: None,
        }
    }
}

/// Network monitoring service with automatic connectivity detection
pub struct NetworkMonitorService {
    app_handle: AppHandle,
    server_provider_service: Arc<ServerProviderService>,
    http_client: tauri_plugin_http::reqwest::Client,
    status: Arc<RwLock<NetworkStatus>>,
    status_sender: broadcast::Sender<NetworkStatus>,
    monitoring_enabled: Arc<RwLock<bool>>,
    check_interval: Duration,
    retry_intervals: Vec<Duration>, // Exponential backoff intervals
}

impl NetworkMonitorService {
    /// Create a new network monitor service
    pub async fn new(
        app_handle: AppHandle,
        server_provider_service: Arc<ServerProviderService>,
    ) -> AppResult<Self> {
        let http_client = tauri_plugin_http::reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .user_agent("Chiikawarden/1.0.0")
            .build()
            .map_err(|e| AppError::InternalError {
                message: format!("Failed to create HTTP client: {}", e),
            })?;

        let (status_sender, _) = broadcast::channel(100);

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (max)
        let retry_intervals = vec![
            Duration::from_secs(1),
            Duration::from_secs(2),
            Duration::from_secs(4),
            Duration::from_secs(8),
            Duration::from_secs(16),
            Duration::from_secs(30),
        ];

        Ok(Self {
            app_handle,
            server_provider_service,
            http_client,
            status: Arc::new(RwLock::new(NetworkStatus::default())),
            status_sender,
            monitoring_enabled: Arc::new(RwLock::new(false)),
            check_interval: Duration::from_secs(30), // Check every 30 seconds
            retry_intervals,
        })
    }

    /// Start network monitoring
    pub async fn start_monitoring(&self) -> AppResult<()> {
        let mut enabled = self.monitoring_enabled.write().await;
        if *enabled {
            return Ok(()); // Already monitoring
        }
        *enabled = true;
        drop(enabled);

        info!("[network_monitor] Starting network connectivity monitoring");

        // Perform initial connectivity check
        self.check_connectivity().await?;

        // Start background monitoring task
        let status = Arc::clone(&self.status);
        let status_sender = self.status_sender.clone();
        let app_handle = self.app_handle.clone();
        let server_provider_service = Arc::clone(&self.server_provider_service);
        let http_client = self.http_client.clone();
        let monitoring_enabled = Arc::clone(&self.monitoring_enabled);
        let check_interval = self.check_interval;
        let retry_intervals = self.retry_intervals.clone();

        tokio::spawn(async move {
            let mut interval_timer = interval(check_interval);

            while *monitoring_enabled.read().await {
                interval_timer.tick().await;

                match Self::perform_connectivity_check(
                    &server_provider_service,
                    &http_client,
                    &retry_intervals,
                )
                .await
                {
                    Ok(new_status) => {
                        let mut current_status = status.write().await;
                        let state_changed = current_status.state != new_status.state;
                        *current_status = new_status.clone();
                        drop(current_status);

                        // Emit status update
                        if let Err(e) = status_sender.send(new_status.clone()) {
                            warn!("[network_monitor] Failed to broadcast status update: {}", e);
                        }

                        // Emit Tauri event for frontend
                        if let Err(e) = app_handle.emit("network_status_changed", &new_status) {
                            warn!(
                                "[network_monitor] Failed to emit network status event: {}",
                                e
                            );
                        }

                        // Emit mode change event if state changed
                        if state_changed {
                            let mode = match new_status.state {
                                NetworkState::Online => "online",
                                NetworkState::Offline | NetworkState::Limited => "offline",
                                NetworkState::Unknown => "unknown",
                            };

                            if let Err(e) = app_handle.emit("sync_mode_changed", mode) {
                                warn!("[network_monitor] Failed to emit sync mode event: {}", e);
                            }

                            info!(
                                "[network_monitor] Network state changed to: {} (server_reachable: {})",
                                new_status.state, new_status.server_reachable
                            );
                        }
                    }
                    Err(e) => {
                        error!("[network_monitor] Connectivity check failed: {}", e);
                    }
                }
            }

            info!("[network_monitor] Network monitoring stopped");
        });

        Ok(())
    }

    /// Stop network monitoring
    pub async fn stop_monitoring(&self) {
        let mut enabled = self.monitoring_enabled.write().await;
        *enabled = false;
        info!("[network_monitor] Network monitoring stopped");
    }

    /// Get current network status
    pub async fn get_status(&self) -> NetworkStatus {
        self.status.read().await.clone()
    }

    /// Subscribe to network status changes
    pub fn subscribe(&self) -> broadcast::Receiver<NetworkStatus> {
        self.status_sender.subscribe()
    }

    /// Force a connectivity check
    pub async fn check_connectivity(&self) -> AppResult<NetworkStatus> {
        let new_status = Self::perform_connectivity_check(
            &self.server_provider_service,
            &self.http_client,
            &self.retry_intervals,
        )
        .await?;

        let mut current_status = self.status.write().await;
        let state_changed = current_status.state != new_status.state;
        *current_status = new_status.clone();
        drop(current_status);

        // Emit status update
        if let Err(e) = self.status_sender.send(new_status.clone()) {
            warn!("[network_monitor] Failed to broadcast status update: {}", e);
        }

        // Emit Tauri event for frontend
        if let Err(e) = self.app_handle.emit("network_status_changed", &new_status) {
            warn!(
                "[network_monitor] Failed to emit network status event: {}",
                e
            );
        }

        // Emit mode change event if state changed
        if state_changed {
            let mode = match new_status.state {
                NetworkState::Online => "online",
                NetworkState::Offline | NetworkState::Limited => "offline",
                NetworkState::Unknown => "unknown",
            };

            if let Err(e) = self.app_handle.emit("sync_mode_changed", mode) {
                warn!("[network_monitor] Failed to emit sync mode event: {}", e);
            }
        }

        Ok(new_status)
    }

    /// Perform connectivity check with retry logic
    async fn perform_connectivity_check(
        server_provider_service: &ServerProviderService,
        http_client: &tauri_plugin_http::reqwest::Client,
        retry_intervals: &[Duration],
    ) -> AppResult<NetworkStatus> {
        let _start_time = std::time::Instant::now();
        let mut status = NetworkStatus {
            last_check: Utc::now(),
            ..Default::default()
        };

        // First check basic internet connectivity
        let has_internet = Self::check_internet_connectivity(http_client).await;

        if !has_internet {
            status.state = NetworkState::Offline;
            return Ok(status);
        }

        // Check server reachability with retry logic
        let server_url = match server_provider_service.get_api_url().await {
            url => url,
        };

        let mut consecutive_failures = 0;
        let mut last_error = None;

        for (attempt, &retry_interval) in retry_intervals.iter().enumerate() {
            match Self::test_server_endpoint(http_client, &server_url).await {
                Ok(latency) => {
                    status.state = NetworkState::Online;
                    status.server_reachable = true;
                    status.quality.latency_ms = Some(latency);
                    status.quality.last_successful_ping = Some(Utc::now());
                    status.quality.consecutive_failures = 0;
                    status.quality.success_rate =
                        1.0 - (consecutive_failures as f32 / (attempt + 1) as f32);

                    debug!(
                        "[network_monitor] Server connectivity confirmed (attempt {}, latency: {}ms)",
                        attempt + 1,
                        latency
                    );
                    return Ok(status);
                }
                Err(e) => {
                    consecutive_failures += 1;
                    last_error = Some(e);

                    if attempt < retry_intervals.len() - 1 {
                        debug!(
                            "[network_monitor] Server connectivity failed (attempt {}), retrying in {:?}",
                            attempt + 1,
                            retry_interval
                        );
                        sleep(retry_interval).await;
                    }
                }
            }
        }

        // All retries failed
        status.state = NetworkState::Limited;
        status.server_reachable = false;
        status.quality.consecutive_failures = consecutive_failures;
        status.retry_count = consecutive_failures;

        if let Some(e) = last_error {
            warn!(
                "[network_monitor] Server unreachable after {} attempts: {}",
                consecutive_failures, e
            );
        }

        Ok(status)
    }

    /// Check basic internet connectivity using well-known endpoints
    async fn check_internet_connectivity(http_client: &tauri_plugin_http::reqwest::Client) -> bool {
        let test_endpoints = [
            "https://www.google.com",
            "https://www.cloudflare.com",
            "https://www.github.com",
        ];

        for endpoint in &test_endpoints {
            match http_client
                .head(*endpoint)
                .timeout(Duration::from_secs(5))
                .send()
                .await
            {
                Ok(response) if response.status().is_success() => {
                    debug!(
                        "[network_monitor] Internet connectivity confirmed via {}",
                        endpoint
                    );
                    return true;
                }
                Ok(_) => continue,
                Err(_) => continue,
            }
        }

        debug!("[network_monitor] No internet connectivity detected");
        false
    }

    /// Test server endpoint connectivity and measure latency
    async fn test_server_endpoint(
        http_client: &tauri_plugin_http::reqwest::Client,
        server_url: &str,
    ) -> AppResult<u32> {
        let start_time = std::time::Instant::now();

        // Test the /alive endpoint or fallback to HEAD request
        let test_url = if server_url.ends_with('/') {
            format!("{}alive", server_url)
        } else {
            format!("{}/alive", server_url)
        };

        let response = http_client
            .head(&test_url)
            .timeout(Duration::from_secs(10))
            .send()
            .await
            .map_err(|e| AppError::NetworkError {
                status: 0,
                message: format!("Server connectivity test failed: {}", e),
            })?;

        let latency = start_time.elapsed().as_millis() as u32;

        if response.status().is_success() || response.status().is_redirection() {
            Ok(latency)
        } else {
            Err(AppError::NetworkError {
                status: response.status().as_u16(),
                message: format!("Server returned status: {}", response.status()),
            })
        }
    }

    /// Check if currently online
    pub async fn is_online(&self) -> bool {
        let status = self.status.read().await;
        status.state == NetworkState::Online && status.server_reachable
    }

    /// Check if currently offline
    pub async fn is_offline(&self) -> bool {
        let status = self.status.read().await;
        matches!(status.state, NetworkState::Offline | NetworkState::Limited)
    }

    /// Get connection quality metrics
    pub async fn get_connection_quality(&self) -> ConnectionQuality {
        let status = self.status.read().await;
        status.quality.clone()
    }

    /// Set monitoring interval
    pub async fn set_check_interval(&mut self, interval: Duration) {
        self.check_interval = interval;
        info!("[network_monitor] Check interval updated to {:?}", interval);
    }

    /// Get current monitoring status
    pub async fn is_monitoring(&self) -> bool {
        *self.monitoring_enabled.read().await
    }
}
