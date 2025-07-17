import type { Meta, StoryObj } from "@storybook/react";
import React from "react";
import { TextInput } from "./text-input";

const meta: Meta<typeof TextInput> = {
  title: "UI/Form/TextInput",
  component: TextInput,
  parameters: {
    layout: "centered",
    docs: {
      description: {
        component:
          "A flexible text input component built on HeroUI Input. Supports various input types, sizes, variants, and includes built-in validation display.",
      },
    },
  },
  tags: ["autodocs"],
  argTypes: {
    type: {
      control: "select",
      options: ["text", "email", "tel", "password", "url", "date"],
      description: "The input type",
    },
    size: {
      control: "select",
      options: ["sm", "md", "lg"],
      description: "The size of the input",
    },
    variant: {
      control: "select",
      options: ["flat", "bordered", "faded", "underlined"],
      description: "The visual style variant (Hero UI native)",
    },
    label: {
      control: "text",
      description: "The label text",
    },
    placeholder: {
      control: "text",
      description: "Placeholder text",
    },
    error: {
      control: "text",
      description: "Error message to display",
    },
    required: {
      control: "boolean",
      description: "Whether the field is required",
    },
    disabled: {
      control: "boolean",
      description: "Whether the input is disabled",
    },
  },
};

export default meta;
type Story = StoryObj<typeof TextInput>;

// Interactive wrapper component for stories
interface TextInputWrapperProps {
  value?: string;
  [key: string]: unknown;
}

const TextInputWrapper = (props: TextInputWrapperProps) => {
  const [value, setValue] = React.useState(props.value || "");

  return (
    <div className="w-80">
      <TextInput
        name={(props.name as string) || "input"}
        error={(props.error as string) || ""}
        {...props}
        value={value}
        onChange={(e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
          setValue(e.target.value)
        }
        onBlur={() => {}}
      />
    </div>
  );
};

// Default story
export const Default: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "default",
    label: "Text Input",
    placeholder: "Enter text...",
    error: "",
    type: "text",
    size: "md",
    variant: "flat",
  },
};

// Input Types
export const Email: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "email",
    type: "email",
    label: "Email Address",
    placeholder: "user@example.com",
    error: "",
  },
};

export const Password: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "password",
    type: "password",
    label: "Password",
    placeholder: "Enter your password",
    error: "",
  },
};

export const Phone: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "phone",
    type: "tel",
    label: "Phone Number",
    placeholder: "+1 (555) 123-4567",
    error: "",
  },
};

export const URL: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "url",
    type: "url",
    label: "Website URL",
    placeholder: "https://example.com",
    error: "",
  },
};

export const DateInput: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "date",
    type: "date",
    label: "Date of Birth",
    error: "",
  },
};

// Sizes
export const Small: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "small",
    size: "sm",
    label: "Small Input",
    placeholder: "Small size...",
    error: "",
  },
};

export const Medium: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "medium",
    size: "md",
    label: "Medium Input",
    placeholder: "Medium size...",
    error: "",
  },
};

export const Large: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "large",
    size: "lg",
    label: "Large Input",
    placeholder: "Large size...",
    error: "",
  },
};

// Variants
export const FlatVariant: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "flat-variant",
    variant: "flat",
    label: "Flat Variant",
    placeholder: "Flat styling...",
    error: "",
  },
};

export const Faded: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "faded",
    variant: "faded",
    label: "Faded Variant",
    placeholder: "Faded background...",
    error: "",
  },
};

export const Bordered: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "bordered",
    variant: "bordered",
    label: "Bordered Variant",
    placeholder: "Bordered styling...",
    error: "",
  },
};

// States
export const WithError: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "error",
    label: "Email Address",
    placeholder: "user@example.com",
    value: "invalid-email",
    error: "Please enter a valid email address",
    type: "email",
  },
};

export const Required: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "required",
    label: "Full Name",
    placeholder: "Enter your full name",
    required: true,
    error: "",
  },
};

export const Disabled: Story = {
  render: (args) => <TextInputWrapper {...args} />,
  args: {
    name: "disabled",
    label: "Disabled Input",
    placeholder: "This field is disabled",
    disabled: true,
    value: "Cannot edit this",
    error: "",
  },
};

// Note: For multiline text input, use the TextArea component instead

// Complex examples
export const LoginForm: Story = {
  render: () => (
    <div className="w-96 space-y-4 p-6 bg-base-100 rounded-lg border">
      <h2 className="text-xl font-semibold mb-4">Login</h2>
      <TextInputWrapper
        name="login-email"
        type="email"
        label="Email Address"
        placeholder="user@example.com"
        required={true}
        error=""
      />
      <TextInputWrapper
        name="login-password"
        type="password"
        label="Password"
        placeholder="Enter your password"
        required={true}
        error=""
      />
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Example of text inputs used in a login form",
      },
    },
  },
};

export const AllSizes: Story = {
  render: () => (
    <div className="w-96 space-y-4">
      <TextInputWrapper
        name="size-sm"
        size="sm"
        label="Small"
        placeholder="Small input..."
        error=""
      />
      <TextInputWrapper
        name="size-md"
        size="md"
        label="Medium"
        placeholder="Medium input..."
        error=""
      />
      <TextInputWrapper
        name="size-lg"
        size="lg"
        label="Large"
        placeholder="Large input..."
        error=""
      />
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Comparison of all available input sizes",
      },
    },
  },
};

export const AllVariants: Story = {
  render: () => (
    <div className="w-96 space-y-4">
      <TextInputWrapper
        name="variant-flat"
        variant="flat"
        label="Flat"
        placeholder="Flat variant..."
        error=""
      />
      <TextInputWrapper
        name="variant-bordered"
        variant="bordered"
        label="Bordered"
        placeholder="Bordered variant..."
        error=""
      />
      <TextInputWrapper
        name="variant-faded"
        variant="faded"
        label="Faded"
        placeholder="Faded variant..."
        error=""
      />
      <TextInputWrapper
        name="variant-underlined"
        variant="underlined"
        label="Underlined"
        placeholder="Underlined variant..."
        error=""
      />
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "All available input variants displayed together",
      },
    },
  },
};
