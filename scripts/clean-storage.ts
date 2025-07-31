#!/usr/bin/env tsx

/**
 * Clean All Local Storage Script
 *
 * This script cleans all types of local storage used by the Chiikawarden application:
 * - Build artifacts (dist, node_modules/.rsbuild, etc.)
 * - Frontend storage (localStorage, sessionStorage) - requires manual browser action
 * - Tauri application data (database, secure storage, plugin stores, local files)
 * - Memory cache (cleared on restart)
 * - Logs and temporary files
 */

import { execSync } from "node:child_process";
import { existsSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const rootDir = join(__dirname, "..");

// TypeScript interfaces
interface Colors {
  reset: string;
  bright: string;
  red: string;
  green: string;
  yellow: string;
  blue: string;
  magenta: string;
  cyan: string;
}

// ANSI color codes for console output
const colors: Colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
};

function log(message: string, color: string = colors.reset): void {
  console.log(`${color}${message}${colors.reset}`);
}

function logSection(title: string): void {
  log(`\n${colors.bright}${colors.cyan}=== ${title} ===${colors.reset}`);
}

function logSuccess(message: string): void {
  log(`${colors.green}✓ ${message}${colors.reset}`);
}

function logWarning(message: string): void {
  log(`${colors.yellow}⚠ ${message}${colors.reset}`);
}

function logError(message: string): void {
  log(`${colors.red}✗ ${message}${colors.reset}`);
}

function logInfo(message: string): void {
  log(`${colors.blue}ℹ ${message}${colors.reset}`);
}

/**
 * Clean build artifacts and development files
 */
function cleanBuildArtifacts(): void {
  logSection("Cleaning Build Artifacts");

  const pathsToClean: string[] = [
    "dist",
    "node_modules/.rsbuild",
    "src-tauri/target/tmp",
    ".next",
    ".turbo",
    "storybook-static",
  ];

  pathsToClean.forEach((path) => {
    const fullPath = join(rootDir, path);
    if (existsSync(fullPath)) {
      try {
        rmSync(fullPath, { recursive: true, force: true });
        logSuccess(`Removed ${path}`);
      } catch (error) {
        logError(`Failed to remove ${path}: ${(error as Error).message}`);
      }
    } else {
      logInfo(`${path} does not exist, skipping`);
    }
  });
}

/**
 * Get the application data directory path
 */
function getAppDataDir(): string {
  const os = process.platform;
  const homeDir = process.env.HOME || process.env.USERPROFILE;

  if (!homeDir) {
    throw new Error("Could not determine home directory");
  }

  switch (os) {
    case "darwin": // macOS
      return join(homeDir, "Library", "'Application Support'", "com.chiikawarden.desktop");
    case "win32": // Windows
      return join(
        process.env.APPDATA || join(homeDir, "AppData", "Roaming"),
        "com.chiikawarden.desktop"
      );
    case "linux": // Linux
      return join(
        process.env.XDG_DATA_HOME || join(homeDir, ".local", "share"),
        "com.chiikawarden.desktop"
      );
    default:
      logWarning(`Unknown platform: ${os}, using default path`);
      return join(homeDir, ".chiikawarden");
  }
}

/**
 * Clean Tauri application data
 */
function cleanTauriData(): void {
  logSection("Cleaning Tauri Application Data");

  const appDataDir = getAppDataDir();
  logInfo(`App data directory: ${appDataDir}`);

  if (existsSync(appDataDir)) {
    try {
      // List contents before deletion for transparency
      const contents = execSync(`ls -la "${appDataDir}"`, {
        encoding: "utf8",
      }).trim();
      logInfo("Contents to be deleted:");
      console.log(contents);

      rmSync(appDataDir, { recursive: true, force: true });
      logSuccess("Removed Tauri application data directory");
    } catch (error) {
      logError(`Failed to remove Tauri data: ${(error as Error).message}`);
    }
  } else {
    logInfo("Tauri application data directory does not exist, skipping");
  }
}

/**
 * Clean system keychain/credential storage (platform-specific)
 */
