// src/services/crypto.service.ts
// Mixed approach: Uses typed commands where available, direct invoke for specialized crypto operations
import { invoke } from "@tauri-apps/api/core";
import { commands, type KdfConfig } from "@/lib/tauri-commands";

// Re-export types from tauri-commands for convenience
export type {
  BiometricUnlockResponse,
  KdfConfig,
  LoginResponse,
  RetrieveBiometricKeyRequest,
  RetrieveBiometricKeyResponse,
  SetupAccountResponse,
  UnlockResponse,
} from "@/lib/tauri-commands";

// Types matching the Rust backend (for direct invoke operations)
export interface EncryptedData {
  data: string;
  iv: string;
  mac?: string;
  enc_type: number;
}

export interface DeriveKeyRequest {
  password: string;
  email: string;
  kdf_config: KdfConfig;
}

export interface DeriveKeyResponse {
  master_key: number[];
}

export interface HashKeyRequest {
  password: string;
  master_key: number[];
  purpose: string; // "local" or "server"
}

export interface HashKeyResponse {
  hash: string;
}

export interface EncryptRequest {
  data: number[];
  key: number[];
  encryption_type: string;
}

export interface EncryptResponse {
  encrypted_data: EncryptedData;
}

export interface DecryptRequest {
  encrypted_data: EncryptedData;
  key: number[];
  encryption_type: string;
}

export interface DecryptResponse {
  data: number[];
}

export interface GenerateKeyResponse {
  key: number[];
}

export interface RsaKeyPairResponse {
  public_key: number[];
  private_key: number[];
}

// Encryption types
export enum EncryptionType {
  AesCbc256B64 = "AesCbc256B64",
  AesCbc256HmacSha256B64 = "AesCbc256HmacSha256B64",
}

// Hash purposes
export enum HashPurpose {
  Local = "local",
  Server = "server",
}

