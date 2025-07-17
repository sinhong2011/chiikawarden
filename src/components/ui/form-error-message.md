# FormErrorMessage Component

A reusable component for displaying form validation errors with consistent styling and accessibility features.

## Features

- ✅ **Single or Multiple Errors**: Supports both single error messages and arrays of errors
- ✅ **Accessibility**: Proper ARIA attributes, screen reader support, and semantic HTML
- ✅ **Responsive Design**: Adapts to different screen sizes and contexts
- ✅ **Customizable**: Multiple size variants, custom icons, and styling options
- ✅ **Type Safe**: Full TypeScript support with comprehensive type definitions
- ✅ **Animation**: Smooth entrance animations (can be disabled)
- ✅ **Design System**: Consistent with the application's design tokens and theming

## Basic Usage

```tsx
import { FormErrorMessage } from "@/components/ui/form-error-message";

// Single error message
<FormErrorMessage error="This field is required" />

// Multiple error messages
<FormErrorMessage error={[
  "Password is required",
  "Password must be at least 8 characters",
  "Password must contain uppercase letters"
]} />

// No error (renders nothing)
<FormErrorMessage error={null} />
```

## Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `error` | `string \| string[] \| null \| undefined` | - | Error message(s) to display |
| `size` | `"sm" \| "md" \| "lg"` | `"sm"` | Size variant for the error message |
| `showIcon` | `boolean` | `true` | Whether to show the error icon |
| `icon` | `React.ReactNode` | `<AlertCircle />` | Custom icon to display |
| `animate` | `boolean` | `true` | Whether to animate the appearance |
| `className` | `string` | - | Additional CSS classes |
| `id` | `string` | - | Unique ID for accessibility |
| `containerProps` | `React.HTMLAttributes<HTMLDivElement>` | - | Additional props for the container |

## Size Variants

```tsx
// Small (default)
<FormErrorMessage error="Small error message" size="sm" />

// Medium
<FormErrorMessage error="Medium error message" size="md" />

// Large
<FormErrorMessage error="Large error message" size="lg" />
```

## Custom Icons

```tsx
import { XCircle, AlertTriangle } from "lucide-react";

// Custom error icon
<FormErrorMessage 
  error="Critical error" 
  icon={<XCircle className="h-4 w-4 text-danger" />} 
/>

// Warning icon
<FormErrorMessage 
  error="Warning message" 
  icon={<AlertTriangle className="h-4 w-4 text-warning" />} 
/>

// No icon
<FormErrorMessage error="Error without icon" showIcon={false} />
```

## Form Integration

### With React Hook Form

```tsx
import { useForm } from "react-hook-form";
import { FormErrorMessage, useFormErrorMessage } from "@/components/ui/form-error-message";

function LoginForm() {
  const { register, handleSubmit, formState: { errors } } = useForm();
  
  // Use the helper hook for accessibility
  const emailError = useFormErrorMessage(errors.email?.message);
  
  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input
        {...register("email", { required: "Email is required" })}
        aria-invalid={emailError.hasError}
        aria-describedby={emailError.errorId}
      />
      <FormErrorMessage 
        error={errors.email?.message} 
        id={emailError.errorId}
      />
    </form>
  );
}
```

### With HeroUI Form Components

```tsx
import { Input } from "@heroui/input";
import { FormErrorMessage } from "@/components/ui/form-error-message";

function SignupForm() {
  const [serverError, setServerError] = useState<string[]>([]);
  
  return (
    <div className="space-y-4">
      <Input
        type="email"
        label="Email"
        isInvalid={serverError.length > 0}
      />
      
      <FormErrorMessage 
        error={serverError}
        className="mt-2"
      />
    </div>
  );
}
```

## Accessibility Features

The component includes comprehensive accessibility support:

- **ARIA Attributes**: `role="alert"`, `aria-live="polite"`, `aria-atomic="true"`
- **Screen Reader Support**: Proper semantic structure and announcements
- **Keyboard Navigation**: Works with form navigation patterns
- **Focus Management**: Integrates with form focus management
- **Error Association**: Use `aria-describedby` to associate errors with form fields

### Accessibility Example

```tsx
function AccessibleForm() {
  const [error, setError] = useState("Email is required");
  const errorId = "email-error";
  
  return (
    <div>
      <label htmlFor="email">Email Address</label>
      <input
        id="email"
        type="email"
        aria-invalid={!!error}
        aria-describedby={error ? errorId : undefined}
      />
      <FormErrorMessage 
        error={error}
        id={errorId}
      />
    </div>
  );
}
```

## Styling and Theming

The component uses the application's design system:

- **Colors**: Uses `text-danger` and `border-danger` from the theme
- **Typography**: Consistent font sizes and weights
- **Spacing**: Standardized gaps and padding
- **Animation**: Smooth entrance transitions

### Custom Styling

```tsx
// Custom background and border
<FormErrorMessage 
  error="Custom styled error"
  className="bg-danger/5 p-3 rounded-md border border-danger/20"
/>

// Different color scheme for warnings
<FormErrorMessage 
  error="Warning message"
  className="text-warning"
  icon={<AlertTriangle className="h-4 w-4 text-warning" />}
/>
```

## Helper Hook: useFormErrorMessage

The `useFormErrorMessage` hook provides utilities for form error handling:

```tsx
const { hasError, errorId, errorProps } = useFormErrorMessage(error);

// Use in form fields
<input {...errorProps} />
<FormErrorMessage error={error} id={errorId} />
```

## Best Practices

1. **Consistent Placement**: Place error messages immediately after the related form field
2. **Clear Messages**: Use specific, actionable error messages
3. **Accessibility**: Always use proper ARIA attributes and IDs
4. **Performance**: The component is memoized for optimal performance
5. **Validation**: Combine with proper form validation libraries
6. **User Experience**: Use animations to draw attention to new errors

## Migration from Basic Error Display

Replace basic error displays:

```tsx
// Before
{errorMessage && <div className="text-error text-sm">{errorMessage}</div>}

// After
<FormErrorMessage error={errorMessage} />
```

## Testing

The component includes comprehensive tests covering:

- Rendering behavior with different error states
- Accessibility attributes
- Size variants and styling
- Custom icons and props
- Helper hook functionality

Run tests with:
```bash
npm test src/components/ui/__tests__/form-error-message.test.tsx
```
