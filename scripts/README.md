# Chiikawarden Storage Cleanup Scripts

This directory contains utility scripts for managing and cleaning various types of storage used by the Chiikawarden application.

## Available Scripts

### `clean-storage.ts`

A comprehensive TypeScript storage cleanup script that removes all local data stored by the application. Uses `tsx` for execution with full type safety.

### `reset-tauri-data.ts` (Auto-generated)

A standalone TypeScript script created by `clean-storage.ts` that specifically handles Tauri command-based resets. This script can be run independently when the Tauri application is available and includes proper TypeScript interfaces for type safety.

## Requirements

- **Node.js**: Required for script execution
- **tsx**: TypeScript execution engine (installed as dev dependency)
- **@types/node**: Node.js type definitions (installed as dev dependency)

The scripts use `tsx` for direct TypeScript execution without compilation step.

#### Usage

```bash
# Show what would be cleaned (dry run)
bun run clean:storage

# Actually perform the cleanup (requires --force flag)
bun run clean:storage --force

# Clean both build artifacts and storage
bun run clean:all

# Run the generated Tauri reset script separately
tsx reset-tauri-data.ts

# Skip Tauri database reset (file cleanup only)
bun run clean:storage --force --skip-tauri
```

#### What Gets Cleaned

1. **Build Artifacts**
   - `dist/` - Production build output
   - `node_modules/.rsbuild/` - RSBuild cache
   - `src-tauri/target/debug/` - Rust debug builds
   - `src-tauri/target/release/` - Rust release builds
   - `src-tauri/target/tmp/` - Temporary build files
   - `storybook-static/` - Storybook build output

2. **Tauri Application Data**
   - SQLite database (`chiikawarden.db`)
   - Tauri plugin store files (`.json` stores)
   - Local data files (non-sensitive cached data)
   - Application configuration files
   - Location varies by platform:
     - **macOS**: `~/Library/Application Support/Chiikawarden/`
     - **Windows**: `%APPDATA%\Chiikawarden\`
     - **Linux**: `~/.local/share/Chiikawarden/`

3. **Secure Storage** (Platform-specific)
   - **macOS**: Keychain entries for stored passwords/keys
   - **Windows**: Windows Credential Manager entries
   - **Linux**: Manual cleanup required for system keyring

4. **Log Files**
   - Application log files
   - Debug logs
   - Error logs

5. **Database Reset** (via Tauri commands)
   - Complete database reset (development builds only)
   - Settings reset to defaults
   - Storage store cleanup (settings, session, cache, etc.)
   - User key clearing for all registered users
   - Creates a standalone `reset-tauri-data.ts` script for manual execution

6. **Frontend Storage** (Manual cleanup required)
   - Browser localStorage
   - Browser sessionStorage
   - IndexedDB (if used)

#### Safety Features

- **Requires `--force` flag**: Prevents accidental data loss
- **TypeScript type safety**: Full type checking and interfaces
- **Detailed logging**: Shows exactly what is being cleaned
- **Platform detection**: Handles different OS storage locations
- **Error handling**: Continues cleanup even if some operations fail
- **Dry run mode**: Shows what would be cleaned without the `--force` flag
- **Modular execution**: Can skip Tauri commands with `--skip-tauri` flag

#### Example Output

```
=== Chiikawarden Storage Cleanup Tool ===
This will remove ALL local data including saved passwords, settings, and cache.

=== Cleaning Build Artifacts ===
✓ Removed dist
✓ Removed node_modules/.rsbuild
ℹ src-tauri/target/debug does not exist, skipping

=== Cleaning Tauri Application Data ===
ℹ App data directory: /Users/username/Library/Application Support/Chiikawarden
ℹ Contents to be deleted:
total 1024
-rw-r--r--  1 user  staff  524288 Jan 15 10:30 chiikawarden.db
-rw-r--r--  1 user  staff    1024 Jan 15 10:30 settings.json
✓ Removed Tauri application data directory

=== Cleaning Secure Storage (Keychain/Credentials) ===
ℹ Cleaning macOS Keychain entries...
✓ Removed macOS Keychain entries

=== Frontend Storage Cleanup Instructions ===
ℹ To clean frontend storage (localStorage/sessionStorage), follow these steps:
1. Open the application in your browser
2. Open Developer Tools (F12 or Cmd+Option+I)
...

=== Cleanup Complete ===
✓ All local storage has been cleaned successfully!
ℹ You may need to restart the application and reconfigure your settings.
```

## Package.json Scripts

The following scripts are available in the main `package.json`:

- `bun run clean:storage` - Run storage cleanup (requires --force)
- `bun run clean:all` - Clean both build artifacts and storage
- `bun run clean` - Clean only build artifacts (existing script)

## Important Notes

⚠️ **Data Loss Warning**: These scripts will permanently delete all application data including:
- Saved passwords and secure notes
- User settings and preferences
- Cached data and session information
- Authentication tokens and keys

⚠️ **Backup Recommendation**: Consider backing up important data before running cleanup scripts.

⚠️ **Manual Steps Required**: Some storage types (browser storage, system keyring on Linux) require manual cleanup steps.

## Development vs Production

- The cleanup script works in both development and production environments
- Some Tauri commands (like `reset_database`) are only available in debug builds
- The script handles missing directories gracefully

## Troubleshooting

### Permission Errors
If you encounter permission errors:
- On macOS/Linux: You may need to run with elevated permissions for keychain access
- On Windows: Run as administrator if credential manager access fails

### Partial Cleanup
If some cleanup operations fail:
- The script continues with remaining operations
- Check the error messages for specific issues
- Some failures (like missing directories) are expected and safe to ignore

### Platform-Specific Issues
- **macOS**: Keychain access may require user confirmation
- **Windows**: Credential Manager operations may require administrator rights
- **Linux**: Secure storage cleanup requires manual intervention
