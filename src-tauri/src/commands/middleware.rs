use crate::app_state::AppState;
use crate::error::AppError;
use serde::{Deserialize, Serialize};
use std::time::Instant;
use tauri::{command, State};

/// Command execution context for middleware
#[derive(Debug)]
pub struct CommandContext {
    pub command_name: &'static str,
    pub start_time: Instant,
    pub user_id: Option<String>,
}

impl CommandContext {
    pub fn new(command_name: &'static str) -> Self {
        Self {
            command_name,
            start_time: Instant::now(),
            user_id: None,
        }
    }

    pub fn with_user_id(mut self, user_id: String) -> Self {
        self.user_id = Some(user_id);
        self
    }

    pub fn elapsed(&self) -> std::time::Duration {
        self.start_time.elapsed()
    }
}

/// Middleware trait for command processing
pub trait CommandMiddleware {
    fn before_execute(&self, ctx: &CommandContext) -> Result<(), AppError>;
    fn after_execute(
        &self,
        ctx: &CommandContext,
        result: &Result<(), AppError>,
    ) -> Result<(), AppError>;
}

/// Authentication middleware - ensures user is authenticated
pub struct AuthMiddleware;

impl CommandMiddleware for AuthMiddleware {
    fn before_execute(&self, ctx: &CommandContext) -> Result<(), AppError> {
        // Check if user is authenticated for protected commands
        if ctx.user_id.is_none() {
            return Err(AppError::Unauthorized("User not authenticated".to_string()));
        }
        Ok(())
    }

    fn after_execute(
        &self,
        _ctx: &CommandContext,
        _result: &Result<(), AppError>,
    ) -> Result<(), AppError> {
        Ok(())
    }
}

/// Rate limiting middleware
pub struct RateLimitMiddleware {
    max_requests_per_minute: u32,
}

impl RateLimitMiddleware {
    pub fn new(max_requests_per_minute: u32) -> Self {
        Self {
            max_requests_per_minute,
        }
    }
}

impl CommandMiddleware for RateLimitMiddleware {
    fn before_execute(&self, ctx: &CommandContext) -> Result<(), AppError> {
        // In a real implementation, you would track request counts per user/IP
        // This is a simplified example
        println!(
            "Rate limiting check for command: {} (max: {} req/min)",
            ctx.command_name, self.max_requests_per_minute
        );
        Ok(())
    }

    fn after_execute(
        &self,
        _ctx: &CommandContext,
        _result: &Result<(), AppError>,
    ) -> Result<(), AppError> {
        Ok(())
    }
}

/// Command wrapper that applies middleware
pub struct CommandWrapper {
    middlewares: Vec<Box<dyn CommandMiddleware + Send + Sync>>,
}

impl CommandWrapper {
    pub fn new() -> Self {
        Self {
            middlewares: Vec::new(),
        }
    }

    pub fn with_middleware(mut self, middleware: Box<dyn CommandMiddleware + Send + Sync>) -> Self {
        self.middlewares.push(middleware);
        self
    }

    pub async fn execute<F, T, E>(
        &self,
        command_name: &'static str,
        user_id: Option<String>,
        command_fn: F,
    ) -> Result<T, AppError>
    where
        F: FnOnce() -> Result<T, E>,
        E: Into<AppError>,
    {
        let mut ctx = CommandContext::new(command_name);
        if let Some(uid) = user_id {
            ctx = ctx.with_user_id(uid);
        }

        // Execute before middleware
        for middleware in &self.middlewares {
            middleware.before_execute(&ctx)?;
        }

        // Execute the actual command
        let result = command_fn().map_err(|e| e.into());

        // Execute after middleware
        let middleware_result = result.as_ref().map(|_| ()).map_err(|e| e.clone());
        for middleware in &self.middlewares {
            middleware.after_execute(&ctx, &middleware_result)?;
        }

        result
    }
}

/// Default command wrapper with common middleware
pub fn create_default_wrapper() -> CommandWrapper {
    CommandWrapper::new()
        .with_middleware(Box::new(PerformanceMiddleware))
        .with_middleware(Box::new(RateLimitMiddleware::new(60)))
}

/// Protected command wrapper (requires authentication)
pub fn create_protected_wrapper() -> CommandWrapper {
    CommandWrapper::new()
        .with_middleware(Box::new(AuthMiddleware))
        .with_middleware(Box::new(PerformanceMiddleware))
        .with_middleware(Box::new(RateLimitMiddleware::new(60)))
}

/// Macro to create a command with middleware
#[macro_export]
macro_rules! protected_command {
    ($name:ident, $handler:expr) => {
        #[tauri::command]
        pub async fn $name(
            state: State<'_, AppState>,
            // Add other parameters as needed
        ) -> Result<impl Serialize, String> {
            let wrapper = create_protected_wrapper();
            wrapper
                .execute(stringify!($name), None, || $handler(state))
                .await
                .map_err(|e| e.to_string())
        }
    };
}

/// Example usage of the middleware system
#[derive(Serialize, Deserialize)]
pub struct ExampleResponse {
    pub message: String,
}

#[command]
pub async fn example_protected_command(
    state: State<'_, AppState>,
) -> Result<ExampleResponse, String> {
    let wrapper = create_protected_wrapper();

    wrapper
        .execute("example_protected_command", None, || {
            // Your actual command logic here
            Ok(ExampleResponse {
                message: "Command executed successfully".to_string(),
            })
        })
        .await
        .map_err(|e| e.to_string())
}

#[command]
pub async fn example_public_command() -> Result<ExampleResponse, String> {
    let wrapper = create_default_wrapper();

    wrapper
        .execute("example_public_command", None, || {
            // Your actual command logic here
            Ok(ExampleResponse {
                message: "Public command executed".to_string(),
            })
        })
        .await
        .map_err(|e| e.to_string())
}