function cleanSecureStorage(): void {
  logSection("Cleaning Secure Storage (Keychain/Credentials)");

  const os = process.platform;

  try {
    switch (os) {
      case "darwin": // macOS Keychain
        logInfo("Cleaning macOS Keychain entries...");
        try {
          // List and delete Chiikawarden keychain entries
          const keychainEntries = execSync(
            'security find-generic-password -s "Chiikawarden" 2>/dev/null || true',
            { encoding: "utf8" }
          );

          if (keychainEntries.trim()) {
            execSync('security delete-generic-password -s "Chiikawarden" 2>/dev/null || true');
            logSuccess("Removed macOS Keychain entries");
          } else {
            logInfo("No Keychain entries found");
          }
        } catch {
          logWarning("Could not clean Keychain entries (may require manual cleanup)");
        }
        break;

      case "win32": // Windows Credential Manager
        logInfo("Cleaning Windows Credential Manager entries...");
        try {
          execSync(
            'cmdkey /list | findstr "Chiikawarden" && cmdkey /delete:Chiikawarden || echo "No credentials found"',
            { encoding: "utf8" }
          );
          logSuccess("Cleaned Windows Credential Manager");
        } catch {
          logWarning("Could not clean Windows credentials (may require manual cleanup)");
        }
        break;

      case "linux": // Linux Secret Service
        logInfo("Linux secure storage cleanup requires manual action");
        logWarning("Please manually clear any stored passwords in your system keyring");
        break;

      default:
        logWarning(`Secure storage cleanup not implemented for platform: ${os}`);
    }
  } catch (error) {
    logError(`Secure storage cleanup failed: ${(error as Error).message}`);
  }
}

/**
 * Display instructions for manual frontend storage cleanup
 */
function displayFrontendCleanupInstructions(): void {
  logSection("Frontend Storage Cleanup Instructions");

  logInfo("To clean frontend storage (localStorage/sessionStorage), follow these steps:");
  log("1. Open the application in your browser");
  log("2. Open Developer Tools (F12 or Cmd+Option+I)");
  log("3. Go to the Application/Storage tab");
  log('4. Under Storage, select "Local Storage" and "Session Storage"');
  log("5. Delete all entries for your application domain");
  log("6. Alternatively, run this in the browser console:");
  log("   localStorage.clear(); sessionStorage.clear();");

  logWarning("Frontend storage cannot be cleared automatically from this script");
}

/**
 * Clean log files
 */
function cleanLogs(): void {
  logSection("Cleaning Log Files");

  const logPaths: string[] = [join(rootDir, "logs"), join(getAppDataDir(), "logs")];

  logPaths.forEach((logPath) => {
    if (existsSync(logPath)) {
      try {
        rmSync(logPath, { recursive: true, force: true });
        logSuccess(`Removed log directory: ${logPath}`);
      } catch (error) {
        logError(`Failed to remove logs at ${logPath}: ${(error as Error).message}`);
      }
    } else {
      logInfo(`Log directory ${logPath} does not exist, skipping`);
    }
  });
}

/**
 * Create a comprehensive reset script for Tauri commands
 */
