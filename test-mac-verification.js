// Test script to trigger MAC verification failure
// This script will call the debug_cipher_decryption command to analyze the MAC verification issue

const { invoke } = window.__TAURI__.core;

async function testMacVerification() {
    try {
        console.log("🔍 Starting MAC verification debug test...");
        
        // First, get all users to find a user ID
        const usersResult = await invoke('get_all_users');
        console.log("📋 Users result:", usersResult);
        
        if (usersResult.status === 'ok' && usersResult.data.length > 0) {
            const userId = usersResult.data[0].id;
            console.log(`👤 Using user ID: ${userId}`);
            
            // Now call the debug cipher decryption command
            console.log("🔐 Calling debug_cipher_decryption...");
            const debugResult = await invoke('debug_cipher_decryption', { userId });
            
            console.log("📊 Debug result:", debugResult);
            
            if (debugResult.status === 'ok') {
                console.log("✅ Debug output:");
                console.log(debugResult.data);
            } else {
                console.error("❌ Debug failed:", debugResult.error);
            }
        } else {
            console.log("⚠️ No users found in database");
        }
        
    } catch (error) {
        console.error("💥 Error during MAC verification test:", error);
    }
}

// Run the test
testMacVerification();
