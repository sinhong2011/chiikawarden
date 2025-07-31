import type { Meta, StoryObj } from "@storybook/react";
import React from "react";
import type { PreloginResponse } from "@/services/auth.service";
import PreLogin from "./prelogin";

const meta: Meta<typeof PreLogin> = {
  title: "Auth/PreLogin",
  component: PreLogin,
  parameters: {
    layout: "centered",
    docs: {
      description: {
        component:
          "Enhanced prelogin form component with email input and remember me checkbox. This form collects the user's email, retrieves KDF settings, and captures the remember me preference before proceeding to the login form. Built with HeroUI components and integrated with react-hook-form + zod validation.",
      },
    },
  },
  tags: ["autodocs"],
  argTypes: {
    onFinish: {
      action: "onFinish",
      description:
        "Callback when prelogin is successful with email, KDF settings, and remember me preference",
    },
  },
  decorators: [
    (Story) => (
      <div className="min-h-screen bg-background flex items-center justify-center p-4">
        <div className="w-full max-w-md">
          <Story />
        </div>
      </div>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof PreLogin>;

// Mock successful prelogin response
const mockSuccessfulPrelogin = (email: string, rememberMe: boolean) => {
  const mockKdfSettings: PreloginResponse = {
    kdf: 0, // PBKDF2
    kdfIterations: 600000,
    kdfMemory: null,
    kdfParallelism: null,
  };

  console.log("Prelogin successful:", { email, kdfSettings: mockKdfSettings, rememberMe });
  return mockKdfSettings;
};

// Default story
export const Default: Story = {
  args: {
    onFinish: (email, _kdfSettings, rememberMe) => {
      mockSuccessfulPrelogin(email, rememberMe);
    },
  },
};

// Interactive demo with remember me functionality
export const RememberMeDemo: Story = {
  args: {
    onFinish: (email, _kdfSettings, rememberMe) => {
      mockSuccessfulPrelogin(email, rememberMe);
    },
  },
  render: (args) => {
    const [lastSubmission, setLastSubmission] = React.useState<{
      email: string;
      rememberMe: boolean;
    } | null>(null);

    const handleFinish = (email: string, kdfSettings: PreloginResponse, rememberMe: boolean) => {
      setLastSubmission({ email, rememberMe });
      args.onFinish(email, kdfSettings, rememberMe);
    };

    return (
      <div className="space-y-4">
        <PreLogin {...args} onFinish={handleFinish} />
        {lastSubmission && (
          <div className="p-4 bg-success/10 border border-success/20 rounded-lg">
            <h4 className="font-medium text-success mb-2">Form Submitted Successfully!</h4>
            <div className="text-sm space-y-1">
              <div>
                <strong>Email:</strong> {lastSubmission.email}
              </div>
              <div>
                <strong>Remember Me:</strong> {lastSubmission.rememberMe ? "Yes" : "No"}
              </div>
            </div>
          </div>
        )}
        <div className="text-center text-sm text-muted-foreground">
          Try toggling the "Remember me" checkbox and submitting the form
        </div>
      </div>
    );
  },
  parameters: {
    docs: {
      description: {
        story:
          "Interactive demo showing the remember me checkbox functionality with form submission feedback",
      },
    },
  },
};

// Loading state simulation
export const LoadingState: Story = {
  args: {
    onFinish: (email, _kdfSettings, rememberMe) => {
      mockSuccessfulPrelogin(email, rememberMe);
    },
  },
  render: (args) => {
    const [isSubmitting, setIsSubmitting] = React.useState(false);

    const handleSubmit = () => {
      setIsSubmitting(true);
      // Simulate loading for 3 seconds
      setTimeout(() => setIsSubmitting(false), 3000);
    };

    return (
      <div>
        <PreLogin {...args} />
        {!isSubmitting && (
          <div className="mt-4 text-center">
            <button
              type="button"
              onClick={handleSubmit}
              className="text-sm text-primary hover:text-primary/80 underline"
            >
              Simulate Prelogin Loading
            </button>
          </div>
        )}
      </div>
    );
  },
  parameters: {
    docs: {
      description: {
        story: "Demonstrates the loading state with spinner and disabled form",
      },
    },
  },
};

// Error state simulation
export const ErrorState: Story = {
  args: {
    onFinish: (email, _kdfSettings, rememberMe) => {
      mockSuccessfulPrelogin(email, rememberMe);
    },
  },
  render: (args) => {
    return (
      <div>
        <PreLogin {...args} />
        <div className="mt-4 text-center text-sm text-muted-foreground">
          Try entering an invalid email to see error handling
        </div>
      </div>
    );
  },
  parameters: {
    docs: {
      description: {
        story: "Form with error handling - try entering invalid email format",
      },
    },
  },
};

// Dark mode
export const DarkMode: Story = {
  args: {
    onFinish: (email, _kdfSettings, rememberMe) => {
      mockSuccessfulPrelogin(email, rememberMe);
    },
  },
  decorators: [
    (Story) => (
      <div className="dark min-h-screen bg-background flex items-center justify-center p-4">
        <div className="w-full max-w-md">
          <Story />
        </div>
      </div>
    ),
  ],
  parameters: {
    docs: {
      description: {
        story: "Prelogin form in dark mode with proper theme colors",
      },
    },
  },
};

// Mobile viewport
export const Mobile: Story = {
  args: {
    onFinish: (email, _kdfSettings, rememberMe) => {
      mockSuccessfulPrelogin(email, rememberMe);
    },
  },
  parameters: {
    viewport: {
      defaultViewport: "mobile1",
    },
    docs: {
      description: {
        story: "Prelogin form optimized for mobile devices",
      },
    },
  },
};

// Accessibility test
export const AccessibilityTest: Story = {
  args: {
    onFinish: (email, _kdfSettings, rememberMe) => {
      mockSuccessfulPrelogin(email, rememberMe);
    },
  },
  parameters: {
    docs: {
      description: {
        story: "Test keyboard navigation, screen reader support, and focus management",
      },
    },
  },
  render: (args) => (
    <div>
      <PreLogin {...args} />
      <div className="mt-6 p-4 bg-muted/30 rounded-lg text-sm text-muted-foreground">
        <h3 className="font-medium mb-2">Accessibility Features:</h3>
        <ul className="space-y-1 text-xs">
          <li>• Tab navigation through all interactive elements</li>
          <li>• ARIA labels for form inputs and checkbox</li>
          <li>• Proper form validation with screen reader announcements</li>
          <li>• Focus management on form submission errors</li>
          <li>• High contrast focus indicators</li>
          <li>• Remember me checkbox with descriptive label</li>
        </ul>
      </div>
    </div>
  ),
};
