import { useMutation } from "@tanstack/react-query";
import type { EncryptedData, KdfConfig } from "@/services/crypto.service";
import { cryptoService, type EncryptionType, type HashPurpose } from "@/services/crypto.service";

export const useCryptoQueries = () => {
  // Derive master key mutation
  const deriveMasterKeyMutation = useMutation({
    mutationFn: async ({
      password,
      email,
      kdfConfig,
    }: {
      password: string;
      email: string;
      kdfConfig: KdfConfig;
    }) => {
      return await cryptoService.deriveMasterKey(password, email, kdfConfig);
    },
    onError: (error) => {
      console.error("Failed to derive master key:", error);
    },
  });

  // Hash master key mutation
  const hashMasterKeyMutation = useMutation({
    mutationFn: async ({
      password,
      masterKey,
      purpose,
    }: {
      password: string;
      masterKey: number[];
      purpose: HashPurpose;
    }) => {
      return await cryptoService.hashMasterKey(password, masterKey, purpose);
    },
    onError: (error) => {
      console.error("Failed to hash master key:", error);
    },
  });

  // Encrypt data mutation
  const encryptDataMutation = useMutation({
    mutationFn: async ({
      data,
      key,
      encryptionType,
    }: {
      data: number[];
      key: number[];
      encryptionType: EncryptionType;
    }) => {
      return await cryptoService.encryptData(data, key, encryptionType);
    },
    onError: (error) => {
      console.error("Failed to encrypt data:", error);
    },
  });

  // Decrypt data mutation
  const decryptDataMutation = useMutation({
    mutationFn: async ({
      encryptedData,
      key,
      encryptionType,
    }: {
      encryptedData: EncryptedData;
      key: number[];
      encryptionType: EncryptionType;
    }) => {
      return await cryptoService.decryptData(encryptedData, key, encryptionType);
    },
    onError: (error) => {
      console.error("Failed to decrypt data:", error);
    },
  });

  // Generate user key mutation
  const generateUserKeyMutation = useMutation({
    mutationFn: async () => {
      return await cryptoService.generateUserKey();
    },
    onError: (error) => {
      console.error("Failed to generate user key:", error);
    },
  });

  // Generate RSA key pair mutation
  const generateRsaKeyPairMutation = useMutation({
    mutationFn: async (bits: number = 2048) => {
      return await cryptoService.generateRsaKeyPair(bits);
    },
    onError: (error) => {
      console.error("Failed to generate RSA key pair:", error);
    },
  });

  // Generate random bytes mutation
  const generateRandomBytesMutation = useMutation({
    mutationFn: async (length: number) => {
      return await cryptoService.generateRandomBytes(length);
    },
    onError: (error) => {
      console.error("Failed to generate random bytes:", error);
    },
  });

  // Decrypt user key mutation
  const decryptUserKeyMutation = useMutation({
    mutationFn: async ({
      encryptedUserKey,
      masterKey,
      encryptionType,
    }: {
      encryptedUserKey: EncryptedData;
      masterKey: number[];
      encryptionType: EncryptionType;
    }) => {
      return await cryptoService.decryptUserKey(encryptedUserKey, masterKey, encryptionType);
    },
    onError: (error) => {
      console.error("Failed to decrypt user key:", error);
    },
  });

  // Validate KDF config mutation
  const validateKdfConfigMutation = useMutation({
    mutationFn: async (kdfConfig: KdfConfig) => {
      return await cryptoService.validateKdfConfig(kdfConfig);
    },
    onError: (error) => {
      console.error("Failed to validate KDF config:", error);
    },
  });

  // RSA encrypt mutation
  const rsaEncryptMutation = useMutation({
    mutationFn: async ({ data, publicKey }: { data: number[]; publicKey: number[] }) => {
      return await cryptoService.rsaEncrypt(data, publicKey);
    },
    onError: (error) => {
      console.error("Failed to RSA encrypt:", error);
    },
  });

  // RSA decrypt mutation
  const rsaDecryptMutation = useMutation({
    mutationFn: async ({
      encryptedData,
      privateKey,
    }: {
      encryptedData: number[];
      privateKey: number[];
    }) => {
      return await cryptoService.rsaDecrypt(encryptedData, privateKey);
    },
    onError: (error) => {
      console.error("Failed to RSA decrypt:", error);
    },
  });

  // Encrypt string mutation (simplified)
  const encryptStringMutation = useMutation({
    mutationFn: async ({ plaintext, key }: { plaintext: string; key: string }) => {
      return await cryptoService.encryptString(plaintext, key);
    },
    onError: (error) => {
      console.error("Failed to encrypt string:", error);
    },
  });

  // Decrypt string mutation (simplified)
  const decryptStringMutation = useMutation({
    mutationFn: async ({ ciphertext, key }: { ciphertext: string; key: string }) => {
      return await cryptoService.decryptString(ciphertext, key);
    },
    onError: (error) => {
      console.error("Failed to decrypt string:", error);
    },
  });

  // Derive Argon2 key mutation
  const deriveArgon2KeyMutation = useMutation({
    mutationFn: async ({
      password,
      salt,
      iterations,
    }: {
      password: string;
      salt: string;
      iterations: number;
    }) => {
      return await cryptoService.deriveArgon2Key(password, salt, iterations);
    },
    onError: (error) => {
      console.error("Failed to derive Argon2 key:", error);
    },
  });

  // Generate password mutation
  const generatePasswordMutation = useMutation({
    mutationFn: async ({
      length = 16,
      includeSymbols = true,
    }: {
      length?: number;
      includeSymbols?: boolean;
    } = {}) => {
      return cryptoService.generatePassword(length, includeSymbols);
    },
    onError: (error) => {
      console.error("Failed to generate password:", error);
    },
  });

  return {
    // Key derivation and hashing
    deriveMasterKey: deriveMasterKeyMutation,
    hashMasterKey: hashMasterKeyMutation,
    generateUserKey: generateUserKeyMutation,
    decryptUserKey: decryptUserKeyMutation,
    validateKdfConfig: validateKdfConfigMutation,

    // Encryption and decryption
    encryptData: encryptDataMutation,
    decryptData: decryptDataMutation,
    encryptString: encryptStringMutation,
    decryptString: decryptStringMutation,

    // RSA operations
    generateRsaKeyPair: generateRsaKeyPairMutation,
    rsaEncrypt: rsaEncryptMutation,
    rsaDecrypt: rsaDecryptMutation,

    // Utility operations
    generateRandomBytes: generateRandomBytesMutation,
    deriveArgon2Key: deriveArgon2KeyMutation,
    generatePassword: generatePasswordMutation,

    // Utility functions (direct access to service methods)
    utils: {
      stringToBytes: cryptoService.stringToBytes,
      bytesToString: cryptoService.bytesToString,
      hexToBytes: cryptoService.hexToBytes,
      bytesToHex: cryptoService.bytesToHex,
    },
  };
};
