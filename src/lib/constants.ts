// src/lib/constants.ts

/**
 * Regular expression pattern for email validation
 *
 * Pattern breakdown:
 * - ^: Start of string
 * - [^\s@]+: One or more characters that are not whitespace or @
 * - @: Literal @ symbol
 * - [^\s@]+: One or more characters that are not whitespace or @
 * - \.: Literal dot (escaped)
 * - [^\s@]+: One or more characters that are not whitespace or @
 * - $: End of string
 *
 * This ensures:
 * - Exactly one @ symbol
 * - Characters before and after the @
 * - At least one dot in the domain
 * - No whitespace anywhere in the email
 * - The entire string matches the pattern
 */
export const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Utility function to test if a string is a valid email
 * @param email - The email string to validate
 * @returns true if the email is valid, false otherwise
 */
export const isValidEmail = (email: string): boolean => {
  return EMAIL_REGEX.test(email);
};
