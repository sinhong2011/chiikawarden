import type { Meta, StoryObj } from "@storybook/react";
import { ExternalLink } from "lucide-react";
import { Link } from "./link";

const meta: Meta<typeof Link> = {
  title: "UI/Navigation/Link",
  component: Link,
  parameters: {
    layout: "centered",
    docs: {
      description: {
        component:
          "A flexible link component built on HeroUI Link. Features multiple variants, sizes, and states. Supports both internal and external links with proper accessibility.",
      },
    },
  },
  tags: ["autodocs"],
  argTypes: {
    variant: {
      control: "select",
      options: ["primary", "secondary", "accent", "neutral", "ghost", "underline"],
      description: "Visual style variant of the link",
    },
    size: {
      control: "select",
      options: ["sm", "md", "lg"],
      description: "Size of the link text",
    },
    disabled: {
      control: "boolean",
      description: "Whether the link is disabled",
    },
    external: {
      control: "boolean",
      description: "Whether the link opens in a new tab with security attributes",
    },
    href: {
      control: "text",
      description: "URL or path the link points to",
    },
    children: {
      control: "text",
      description: "Link content",
    },
  },
};

export default meta;
type Story = StoryObj<typeof Link>;

// Default story
export const Default: Story = {
  args: {
    href: "#",
    children: "Default Link",
    variant: "primary",
    size: "md",
  },
};

// Variants
export const Variants: Story = {
  render: () => (
    <div className="flex flex-wrap gap-4">
      <Link href="#" variant="primary">
        Primary Link
      </Link>
      <Link href="#" variant="secondary">
        Secondary Link
      </Link>
      <Link href="#" variant="accent">
        Accent Link
      </Link>
      <Link href="#" variant="neutral">
        Neutral Link
      </Link>
      <Link href="#" variant="ghost">
        Ghost Link
      </Link>
      <Link href="#" variant="underline">
        Underlined Link
      </Link>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Different visual styles for various use cases.",
      },
    },
  },
};

// Sizes
export const Sizes: Story = {
  render: () => (
    <div className="flex flex-wrap items-center gap-4">
      <Link href="#" size="sm">
        Small Link
      </Link>
      <Link href="#" size="md">
        Medium Link
      </Link>
      <Link href="#" size="lg">
        Large Link
      </Link>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Different sizes for various contexts.",
      },
    },
  },
};

// States
export const States: Story = {
  render: () => (
    <div className="flex flex-wrap gap-4">
      <Link href="#" variant="primary">
        Normal Link
      </Link>
      <Link href="#" variant="primary" disabled>
        Disabled Link
      </Link>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Different states including disabled.",
      },
    },
  },
};

// External Links
export const External: Story = {
  render: () => (
    <div className="flex flex-wrap gap-4">
      <Link href="https://heroui.com" external>
        HeroUI Documentation
      </Link>
      <Link href="https://github.com" external variant="secondary">
        <span className="flex items-center gap-1">
          GitHub
          <ExternalLink size={14} />
        </span>
      </Link>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: 'External links automatically get target="_blank" and security attributes.',
      },
    },
  },
};

// Navigation Example
export const Navigation: Story = {
  render: () => (
    <div className="space-y-4">
      <div className="flex gap-4">
        <Link href="/dashboard" variant="primary">
          Dashboard
        </Link>
        <Link href="/settings" variant="ghost">
          Settings
        </Link>
        <Link href="/profile" variant="underline">
          Profile
        </Link>
      </div>

      <div className="flex gap-2 text-sm">
        <Link href="/" variant="ghost" size="sm">
          Home
        </Link>
        <span className="text-gray-400">/</span>
        <Link href="/products" variant="ghost" size="sm">
          Products
        </Link>
        <span className="text-gray-400">/</span>
        <span className="text-gray-600">Current Page</span>
      </div>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Examples of links used in navigation contexts.",
      },
    },
  },
};

// Real-world Usage
export const RealWorldUsage: Story = {
  render: () => (
    <div className="space-y-6 max-w-md">
      {/* Login page style */}
      <div className="p-4 bg-gray-50 dark:bg-gray-800 rounded-lg">
        <div className="flex justify-center gap-2">
          <p className="text-base text-gray-600 dark:text-gray-400">Don't have an account?</p>
          <Link href="/signup" className="text-base text-primary hover:text-primary/80 font-medium">
            Sign up
          </Link>
        </div>
      </div>

      {/* Article content style */}
      <div className="p-4 bg-white dark:bg-gray-800 rounded-lg border">
        <p className="text-gray-700 dark:text-gray-300">
          This is some article content with an{" "}
          <Link href="#" variant="underline">
            inline link
          </Link>{" "}
          that demonstrates how links work within text content. You can also{" "}
          <Link href="https://example.com" external variant="primary">
            visit external resources
          </Link>{" "}
          for more information.
        </p>
      </div>

      {/* Footer style */}
      <div className="p-4 bg-gray-100 dark:bg-gray-900 rounded-lg">
        <div className="flex flex-wrap gap-6 text-sm">
          <Link href="/about" variant="ghost" size="sm">
            About
          </Link>
          <Link href="/privacy" variant="ghost" size="sm">
            Privacy Policy
          </Link>
          <Link href="/terms" variant="ghost" size="sm">
            Terms of Service
          </Link>
          <Link href="/contact" variant="ghost" size="sm">
            Contact
          </Link>
        </div>
      </div>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Real-world usage examples showing how links integrate into different UI contexts.",
      },
    },
  },
};

// Interactive Playground
export const InteractivePlayground: Story = {
  args: {
    href: "#",
    children: "Interactive Link",
    variant: "primary",
    size: "md",
    disabled: false,
    external: false,
  },
  parameters: {
    docs: {
      description: {
        story: "Interactive playground to test all Link component props and configurations.",
      },
    },
  },
};
