// src/utils/crypto.utils.ts
export const cryptoUtils = {
  encrypt: (data: string) => `encrypted:${data}`,
  decrypt: (data: string) => data.replace("encrypted:", ""),
};
