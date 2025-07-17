# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Chiikawarden is a modern password manager desktop application built with Tauri (Rust backend) and SolidJS (frontend). It provides Bitwarden API compatibility with enhanced security features including Stronghold secure storage and biometric authentication.

## Development Commands

### Primary Development Commands
- `bun run dev` - Start Tauri development server with hot reload
- `bun run build` - Build production application
- `bun run dev:ui` - Start frontend-only development server
- `bun run build:ui` - Build frontend assets only

### Testing Commands
- `bun run test` - Run unit tests with Vitest
- `bun run test:ui` - Run tests with Vitest UI
- `bun run test:e2e` - Run end-to-end tests

### Code Quality Commands
- `bun run lint` - Check code quality with Biome
- `bun run lint:fix` - Fix linting issues automatically
- `bun run format` - Format code with Biome
- `bun run typecheck` - Run TypeScript type checking
- `bun run check` - Run all quality checks (lint + format + type)
- `bun run check:fix` - Fix all quality issues automatically

### Debug Commands
- `bun run dev:debug` - Start development with Rust debug logging
- `bun run build:debug` - Build with debug symbols

### Git Hooks
- `bun run hooks:install` - Install Lefthook git hooks
- `bun run hooks:run` - Run pre-commit hooks manually
- `bun run hooks:test` - Run pre-push hooks manually

## Architecture Overview

### Frontend Architecture (SolidJS)
- **Routing**: TanStack Router with file-based routing and type safety
- **State Management**: Hybrid approach using SolidJS stores + TanStack Query
- **UI Framework**: TailwindCSS with custom design system
- **Type Safety**: Full TypeScript with generated types from Rust backend
- **Internationalization**: Paraglide for type-safe i18n

### Backend Architecture (Rust/Tauri)
- **Framework**: Tauri 2.0 with extensive plugin ecosystem
- **Storage**: Multi-layered approach:
  - Stronghold for sensitive data (keys, passwords)
  - SQLite for structured data (ciphers, folders)
  - Memory cache for runtime performance
- **Crypto**: Custom cryptographic services with:
  - AES-256-CBC encryption
  - Argon2/PBKDF2 key derivation
  - Biometric authentication support
- **API**: Bitwarden API compatibility layer
- **Commands**: Tauri commands with TypeScript type generation

### Key Patterns
1. **Command Pattern**: Tauri commands expose backend functionality to frontend
2. **Service Layer**: Business logic separated from data access
3. **Repository Pattern**: Data access abstraction for database and API
4. **Error Handling**: Comprehensive error types with retry logic
5. **Type Safety**: Full TypeScript generation via tauri-specta

## File Structure

### Frontend (`/src`)
- `/routes` - File-based routing structure
- `/components` - Reusable UI components
- `/services` - API integration services
- `/stores` - SolidJS state management
- `/types` - TypeScript type definitions
- `/lib` - Utility functions and configurations

### Backend (`/src-tauri/src`)
- `/commands` - Tauri command handlers
- `/services` - Business logic services
- `/storage` - Multi-layered storage implementation
- `/crypto` - Cryptographic services
- `/api` - External API integration
- `/models` - Data models and types

## Development Notes

### Type Generation
- TypeScript types are automatically generated from Rust code
- Generated types are in `src/lib/tauri-commands.ts`
- Never edit generated files manually
- Use `#[specta::specta]` annotation on Rust types for generation

### Database
- SQLite with SQLx for type-safe queries
- Migrations in `src-tauri/migrations/`
- Use `sqlx migrate run` to apply migrations

### Security Considerations
- Never store sensitive data in plain text
- Use Stronghold for keys and passwords
- Implement proper memory clearing with zeroize
- Follow cryptographic best practices

### Testing
- **Primary Testing Strategy**: Use Storybook for all unit testing and component testing
- **Frontend Component Tests**: Write Storybook stories with interactions and tests
- **Unit Tests**: Implement tests within Storybook using play functions and assertions
- **Backend Tests**: Use standard Rust testing framework
- **Integration Tests**: Use Vitest with SolidJS Testing Library for complex integration scenarios
- Mock Tauri APIs in tests using provided utilities
- Maintain 80%+ test coverage
- **Testing Priority**: Storybook stories > Unit tests > Integration tests

### Internationalization
- Messages in `/messages` directory
- Use `m()` function for type-safe message access
- Support for English, Chinese (Simplified, Traditional, Hong Kong)

## Common Tasks

### Adding New Commands
1. Create command function in appropriate `/commands` module
2. Add `#[tauri::command]` and `#[specta::specta]` annotations
3. Register command in `lib.rs`
4. Use generated types in frontend service

### Adding New Routes
1. Create new file in `/routes` directory
2. Route structure mirrors URL structure
3. Use `createFileRoute` from TanStack Router
4. Add necessary loaders and actions

### Database Changes
1. Create new migration file in `src-tauri/migrations/`
2. Update relevant models in `src-tauri/src/models/`
3. Update queries in `src-tauri/src/storage/database/queries.rs`

## Performance Considerations
- Use TanStack Query for server state caching
- Implement optimistic updates for better UX
- Use memory cache for frequently accessed data
- Avoid blocking operations in main thread
- Use proper indexing for database queries

## Security Best Practices
- All sensitive data must be encrypted at rest
- Use secure memory management (zeroize)
- Implement proper session management
- Follow OWASP security guidelines
- Regular security audits and dependency updates