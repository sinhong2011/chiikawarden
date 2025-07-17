# JavaScript Fetch to Rust Reqwest Conversion Guide

## Overview

This guide provides patterns for converting JavaScript `fetch()` API calls to Rust `reqwest` implementations for the Bitwarden Tauri desktop client.

## Basic Conversion Patterns

### 1. Simple GET Request

#### ❌ JavaScript (Before)
```typescript
async function getData(): Promise<ResponseType> {
  const response = await fetch('/api/endpoint', {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    }
  });

  if (!response.ok) {
    throw new Error('Request failed');
  }

  return response.json();
}
```

#### ✅ Rust (After)
```rust
use reqwest::Client;
use serde::Deserialize;

#[derive(Deserialize)]
struct ResponseType {
    // Define your response structure
}

async fn get_data(access_token: &str) -> Result<ResponseType, reqwest::Error> {
    let client = Client::new();
    
    let response = client
        .get("https://api.bitwarden.com/api/endpoint")
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    response.json::<ResponseType>().await
}
```

### 2. POST Request with JSON Body

#### ❌ JavaScript (Before)
```typescript
async function postData(data: RequestType): Promise<ResponseType> {
  const response = await fetch('/api/endpoint', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(data)
  });

  if (!response.ok) {
    throw new Error('Request failed');
  }

  return response.json();
}
```

#### ✅ Rust (After)
```rust
use reqwest::Client;
use serde::{Serialize, Deserialize};

#[derive(Serialize)]
struct RequestType {
    // Define your request structure
}

#[derive(Deserialize)]
struct ResponseType {
    // Define your response structure
}

async fn post_data(
    data: RequestType, 
    access_token: &str
) -> Result<ResponseType, reqwest::Error> {
    let client = Client::new();
    
    let response = client
        .post("https://api.bitwarden.com/api/endpoint")
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .json(&data)
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    response.json::<ResponseType>().await
}
```

### 3. Form Data Request

#### ❌ JavaScript (Before)
```typescript
async function postForm(formData: FormData): Promise<ResponseType> {
  const response = await fetch('/api/endpoint', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`
    },
    body: formData
  });

  if (!response.ok) {
    throw new Error('Request failed');
  }

  return response.json();
}
```

#### ✅ Rust (After)
```rust
use reqwest::{Client, multipart};

async fn post_form(
    form_data: multipart::Form,
    access_token: &str
) -> Result<ResponseType, reqwest::Error> {
    let client = Client::new();
    
    let response = client
        .post("https://api.bitwarden.com/api/endpoint")
        .header("Authorization", format!("Bearer {}", access_token))
        .multipart(form_data)
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    response.json::<ResponseType>().await
}
```

### 4. URL-Encoded Form Request

#### ❌ JavaScript (Before)
```typescript
async function postUrlEncoded(params: Record<string, string>): Promise<ResponseType> {
  const formData = new URLSearchParams(params);
  
  const response = await fetch('/api/endpoint', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: formData.toString()
  });

  if (!response.ok) {
    throw new Error('Request failed');
  }

  return response.json();
}
```

#### ✅ Rust (After)
```rust
use reqwest::Client;
use std::collections::HashMap;

async fn post_url_encoded(
    params: HashMap<String, String>
) -> Result<ResponseType, reqwest::Error> {
    let client = Client::new();
    
    let response = client
        .post("https://api.bitwarden.com/api/endpoint")
        .header("Content-Type", "application/x-www-form-urlencoded")
        .form(&params)
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    response.json::<ResponseType>().await
}
```

### 5. Binary Data Download

#### ❌ JavaScript (Before)
```typescript
async function downloadBinary(): Promise<ArrayBuffer> {
  const response = await fetch('/api/download', {
    headers: {
      'Authorization': `Bearer ${accessToken}`
    }
  });

  if (!response.ok) {
    throw new Error('Download failed');
  }

  return response.arrayBuffer();
}
```

#### ✅ Rust (After)
```rust
use reqwest::Client;
use bytes::Bytes;

async fn download_binary(access_token: &str) -> Result<Bytes, reqwest::Error> {
    let client = Client::new();
    
    let response = client
        .get("https://api.bitwarden.com/api/download")
        .header("Authorization", format!("Bearer {}", access_token))
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(reqwest::Error::from(response.error_for_status().unwrap_err()));
    }

    response.bytes().await
}
```

## Error Handling Patterns

### Enhanced Error Handling

```rust
use reqwest::{Client, StatusCode};
use serde::Deserialize;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ApiError {
    #[error("HTTP request failed: {0}")]
    Request(#[from] reqwest::Error),
    
    #[error("Not found")]
    NotFound,
    
    #[error("Unauthorized")]
    Unauthorized,
    
    #[error("Server error: {status}")]
    ServerError { status: u16 },
    
    #[error("Client error: {status}")]
    ClientError { status: u16 },
}

async fn api_request_with_error_handling(
    access_token: &str
) -> Result<ResponseType, ApiError> {
    let client = Client::new();
    
    let response = client
        .get("https://api.bitwarden.com/api/endpoint")
        .header("Authorization", format!("Bearer {}", access_token))
        .send()
        .await?;

    match response.status() {
        StatusCode::OK => {
            Ok(response.json::<ResponseType>().await?)
        }
        StatusCode::NOT_FOUND => Err(ApiError::NotFound),
        StatusCode::UNAUTHORIZED => Err(ApiError::Unauthorized),
        status if status.is_server_error() => {
            Err(ApiError::ServerError { status: status.as_u16() })
        }
        status if status.is_client_error() => {
            Err(ApiError::ClientError { status: status.as_u16() })
        }
        _ => Err(ApiError::Request(response.error_for_status().unwrap_err()))
    }
}
```

## Key Differences Summary

| JavaScript `fetch()` | Rust `reqwest` | Notes |
|---------------------|----------------|-------|
| `fetch(url, options)` | `client.get(url).send().await` | Method chaining |
| `response.json()` | `response.json::<T>().await` | Type-safe deserialization |
| `response.ok` | `response.status().is_success()` | Status checking |
| `JSON.stringify(data)` | `.json(&data)` | Automatic serialization |
| `new URLSearchParams()` | `.form(&params)` | Form encoding |
| `response.arrayBuffer()` | `response.bytes().await` | Binary data |
| Manual error handling | `?` operator + `Result<T, E>` | Rust error handling |

## Best Practices

1. **Always use type-safe deserialization** with `serde`
2. **Handle errors properly** with `Result<T, E>` types
3. **Use the `?` operator** for error propagation
4. **Define clear error types** with `thiserror`
5. **Reuse HTTP clients** for better performance
6. **Use appropriate timeouts** for production code
7. **Implement retry logic** for critical operations

This conversion ensures all API calls are secure, type-safe, and follow Rust best practices.
