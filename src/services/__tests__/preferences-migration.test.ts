import { beforeEach, describe, expect, it, vi } from "vitest";
import { preferencesMigrationService } from "../preferences-migration.service";

// Mock localStorage
const mockLocalStorage = {
  getItem: vi.fn(),
  setItem: vi.fn(),
  removeItem: vi.fn(),
  clear: vi.fn(),
};

// Mock settingsService
const mockSettingsService = {
  getSettings: vi.fn(),
  saveSettings: vi.fn(),
};

// Mock the dependencies
vi.mock("../settings.service", () => ({
  settingsService: mockSettingsService,
}));

// Setup global localStorage mock
Object.defineProperty(window, "localStorage", {
  value: mockLocalStorage,
  writable: true,
});

describe("PreferencesMigrationService", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("hasLegacyPreferences", () => {
    it("should return true when legacy preferences exist", () => {
      mockLocalStorage.getItem.mockReturnValue('{"theme":"dark"}');

      const result = preferencesMigrationService.hasLegacyPreferences();

      expect(result).toBe(true);
      expect(mockLocalStorage.getItem).toHaveBeenCalledWith("chiikawarden_preferences");
    });

    it("should return false when no legacy preferences exist", () => {
      mockLocalStorage.getItem.mockReturnValue(null);

      const result = preferencesMigrationService.hasLegacyPreferences();

      expect(result).toBe(false);
    });

    it("should return false when localStorage throws error", () => {
      mockLocalStorage.getItem.mockImplementation(() => {
        throw new Error("Storage error");
      });

      const result = preferencesMigrationService.hasLegacyPreferences();

      expect(result).toBe(false);
    });
  });

  describe("loadLegacyPreferences", () => {
    it("should load and parse legacy preferences", () => {
      const legacyPrefs = {
        theme: "dark",
        language: "en",
        autoLock: true,
        autoLockTimeout: 30,
        minimizeToTray: false,
        startMinimized: true,
        clearClipboard: true,
        clearClipboardTimeout: 10,
      };

      mockLocalStorage.getItem.mockReturnValue(JSON.stringify(legacyPrefs));

      const result = preferencesMigrationService.loadLegacyPreferences();

      expect(result).toEqual(legacyPrefs);
    });

    it("should return null when no preferences exist", () => {
      mockLocalStorage.getItem.mockReturnValue(null);

      const result = preferencesMigrationService.loadLegacyPreferences();

      expect(result).toBeNull();
    });

    it("should return null when JSON parsing fails", () => {
      mockLocalStorage.getItem.mockReturnValue("invalid json");

      const result = preferencesMigrationService.loadLegacyPreferences();

      expect(result).toBeNull();
    });
  });

  describe("convertLegacyToSettings", () => {
    it("should convert legacy preferences to Tauri settings format", () => {
      const legacyPrefs = {
        theme: "dark" as const,
        language: "en",
        autoLock: true,
        autoLockTimeout: 30,
        minimizeToTray: false,
        startMinimized: true,
        clearClipboard: true,
        clearClipboardTimeout: 10,
      };

      const result = preferencesMigrationService.convertLegacyToSettings(legacyPrefs);

      expect(result).toEqual({
        theme: "dark",
        language: "en",
        vault_timeout: 30,
        vault_timeout_action: "lock",
        clear_clipboard: 10,
        minimize_to_tray: false,
        start_to_tray: true,
        biometric_unlock: false,
        auto_start: false,
        server_url: undefined,
      });
    });

    it("should handle autoLock false correctly", () => {
      const legacyPrefs = {
        theme: "light" as const,
        language: "en",
        autoLock: false,
        autoLockTimeout: 15,
        minimizeToTray: true,
        startMinimized: false,
        clearClipboard: false,
        clearClipboardTimeout: 20,
      };

      const result = preferencesMigrationService.convertLegacyToSettings(legacyPrefs);

      expect(result.vault_timeout_action).toBe("logout");
      expect(result.clear_clipboard).toBe(0); // Disabled when clearClipboard is false
    });
  });

  describe("cleanupLegacyPreferences", () => {
    it("should remove legacy preferences from localStorage", () => {
      preferencesMigrationService.cleanupLegacyPreferences();

      expect(mockLocalStorage.removeItem).toHaveBeenCalledWith("chiikawarden_preferences");
      expect(mockLocalStorage.removeItem).toHaveBeenCalledWith("chiikawarden_app-preferences");
    });

    it("should handle localStorage errors gracefully", () => {
      mockLocalStorage.removeItem.mockImplementation(() => {
        throw new Error("Storage error");
      });

      expect(() => {
        preferencesMigrationService.cleanupLegacyPreferences();
      }).not.toThrow();
    });
  });

  describe("isMigrationComplete", () => {
    it("should return true when no legacy preferences exist", () => {
      mockLocalStorage.getItem.mockReturnValue(null);

      const result = preferencesMigrationService.isMigrationComplete();

      expect(result).toBe(true);
    });

    it("should return false when legacy preferences exist", () => {
      mockLocalStorage.getItem.mockReturnValue('{"theme":"dark"}');

      const result = preferencesMigrationService.isMigrationComplete();

      expect(result).toBe(false);
    });
  });
});
