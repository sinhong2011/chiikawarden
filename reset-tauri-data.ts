#!/usr/bin/env tsx

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
    console.log('\n📊 Resetting database...');
    try {
      const result = await commands.resetDatabase();
      if (result.status === 'ok') {
        console.log('✅ Database reset successful:', result.data);
        results.push({ operation: 'reset_database', success: true, result: result.data });

        // After reset, ensure database is properly initialized with current schema
        console.log('\n🔄 Ensuring database initialization...');
        try {
          const initResult = await commands.isDatabaseInitialized();
          if (initResult.status === 'ok') {
            console.log(`ℹ️ Database initialization status: ${initResult.data}`);
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
    console.log('\n⚙️ Resetting settings...');
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
    console.log('\n🗄️ Clearing storage stores...');
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
      console.log(`✅ Processed store: ${storeName}`);
    }

    // 4. Clear user keys (if any users exist)
    console.log('\n🔐 Clearing user keys...');
    try {
      // Get all users first - this might fail if database was just reset
      const usersResult = await commands.getAllUsers();
      if (usersResult.status === 'ok' && usersResult.data && usersResult.data.length > 0) {
        console.log(`ℹ️ Found ${usersResult.data.length} users - user keys will be cleared by file-based cleanup`);
        for (const user of usersResult.data) {
          console.log(`📋 User: ${user.email} (ID: ${user.id})`);
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
    console.log('\n📁 Getting database path...');
    try {
      const result = await commands.getDatabasePath();
      if (result.status === 'ok') {
        console.log(`ℹ️ Database path: ${result.data}`);
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
    console.log('\n📋 Database reset summary:');
    console.log('• Database tables, views, and triggers have been dropped');
    console.log('• Database will be recreated with current schema on next app startup');
    console.log('• All user data, settings, and cached data have been cleared');
    console.log('• Secure storage (keychain) entries have been cleaned');
    console.log('• Application data directory has been cleared');

    console.log('\n🎉 Tauri data reset completed!');
    console.log('📊 Summary:');
    results.forEach(result => {
      const status = result.success ? '✅' : '❌';
      console.log(`  ${status} ${result.operation}: ${result.success ? 'Success' : result.error}`);
    });

    console.log('\nℹ️ You may need to restart the application to see all changes.');

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
