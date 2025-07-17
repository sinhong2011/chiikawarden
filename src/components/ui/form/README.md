# Form Components

This directory contains improved form components with consistent styling that follows the application's design system.

## Components

### TextInput
A versatile text input component with support for various input types and styling variants.

**Features:**
- Hero UI native variants: `flat`, `bordered`, `faded`, `underlined`
- Size options: `sm`, `md`, `lg`
- Support for multiline (textarea)
- Consistent error states and validation
- Required field indicators
- Proper focus states and accessibility

**Usage:**
```tsx
<TextInput
  name="email"
  type="email"
  label="Email Address"
  placeholder="Enter your email"
  value={value}
  error={error}
  required
  size="md"
  variant="flat"
  onInput={handleInput}
  onChange={handleChange}
  onBlur={handleBlur}
/>
```

### Checkbox
A styled checkbox component with optional descriptions and proper accessibility.

**Features:**
- Size options: `sm`, `md`, `lg`
- Optional description text
- Custom checkmark icon
- Proper focus states
- Error state styling
- Required field indicators

**Usage:**
```tsx
<Checkbox
  name="newsletter"
  label="Subscribe to Newsletter"
  description="Get updates delivered to your inbox"
  checked={checked}
  error={error}
  size="md"
  onInput={handleInput}
  onChange={handleChange}
/>
```

### RadioGroup
A radio button group component with support for descriptions and flexible layouts.

**Features:**
- Size options: `sm`, `md`, `lg`
- Orientation: `horizontal`, `vertical`
- Optional descriptions for options
- Individual option disable support
- Consistent styling with other form components

**Usage:**
```tsx
<RadioGroup
  name="theme"
  label="Theme Preference"
  description="Choose your preferred theme"
  options={[
    { label: "Light", value: "light", description: "Bright interface" },
    { label: "Dark", value: "dark", description: "Easy on eyes" }
  ]}
  value={value}
  error={error}
  orientation="vertical"
  size="md"
  onInput={handleInput}
  onChange={handleChange}
/>
```

### Select
A dropdown select component with custom styling and animations.

**Features:**
- Hero UI native variants: `flat`, `bordered`, `faded`, `underlined`
- Size options: `sm`, `md`, `lg`
- Custom dropdown animations
- Option disable support
- Proper keyboard navigation
- Search/filter capabilities

**Usage:**
```tsx
<Select
  name="country"
  label="Country"
  placeholder="Select your country"
  options={[
    { label: "United States", value: "us" },
    { label: "Canada", value: "ca" }
  ]}
  value={value}
  error={error}
  required
  size="md"
  variant="flat"
  onInput={handleInput}
  onChange={handleChange}
/>
```

## Design System Integration

All components follow the application's design system:

- **Colors**: Uses theme colors from `global.css` (primary, secondary, base-*, error, etc.)
- **Typography**: Consistent font sizes and weights
- **Spacing**: Standardized padding and margins
- **Borders**: Consistent border radius and styles
- **Animations**: Smooth transitions and hover effects
- **Accessibility**: Proper ARIA labels, focus states, and keyboard navigation

## Styling Approach

- **Tailwind CSS**: All styling uses Tailwind utility classes
- **Theme Colors**: Leverages CSS custom properties for theming
- **Responsive**: Components adapt to different screen sizes
- **Dark Mode**: Full support for dark/light theme switching
- **Consistent**: All components share similar visual patterns

## Accessibility Features

- Proper ARIA labels and descriptions
- Keyboard navigation support
- Focus indicators
- Screen reader compatibility
- Error state announcements
- Required field indicators

## Form Integration

These components work seamlessly with:
- **@modular-forms/solid**: Form state management
- **Validation**: Built-in error display and validation states
- **TypeScript**: Full type safety and IntelliSense support

## Example Usage

See `FormShowcase.tsx` for a comprehensive example demonstrating all components with various configurations and use cases.