export const cryptoService = {
  /**
   * Derive master key from password and email
   */
  async deriveMasterKey(password: string, email: string, kdfConfig: KdfConfig): Promise<number[]> {
    try {
      const request: DeriveKeyRequest = {
        password,
        email,
        kdf_config: kdfConfig,
      };

      const response = await invoke<DeriveKeyResponse>("derive_master_key", { request });
      return response.master_key;
    } catch (error) {
      throw new Error(`Failed to derive master key: ${error}`);
    }
  },

  /**
   * Hash master key for verification
   */
  async hashMasterKey(
    password: string,
    masterKey: number[],
    purpose: HashPurpose
  ): Promise<string> {
    try {
      const request: HashKeyRequest = {
        password,
        master_key: masterKey,
        purpose,
      };

      const response = await invoke<HashKeyResponse>("hash_master_key", { request });
      return response.hash;
    } catch (error) {
      throw new Error(`Failed to hash master key: ${error}`);
    }
  },

  /**
   * Encrypt data
   */
  async encryptData(
    data: number[],
    key: number[],
    encryptionType: EncryptionType
  ): Promise<EncryptedData> {
    try {
      const request: EncryptRequest = {
        data,
        key,
        encryption_type: encryptionType,
      };

      const response = await invoke<EncryptResponse>("encrypt_data", { request });
      return response.encrypted_data;
    } catch (error) {
      throw new Error(`Failed to encrypt data: ${error}`);
    }
  },

  /**
   * Decrypt data
   */
  async decryptData(
    encryptedData: EncryptedData,
    key: number[],
    encryptionType: EncryptionType
  ): Promise<number[]> {
    try {
      const request: DecryptRequest = {
        encrypted_data: encryptedData,
        key,
        encryption_type: encryptionType,
      };

      const response = await invoke<DecryptResponse>("decrypt_data", { request });
      return response.data;
    } catch (error) {
      throw new Error(`Failed to decrypt data: ${error}`);
    }
  },

  /**
   * Generate user key
   */
  async generateUserKey(): Promise<number[]> {
    try {
      const response = await invoke<GenerateKeyResponse>("generate_user_key");
      return response.key;
    } catch (error) {
      throw new Error(`Failed to generate user key: ${error}`);
    }
  },

  /**
   * Generate RSA key pair
   */
  async generateRsaKeyPair(bits: number = 2048): Promise<RsaKeyPairResponse> {
    try {
      const response = await invoke<RsaKeyPairResponse>("generate_rsa_key_pair", { bits });
      return response;
    } catch (error) {
      throw new Error(`Failed to generate RSA key pair: ${error}`);
    }
  },

  /**
   * Generate random bytes
   */
  async generateRandomBytes(length: number): Promise<number[]> {
    try {
      const response = await invoke<GenerateKeyResponse>("generate_random_bytes", { length });
      return response.key;
    } catch (error) {
      throw new Error(`Failed to generate random bytes: ${error}`);
    }
  },

  /**
   * Setup biometric unlock (uses typed command)
   */
  async setupBiometricUnlock(userId: string, userKey: number[]): Promise<boolean> {
    const result = await commands.setupBiometricUnlock(userId, userKey);

    if (result.status === "error") {
      throw new Error(`Failed to setup biometric unlock: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Retrieve biometric user key (uses typed command)
   */
  async retrieveBiometricUserKey(userId: string, prompt?: string): Promise<number[]> {
    const request = { user_id: userId, prompt: prompt || "Unlock Chiikawarden" };
    const result = await commands.retrieveBiometricUserKey(request);

    if (result.status === "error") {
      throw new Error(`Failed to retrieve biometric user key: ${result.error}`);
    }

    if (!result.data.success || !result.data.user_key) {
      throw new Error("Biometric authentication failed");
    }

    return result.data.user_key;
  },

  /**
   * Change master password (uses typed command)
   */
  async changeMasterPassword(
    userId: string,
    currentPassword: string,
    newPassword: string,
    email: string,
    kdfConfig: KdfConfig
  ): Promise<boolean> {
    const result = await commands.changeMasterPassword(
      userId,
      currentPassword,
      newPassword,
      email,
      kdfConfig
    );

    if (result.status === "error") {
      throw new Error(`Failed to change master password: ${result.error}`);
    }

    return result.data;
  },

  /**
   * Decrypt user key with master key (direct invoke - not in typed commands)
   */
  async decryptUserKey(
    encryptedUserKey: EncryptedData,
    masterKey: number[],
    encryptionType: EncryptionType
  ): Promise<number[]> {
    try {
      const response = await invoke<GenerateKeyResponse>("decrypt_user_key", {
        encryptedUserKey,
        masterKey,
        encryptionType,
      });
      return response.key;
    } catch (error) {
      throw new Error(`Failed to decrypt user key: ${error}`);
    }
  },

  /**
   * Validate KDF configuration
   */
  async validateKdfConfig(kdfConfig: KdfConfig): Promise<boolean> {
    try {
      const response = await invoke<boolean>("validate_kdf_config", { kdfConfig });
      return response;
    } catch (error) {
      throw new Error(`Failed to validate KDF config: ${error}`);
    }
  },

  /**
   * RSA encrypt data
   */
  async rsaEncrypt(data: number[], publicKey: number[]): Promise<number[]> {
    try {
      const response = await invoke<GenerateKeyResponse>("rsa_encrypt", { data, publicKey });
      return response.key;
    } catch (error) {
      throw new Error(`Failed to RSA encrypt: ${error}`);
    }
  },

  /**
   * RSA decrypt data
   */
  async rsaDecrypt(encryptedData: number[], privateKey: number[]): Promise<number[]> {
    try {
      const response = await invoke<GenerateKeyResponse>("rsa_decrypt", {
        encryptedData,
        privateKey,
      });
      return response.key;
    } catch (error) {
      throw new Error(`Failed to RSA decrypt: ${error}`);
    }
  },

  /**
   * Encrypt string with AES-GCM (simplified interface)
   */
  async encryptString(plaintext: string, key: string): Promise<string> {
    try {
      const response = await invoke<string>("encrypt_aes_gcm", { plaintext, key });
      return response;
    } catch (error) {
      throw new Error(`Failed to encrypt string: ${error}`);
    }
  },

  /**
   * Decrypt string with AES-GCM (simplified interface)
   */
  async decryptString(ciphertext: string, key: string): Promise<string> {
    try {
      const response = await invoke<string>("decrypt_aes_gcm", { ciphertext, key });
      return response;
    } catch (error) {
      throw new Error(`Failed to decrypt string: ${error}`);
    }
  },

  /**
   * Derive key using Argon2 (simplified interface)
   */
  async deriveArgon2Key(password: string, salt: string, iterations: number): Promise<string> {
    try {
      const response = await invoke<string>("derive_argon2_key", { password, salt, iterations });
      return response;
    } catch (error) {
      throw new Error(`Failed to derive Argon2 key: ${error}`);
    }
  },

  // Utility functions

  /**
   * Convert string to byte array
   */
  stringToBytes(str: string): number[] {
    return Array.from(new TextEncoder().encode(str));
  },

  /**
   * Convert byte array to string
   */
  bytesToString(bytes: number[]): string {
    return new TextDecoder().decode(new Uint8Array(bytes));
  },

  /**
   * Convert hex string to byte array
   */
  hexToBytes(hex: string): number[] {
    const bytes = [];
    for (let i = 0; i < hex.length; i += 2) {
      bytes.push(parseInt(hex.substring(i, i + 2), 16));
    }
    return bytes;
  },

  /**
   * Convert byte array to hex string
   */
  bytesToHex(bytes: number[]): string {
    return bytes.map((b) => b.toString(16).padStart(2, "0")).join("");
  },

  /**
   * Generate secure random password
   */
  generatePassword(length: number = 16, includeSymbols: boolean = true): string {
    const lowercase = "abcdefghijklmnopqrstuvwxyz";
    const uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const numbers = "0123456789";
    const symbols = "!@#$%^&*()_+-=[]{}|;:,.<>?";

    let charset = lowercase + uppercase + numbers;
    if (includeSymbols) {
      charset += symbols;
    }

    let password = "";
    for (let i = 0; i < length; i++) {
      password += charset.charAt(Math.floor(Math.random() * charset.length));
    }

    return password;
  },
};
