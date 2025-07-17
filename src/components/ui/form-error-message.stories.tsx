import type { Meta, StoryObj } from "@storybook/react";
import { AlertTriangle, XCircle } from "lucide-react";
import { FormErrorMessage } from "./form-error-message";

const meta: Meta<typeof FormErrorMessage> = {
  title: "UI/Form/FormErrorMessage",
  component: FormErrorMessage,
  parameters: {
    layout: "centered",
    docs: {
      description: {
        component:
          "A reusable component for displaying form validation errors. Supports single or multiple error messages with consistent styling and accessibility features.",
      },
    },
  },
  argTypes: {
    error: {
      control: "text",
      description: "Error message(s) to display",
    },
    size: {
      control: "select",
      options: ["sm", "md", "lg"],
      description: "Size variant for the error message",
    },
    showIcon: {
      control: "boolean",
      description: "Whether to show the error icon",
    },
    animate: {
      control: "boolean",
      description: "Whether to animate the appearance",
    },
    className: {
      control: "text",
      description: "Additional CSS classes",
    },
  },
};

export default meta;
type Story = StoryObj<typeof FormErrorMessage>;

// Basic Examples
export const Default: Story = {
  args: {
    error: "This field is required",
  },
};

export const NoError: Story = {
  args: {
    error: null,
  },
  parameters: {
    docs: {
      description: {
        story: "When no error is provided, the component renders nothing.",
      },
    },
  },
};

export const MultipleErrors: Story = {
  args: {
    error: [
      "Email is required",
      "Email must be a valid email address",
      "Email must be less than 100 characters",
    ],
  },
  parameters: {
    docs: {
      description: {
        story: "Multiple errors are displayed as a bulleted list.",
      },
    },
  },
};

// Size Variants
export const SmallSize: Story = {
  args: {
    error: "This field is required",
    size: "sm",
  },
};

export const MediumSize: Story = {
  args: {
    error: "This field is required",
    size: "md",
  },
};

export const LargeSize: Story = {
  args: {
    error: "This field is required",
    size: "lg",
  },
};

// Icon Variants
export const WithoutIcon: Story = {
  args: {
    error: "This field is required",
    showIcon: false,
  },
  parameters: {
    docs: {
      description: {
        story: "Error message without the default icon.",
      },
    },
  },
};

export const CustomIcon: Story = {
  args: {
    error: "This field is required",
    icon: <XCircle className="h-4 w-4 text-danger flex-shrink-0 mt-0.5" />,
  },
  parameters: {
    docs: {
      description: {
        story: "Using a custom icon instead of the default AlertCircle.",
      },
    },
  },
};

export const WarningIcon: Story = {
  args: {
    error: "This field may need attention",
    icon: <AlertTriangle className="h-4 w-4 text-warning flex-shrink-0 mt-0.5" />,
  },
  parameters: {
    docs: {
      description: {
        story: "Using a warning icon with different color for non-critical messages.",
      },
    },
  },
};

// Animation
export const WithoutAnimation: Story = {
  args: {
    error: "This field is required",
    animate: false,
  },
  parameters: {
    docs: {
      description: {
        story: "Error message without entrance animation.",
      },
    },
  },
};

// Form Integration Examples
export const FormExample: Story = {
  render: () => (
    <div className="w-96 space-y-4 p-6 bg-base-100 rounded-lg border">
      <h3 className="text-lg font-semibold mb-4">Login Form</h3>
      
      <div className="space-y-2">
        <label className="block text-sm font-medium text-foreground">
          Email Address *
        </label>
        <input
          type="email"
          className="w-full px-3 py-2 border border-danger rounded-md focus:outline-none focus:ring-2 focus:ring-danger/20"
          placeholder="Enter your email"
          aria-invalid="true"
          aria-describedby="email-error"
        />
        <FormErrorMessage 
          error="Please enter a valid email address" 
          id="email-error"
        />
      </div>

      <div className="space-y-2">
        <label className="block text-sm font-medium text-foreground">
          Password *
        </label>
        <input
          type="password"
          className="w-full px-3 py-2 border border-danger rounded-md focus:outline-none focus:ring-2 focus:ring-danger/20"
          placeholder="Enter your password"
          aria-invalid="true"
          aria-describedby="password-error"
        />
        <FormErrorMessage 
          error={[
            "Password is required",
            "Password must be at least 8 characters long",
            "Password must contain at least one uppercase letter"
          ]}
          id="password-error"
        />
      </div>

      <button className="w-full bg-primary text-primary-foreground py-2 px-4 rounded-md hover:bg-primary-hover transition-colors">
        Sign In
      </button>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Example showing FormErrorMessage integrated with form inputs, including proper ARIA attributes for accessibility.",
      },
    },
  },
};

// Real-world Scenarios
export const LongErrorMessage: Story = {
  args: {
    error: "The password you entered does not meet our security requirements. Please ensure it contains at least 8 characters, including uppercase and lowercase letters, numbers, and special characters.",
  },
  parameters: {
    docs: {
      description: {
        story: "Handling longer error messages with proper text wrapping.",
      },
    },
  },
};

export const ServerValidationErrors: Story = {
  args: {
    error: [
      "Email address is already registered",
      "Please use a different email or try signing in instead",
    ],
  },
  parameters: {
    docs: {
      description: {
        story: "Example of server-side validation errors with multiple related messages.",
      },
    },
  },
};

// Styling Variations
export const CustomStyling: Story = {
  args: {
    error: "Custom styled error message",
    className: "bg-danger/5 p-3 rounded-md border border-danger/20",
  },
  parameters: {
    docs: {
      description: {
        story: "Custom styling applied through the className prop.",
      },
    },
  },
};
