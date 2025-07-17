# Development Guide

## Git Hooks with Lefthook

This project uses [Lefthook](https://github.com/evilmartians/lefthook) for managing git hooks, which replaces the need for lint-staged and provides better performance and configuration.

### Setup

```bash
# Install lefthook hooks
bun run hooks:install

# Or manually
lefthook install
```

### Available Commands

```bash
# Run pre-commit hooks manually
bun run hooks:run

# Run pre-push hooks manually  
bun run hooks:test

# Uninstall hooks
bun run hooks:uninstall
```

### Pre-commit Hooks

The following checks run automatically on `git commit`:

- **Frontend Linting**: Biome check with auto-fix for JS/TS files
- **Frontend Formatting**: Biome format for JS/TS/JSON/MD files
- **TypeScript**: Type checking
- **Rust Formatting**: `cargo fmt --check` in src-tauri/
- **Rust Linting**: `cargo clippy` with warnings as errors
- **Rust Tests**: `cargo test --all`

### Pre-push Hooks

The following checks run automatically on `git push`:

- **Frontend Tests**: Full test suite
- **Build Check**: Production build verification
- **Rust Build**: Release build check

### Configuration

All git hook configuration is in `lefthook.yml`. The hooks run in parallel for better performance.

### Benefits over lint-staged

1. **Native Git Integration**: Direct git hook management
2. **Better Performance**: Parallel execution by default
3. **More Features**: Pre-push hooks, better glob patterns, conditional execution
4. **Single Tool**: No need for husky + lint-staged combination
5. **Better Error Handling**: More informative error messages

### Skipping Hooks

```bash
# Skip pre-commit hooks
git commit --no-verify

# Skip pre-push hooks  
git push --no-verify

# Skip specific hook
LEFTHOOK_EXCLUDE=frontend-lint git commit
``` 