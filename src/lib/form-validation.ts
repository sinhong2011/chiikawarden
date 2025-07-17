// src/lib/form-validation.ts

import { isValidEmail } from "@/lib/constants";
import { i18n } from "@/lib/i18n";

export type ValidationResult = string | undefined;

// Email validation
export const validateEmail = (email: string): ValidationResult => {
  if (!email.trim()) {
    return i18n._("validation.email_required");
  }

  if (!isValidEmail(email)) {
    return i18n._("validation.email_invalid");
  }

  return undefined;
};

// Password validation
export const validatePassword = (password: string): ValidationResult => {
  if (!password) {
    return i18n._("validation.password_required");
  }

  if (password.length < 8) {
    return i18n._("validation.password_min_length");
  }

  return undefined;
};

// Master password validation (stricter)
export const validateMasterPassword = (password: string): ValidationResult => {
  if (!password) {
    return i18n._("validation.master_password_required");
  }

  if (password.length < 8) {
    return i18n._("validation.master_password_min_length");
  }

  if (password.length > 128) {
    return i18n._("validation.master_password_max_length");
  }

  // Check for at least one uppercase, lowercase, number, and special character
  const hasUppercase = /[A-Z]/.test(password);
  const hasLowercase = /[a-z]/.test(password);
  const hasNumber = /\d/.test(password);
  const hasSpecial = /[!@#$%^&*()_+\-=[\]{}|;:,.<>?]/.test(password);

  const strengthChecks = [hasUppercase, hasLowercase, hasNumber, hasSpecial];
  const passedChecks = strengthChecks.filter(Boolean).length;

  if (passedChecks < 3) {
    return i18n._("validation.master_password_strength");
  }

  return undefined;
};

// Confirm password validation
export const validateConfirmPassword = (
  password: string,
  confirmPassword: string
): ValidationResult => {
  if (!confirmPassword) {
    return i18n._("validation.confirm_password_required");
  }

  if (password !== confirmPassword) {
    return i18n._("validation.passwords_do_not_match");
  }

  return undefined;
};

// Required field validation
export const validateRequired = (
  value: string,
  fieldName: string = i18n._("validation.field_default_name")
): ValidationResult => {
  if (!value || !value.trim()) {
    return i18n._("validation.field_required", { fieldName });
  }

  return undefined;
};

// Cipher name validation
export const validateCipherName = (name: string): ValidationResult => {
  if (!name || !name.trim()) {
    return i18n._("validation.name_required");
  }

  if (name.trim().length > 100) {
    return i18n._("validation.name_max_length");
  }

  return undefined;
};

// URL validation
export const validateUrl = (url: string): ValidationResult => {
  if (!url.trim()) {
    return undefined; // URL is optional
  }

  try {
    new URL(url);
    return undefined;
  } catch {
    return i18n._("validation.url_invalid");
  }
};

// Folder name validation
export const validateFolderName = (name: string): ValidationResult => {
  if (!name || !name.trim()) {
    return i18n._("validation.folder_name_required");
  }

  if (name.trim().length > 50) {
    return i18n._("validation.folder_name_max_length");
  }

  return undefined;
};

// Username validation
export const validateUsername = (username: string): ValidationResult => {
  if (!username.trim()) {
    return undefined; // Username is optional
  }

  if (username.length > 100) {
    return i18n._("validation.username_max_length");
  }

  return undefined;
};

// Notes validation
export const validateNotes = (notes: string): ValidationResult => {
  if (notes && notes.length > 10000) {
    return i18n._("validation.notes_max_length");
  }

  return undefined;
};

// Credit card number validation (basic)
export const validateCardNumber = (cardNumber: string): ValidationResult => {
  if (!cardNumber.trim()) {
    return undefined; // Card number is optional
  }

  // Remove spaces and dashes
  const cleaned = cardNumber.replace(/[\s-]/g, "");

  // Check if it's all digits
  if (!/^\d+$/.test(cleaned)) {
    return i18n._("validation.card_number_digits_only");
  }

  // Check length (most cards are 13-19 digits)
  if (cleaned.length < 13 || cleaned.length > 19) {
    return i18n._("validation.card_number_length");
  }

  // Luhn algorithm check
  let sum = 0;
  let isEven = false;

  for (let i = cleaned.length - 1; i >= 0; i--) {
    let digit = parseInt(cleaned[i]);

    if (isEven) {
      digit *= 2;
      if (digit > 9) {
        digit -= 9;
      }
    }

    sum += digit;
    isEven = !isEven;
  }

  if (sum % 10 !== 0) {
    return i18n._("validation.card_number_invalid");
  }

  return undefined;
};

// Expiry date validation (MM/YY format)
export const validateExpiryDate = (expiry: string): ValidationResult => {
  if (!expiry.trim()) {
    return undefined; // Expiry is optional
  }

  const expiryRegex = /^(0[1-9]|1[0-2])\/\d{2}$/;
  if (!expiryRegex.test(expiry)) {
    return i18n._("validation.expiry_date_format");
  }

  const [month, year] = expiry.split("/");
  const currentDate = new Date();
  const currentYear = currentDate.getFullYear() % 100;
  const currentMonth = currentDate.getMonth() + 1;

  const expiryYear = parseInt(year);
  const expiryMonth = parseInt(month);

  if (expiryYear < currentYear || (expiryYear === currentYear && expiryMonth < currentMonth)) {
    return i18n._("validation.card_expired");
  }

  return undefined;
};

// CVV validation
export const validateCvv = (cvv: string): ValidationResult => {
  if (!cvv.trim()) {
    return undefined; // CVV is optional
  }

  if (!/^\d{3,4}$/.test(cvv)) {
    return i18n._("validation.cvv_format");
  }

  return undefined;
};

// Phone number validation (basic)
export const validatePhoneNumber = (phone: string): ValidationResult => {
  if (!phone.trim()) {
    return undefined; // Phone is optional
  }

  // Remove all non-digit characters
  const cleaned = phone.replace(/\D/g, "");

  if (cleaned.length < 10 || cleaned.length > 15) {
    return i18n._("validation.phone_number_length");
  }

  return undefined;
};

// SSN validation (basic US format)
export const validateSsn = (ssn: string): ValidationResult => {
  if (!ssn.trim()) {
    return undefined; // SSN is optional
  }

  // Remove dashes
  const cleaned = ssn.replace(/-/g, "");

  if (!/^\d{9}$/.test(cleaned)) {
    return i18n._("validation.ssn_format");
  }

  return undefined;
};

// Postal code validation (basic)
export const validatePostalCode = (postalCode: string): ValidationResult => {
  if (!postalCode.trim()) {
    return undefined; // Postal code is optional
  }

  // Basic validation - alphanumeric with optional spaces/dashes
  if (!/^[a-zA-Z0-9\s-]{3,10}$/.test(postalCode)) {
    return i18n._("validation.postal_code_format");
  }

  return undefined;
};

// Compose multiple validators
export const composeValidators = (...validators: Array<(value: string) => ValidationResult>) => {
  return (value: string): ValidationResult => {
    for (const validator of validators) {
      const result = validator(value);
      if (result) {
        return result;
      }
    }
    return undefined;
  };
};

// Password strength calculator
export const calculatePasswordStrength = (
  password: string
): {
  score: number;
  feedback: string[];
} => {
  const feedback: string[] = [];
  let score = 0;

  if (password.length >= 8) {
    score += 1;
  } else {
    feedback.push(i18n._("validation.password_strength_length"));
  }

  if (password.length >= 12) {
    score += 1;
  } else if (password.length >= 8) {
    feedback.push(i18n._("validation.password_strength_longer"));
  }

  if (/[a-z]/.test(password)) {
    score += 1;
  } else {
    feedback.push(i18n._("validation.password_strength_lowercase"));
  }

  if (/[A-Z]/.test(password)) {
    score += 1;
  } else {
    feedback.push(i18n._("validation.password_strength_uppercase"));
  }

  if (/\d/.test(password)) {
    score += 1;
  } else {
    feedback.push(i18n._("validation.password_strength_numbers"));
  }

  if (/[!@#$%^&*()_+\-=[\]{}|;:,.<>?]/.test(password)) {
    score += 1;
  } else {
    feedback.push(i18n._("validation.password_strength_special"));
  }

  // Check for common patterns
  if (/(.)\1{2,}/.test(password)) {
    score -= 1;
    feedback.push(i18n._("validation.password_strength_no_repeating"));
  }

  if (/123|abc|qwe/i.test(password)) {
    score -= 1;
    feedback.push(i18n._("validation.password_strength_no_sequences"));
  }

  return {
    score: Math.max(0, Math.min(5, score)),
    feedback,
  };
};
