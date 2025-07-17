// Design tokens and utilities to replace DaisyUI theme system

export const colors = {
  primary: {
    50: "rgb(240 249 255)",
    100: "rgb(224 242 254)",
    200: "rgb(186 230 253)",
    300: "rgb(125 211 252)",
    400: "rgb(56 189 248)",
    500: "rgb(14 165 233)",
    600: "rgb(2 132 199)",
    700: "rgb(3 105 161)",
    800: "rgb(7 89 133)",
    900: "rgb(12 74 110)",
    950: "rgb(8 47 73)",
  },
  secondary: {
    50: "rgb(253 244 255)",
    100: "rgb(250 232 255)",
    200: "rgb(245 208 254)",
    300: "rgb(240 171 252)",
    400: "rgb(232 121 249)",
    500: "rgb(217 70 239)",
    600: "rgb(192 38 211)",
    700: "rgb(162 28 175)",
    800: "rgb(134 25 143)",
    900: "rgb(112 26 117)",
    950: "rgb(74 4 78)",
  },
  accent: {
    50: "rgb(240 253 244)",
    100: "rgb(220 252 231)",
    200: "rgb(187 247 208)",
    300: "rgb(134 239 172)",
    400: "rgb(74 222 128)",
    500: "rgb(34 197 94)",
    600: "rgb(22 163 74)",
    700: "rgb(21 128 61)",
    800: "rgb(22 101 52)",
    900: "rgb(20 83 45)",
    950: "rgb(5 46 22)",
  },
  neutral: {
    50: "rgb(250 250 250)",
    100: "rgb(245 245 245)",
    200: "rgb(229 229 229)",
    300: "rgb(212 212 212)",
    400: "rgb(163 163 163)",
    500: "rgb(115 115 115)",
    600: "rgb(82 82 82)",
    700: "rgb(64 64 64)",
    800: "rgb(38 38 38)",
    900: "rgb(23 23 23)",
    950: "rgb(10 10 10)",
  },
  // Dark theme colors (Dracula-inspired)
  base: {
    100: "rgb(40 42 54)", // dracula background
    200: "rgb(68 71 90)", // dracula current line
    300: "rgb(98 114 164)", // dracula comment
    content: "rgb(248 248 242)", // dracula foreground
  },
  success: "rgb(80 250 123)", // dracula green
  warning: "rgb(255 184 108)", // dracula orange
  error: "rgb(255 85 85)", // dracula red
  info: "rgb(139 233 253)", // dracula cyan
} as const;

export const spacing = {
  xs: "0.5rem",
  sm: "0.75rem",
  md: "1rem",
  lg: "1.5rem",
  xl: "2rem",
  "2xl": "3rem",
  "3xl": "4rem",
} as const;

export const borderRadius = {
  sm: "0.25rem",
  md: "0.375rem",
  lg: "0.5rem",
  xl: "0.75rem",
  "2xl": "1rem",
  box: "0.5rem", // DaisyUI rounded-box equivalent
  full: "9999px",
} as const;

export const fontSize = {
  xs: "0.75rem",
  sm: "0.875rem",
  base: "1rem",
  lg: "1.125rem",
  xl: "1.25rem",
  "2xl": "1.5rem",
  "3xl": "1.875rem",
  "4xl": "2.25rem",
} as const;

export const fontWeight = {
  normal: "400",
  medium: "500",
  semibold: "600",
  bold: "700",
} as const;

export const shadows = {
  sm: "0 1px 2px 0 rgb(0 0 0 / 0.05)",
  md: "0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)",
  lg: "0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)",
  xl: "0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1)",
} as const;

// Animation durations
export const duration = {
  fast: "150ms",
  normal: "200ms",
  slow: "300ms",
} as const;

// Z-index scale
export const zIndex = {
  dropdown: 50,
  modal: 100,
  popover: 200,
  tooltip: 300,
} as const;

// Component size variants
export const sizes = {
  sm: {
    padding: "0.5rem 0.75rem",
    fontSize: fontSize.sm,
    height: "2rem",
  },
  md: {
    padding: "0.5rem 1rem",
    fontSize: fontSize.base,
    height: "2.5rem",
  },
  lg: {
    padding: "0.75rem 1.5rem",
    fontSize: fontSize.lg,
    height: "3rem",
  },
} as const;

// Utility functions
export const cn = (...classes: (string | undefined | null | false)[]): string => {
  return classes.filter(Boolean).join(" ");
};

// Color utility functions
export const withOpacity = (color: string, opacity: number): string => {
  return `${color} / ${opacity}`;
};

// Responsive breakpoints (matching Tailwind defaults)
export const breakpoints = {
  sm: "640px",
  md: "768px",
  lg: "1024px",
  xl: "1280px",
  "2xl": "1536px",
} as const;

// Component variants
export const buttonVariants = {
  primary: "bg-primary text-primary-content hover:bg-primary/90",
  secondary: "bg-secondary text-secondary-content hover:bg-secondary/90",
  ghost: "bg-transparent text-base-content hover:bg-base-200",
  outline: "border border-base-300 bg-transparent text-base-content hover:bg-base-100",
} as const;

export const alertVariants = {
  success: "bg-success/10 border-success/20 text-success",
  warning: "bg-warning/10 border-warning/20 text-warning",
  error: "bg-error/10 border-error/20 text-error",
  info: "bg-info/10 border-info/20 text-info",
} as const;