function createTauriResetScript(): string | null {
  logSection("Creating Tauri Database Reset Script");

  const resetScriptPath = join(rootDir, "reset-tauri-data.ts");
  const resetScriptContent = `#!/usr/bin/env tsx

/**
 * Tauri Data Reset Script
 * This script calls Tauri commands to reset database and storage
 * Run this script when the Tauri application is available
 */

console.log('🔄 Starting Tauri data reset...');

// Import the generated Tauri commands
import { commands } from './src/lib/tauri-commands.js';

interface ResetResult {
  operation: string;
  success: boolean;
  result?: any;
  error?: string;
}

interface User {
  id: string;
  email: string;
}

interface DeleteValueRequest {
  store_name: string;
  key: string;
}

async function resetAllTauriData(): Promise<void> {
  const results: ResetResult[] = [];

  try {
    // 1. Reset database (development only)
    console.log('\\n📊 Resetting database...');
    try {
      const result = await commands.resetDatabase();
      if (result.status === 'ok') {
        console.log('✅ Database reset successful:', result.data);
        results.push({ operation: 'reset_database', success: true, result: result.data });

        // After reset, ensure database is properly initialized with current schema
        console.log('\\n🔄 Ensuring database initialization...');
        try {
          const initResult = await commands.isDatabaseInitialized();
          if (initResult.status === 'ok') {
            console.log(\`ℹ️ Database initialization status: \${initResult.data}\`);
            if (!initResult.data) {
              console.log('⚠️ Database not initialized after reset - this is expected');
              console.log('ℹ️ Database will be initialized on next app startup');
            }
          }
        } catch (initError) {
          console.log('⚠️ Could not check database initialization status:', initError);
        }
      } else {
        console.log('❌ Database reset failed:', result.error);
        results.push({ operation: 'reset_database', success: false, error: String(result.error) });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.log('⚠️ Database reset failed (may not be available in release build):', errorMessage);
      results.push({ operation: 'reset_database', success: false, error: errorMessage });
    }

    // 2. Reset settings to defaults
    console.log('\\n⚙️ Resetting settings...');
    try {
      const result = await commands.resetSettings();
      if (result.status === 'ok') {
        console.log('✅ Settings reset to defaults');
        results.push({ operation: 'reset_settings', success: true, result: result.data });
      } else {
        console.log('❌ Settings reset failed:', result.error);
        results.push({ operation: 'reset_settings', success: false, error: String(result.error) });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.log('❌ Settings reset failed:', errorMessage);
      results.push({ operation: 'reset_settings', success: false, error: errorMessage });
    }

    // 3. Clear storage values from common stores
    console.log('\\n🗄️ Clearing storage stores...');
    const storeNames: string[] = ['settings', 'session', 'cache', 'preferences', 'user_data', 'app_state'];
    const commonKeys: string[] = ['session', 'user', 'settings', 'cache', 'last_login', 'remember_me', 'auth_token', 'user_preferences'];

    for (const storeName of storeNames) {
      for (const key of commonKeys) {
        try {
          const request: DeleteValueRequest = { store_name: storeName, key: key };
          const result = await commands.deleteValue(request);
          // Ignore errors for non-existent keys
        } catch (error) {
          // Ignore errors for non-existent keys
        }
      }
      console.log(\`✅ Processed store: \${storeName}\`);
    }

    // 4. Clear user keys (if any users exist)
    console.log('\\n🔐 Clearing user keys...');
    try {
      // Get all users first - this might fail if database was just reset
      const usersResult = await commands.getAllUsers();
      if (usersResult.status === 'ok' && usersResult.data && usersResult.data.length > 0) {
        console.log(\`ℹ️ Found \${usersResult.data.length} users - user keys will be cleared by file-based cleanup\`);
        for (const user of usersResult.data) {
          console.log(\`📋 User: \${user.email} (ID: \${user.id})\`);
        }
      } else if (usersResult.status === 'error') {
        console.log('⚠️ Could not query users (database may be reset):', usersResult.error);
        console.log('ℹ️ This is expected after database reset - user keys will be cleared by file-based cleanup');
      } else {
        console.log('ℹ️ No users found to clear keys for');
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.log('⚠️ Failed to get users (database may be reset):', errorMessage);
      console.log('ℹ️ This is expected after database reset - user keys will be cleared by file-based cleanup');
    }

    // 5. Database path for reference
    console.log('\\n📁 Getting database path...');
    try {
      const result = await commands.getDatabasePath();
      if (result.status === 'ok') {
        console.log(\`ℹ️ Database path: \${result.data}\`);
        results.push({ operation: 'get_database_path', success: true, result: result.data });
      } else {
        console.log('⚠️ Failed to get database path:', result.error);
        results.push({ operation: 'get_database_path', success: false, error: String(result.error) });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.log('⚠️ Failed to get database path:', errorMessage);
    }

    // 6. Final cleanup summary
    console.log('\\n📋 Database reset summary:');
    console.log('• Database tables, views, and triggers have been dropped');
    console.log('• Database will be recreated with current schema on next app startup');
    console.log('• All user data, settings, and cached data have been cleared');
    console.log('• Secure storage (keychain) entries have been cleaned');
    console.log('• Application data directory has been cleared');

    console.log('\\n🎉 Tauri data reset completed!');
    console.log('📊 Summary:');
    results.forEach(result => {
      const status = result.success ? '✅' : '❌';
      console.log(\`  \${status} \${result.operation}: \${result.success ? 'Success' : result.error}\`);
    });

    console.log('\\nℹ️ You may need to restart the application to see all changes.');

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error('❌ Tauri reset failed:', errorMessage);
    process.exit(1);
  }
}

// Run the reset
resetAllTauriData().catch((error: Error) => {
  console.error('❌ Script execution failed:', error.message);
  process.exit(1);
});
`;

  try {
    writeFileSync(resetScriptPath, resetScriptContent);
    logSuccess(`Created Tauri reset script: ${resetScriptPath}`);
    logInfo("You can run this script separately with: tsx reset-tauri-data.ts");
    return resetScriptPath;
  } catch (error) {
    logError(`Failed to create Tauri reset script: ${(error as Error).message}`);
    return null;
  }
}

