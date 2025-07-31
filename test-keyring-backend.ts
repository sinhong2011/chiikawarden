import { invoke } from '@tauri-apps/api/core';

interface KeyringBackendStatus {
  backend_available: boolean;
  backend_type: string;
  can_store_retrieve: boolean;
  error_message?: string;
  timestamp: string;
}

async function testKeyringBackend() {
  console.log('🔍 Testing keyring backend status...');
  
  try {
    const status: KeyringBackendStatus = await invoke('check_keyring_backend');
    
    console.log('\n📊 Keyring Backend Status:');
    console.log('========================');
    console.log(`✅ Backend Available: ${status.backend_available ? '✅ YES' : '❌ NO'}`);
    console.log(`🔧 Backend Type: ${status.backend_type}`);
    console.log(`💾 Can Store/Retrieve: ${status.can_store_retrieve ? '✅ YES' : '❌ NO'}`);
    console.log(`⏰ Timestamp: ${status.timestamp}`);
    
    if (status.error_message) {
      console.log(`❌ Error: ${status.error_message}`);
    }
    
    // Overall assessment
    if (status.backend_available && status.can_store_retrieve && status.backend_type === 'system') {
      console.log('\n🎉 SUCCESS: Real system keyring is working properly!');
      console.log('   - No more mock keyring');
      console.log('   - Tokens will be persisted securely');
      console.log('   - Vault sync should work correctly');
    } else {
      console.log('\n⚠️  WARNING: Keyring backend has issues');
      if (!status.backend_available) {
        console.log('   - Backend is not available');
      }
      if (!status.can_store_retrieve) {
        console.log('   - Cannot store/retrieve data');
      }
      if (status.backend_type !== 'system') {
        console.log(`   - Using ${status.backend_type} instead of system keyring`);
      }
    }
    
  } catch (error) {
    console.error('❌ Failed to check keyring backend:', error);
  }
}

// Run the test
testKeyringBackend();