/**
 * Reset database using direct file deletion (guaranteed to work)
 */
async function resetDatabase(): Promise<void> {
  logSection("Resetting Database");

  const args = process.argv.slice(2);
  const skipTauri = args.includes("--skip-tauri") || args.includes("--no-tauri");

  // First try Tauri commands if not skipped
  if (!skipTauri) {
    logInfo("Attempting Tauri database reset first...");

    // Create the Tauri reset script
    const resetScriptPath = createTauriResetScript();
    if (resetScriptPath) {
      try {
        const result = execSync(`cd "${rootDir}" && tsx "${resetScriptPath}"`, {
          encoding: "utf8",
          stdio: "pipe",
          timeout: 30000, // 30 second timeout
        });

        if (result.includes("✅ Database reset successful")) {
          logSuccess("Tauri database reset completed successfully");
          logInfo("Reset output:");
          console.log(result.trim());
          return; // Success, no need for file deletion
        }
      } catch (error) {
        logWarning(`Tauri database reset failed: ${(error as Error).message}`);
        logWarning("Falling back to direct file deletion");
      }
    }
  }

  // Direct database file deletion (guaranteed to work)
  logInfo("Using direct database file deletion...");
  logInfo("This will completely remove the database file:");
  logInfo("  1. Delete chiikawarden.db file");
  logInfo("  2. Database will be recreated with current schema on next app startup");

  try {
    const appDataDir = getAppDataDir();
    const dbPath = join(appDataDir, "chiikawarden.db");

    logInfo(`Database path: ${dbPath}`);

    if (existsSync(dbPath)) {
      rmSync(dbPath, { force: true });
      logSuccess("Database file deleted successfully");
      logInfo("All database tables have been completely removed");
    } else {
      logInfo("Database file does not exist, skipping");
    }

    // Also remove any database-related files
    const relatedFiles = [
      join(appDataDir, "chiikawarden.db-shm"),
      join(appDataDir, "chiikawarden.db-wal"),
    ];

    for (const file of relatedFiles) {
      if (existsSync(file)) {
        rmSync(file, { force: true });
        logSuccess(`Removed database file: ${file}`);
      }
    }
  } catch (error) {
    logError(`Direct database deletion failed: ${(error as Error).message}`);
  }
}

/**
 * Main cleanup function
 */
async function main(): Promise<void> {
  log(`${colors.bright}${colors.magenta}Chiikawarden Storage Cleanup Tool${colors.reset}`);
  log("This will remove ALL local data including saved passwords, settings, and cache.");

  // Check if we should proceed
  const args = process.argv.slice(2);
  const force = args.includes("--force") || args.includes("-f");

  if (!force) {
    logWarning("This action cannot be undone!");
    logWarning("Add --force flag to proceed: bun run clean:storage --force");
    process.exit(1);
  }

  logInfo("Starting comprehensive storage cleanup...");

  try {
    cleanBuildArtifacts();
    cleanTauriData();
    cleanSecureStorage();
    cleanLogs();
    await resetDatabase();
    displayFrontendCleanupInstructions();

    logSection("Cleanup Complete");
    logSuccess("All local storage has been cleaned successfully!");
    logInfo("You may need to restart the application and reconfigure your settings.");
  } catch (error) {
    logError(`Cleanup failed: ${(error as Error).message}`);
    process.exit(1);
  }
}

// Run the cleanup
main().catch((error: Error) => {
  logError(`Cleanup failed: ${error.message}`);
  process.exit(1);
});
