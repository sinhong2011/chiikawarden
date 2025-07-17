import type { Meta, StoryObj } from "@storybook/react";
import React from "react";
import { Checkbox } from "./checkbox";

const meta: Meta<typeof Checkbox> = {
  title: "UI/Form/Checkbox",
  component: Checkbox,
  parameters: {
    layout: "centered",
    docs: {
      description: {
        component:
          "A checkbox component built on HeroUI with support for various sizes, states, and validation. Features accessible design and smooth animations.",
      },
    },
  },
  tags: ["autodocs"],
  argTypes: {
    size: {
      control: "select",
      options: ["sm", "md", "lg"],
      description: "The size of the checkbox",
    },
    label: {
      control: "text",
      description: "The label text for the checkbox",
    },
    description: {
      control: "text",
      description: "Optional description text",
    },
    error: {
      control: "text",
      description: "Error message to display",
    },
    required: {
      control: "boolean",
      description: "Whether the checkbox is required",
    },
    disabled: {
      control: "boolean",
      description: "Whether the checkbox is disabled",
    },
    checked: {
      control: "boolean",
      description: "Whether the checkbox is checked",
    },
  },
};

export default meta;
type Story = StoryObj<typeof Checkbox>;

// Interactive wrapper component for stories
interface CheckboxWrapperProps {
  checked?: boolean;
  [key: string]: unknown;
}

const CheckboxWrapper = (props: CheckboxWrapperProps) => {
  const [checked, setChecked] = React.useState(props.checked || false);

  return (
    <div className="w-80">
      <Checkbox
        {...props}
        checked={checked}
        onChange={(e) => setChecked(e.target.checked)}
        name="checkbox"
        label="Checkbox"
        error={props.error as string}
      />
    </div>
  );
};

// Default story
export const Default: Story = {
  render: (args) => <CheckboxWrapper {...args} />,
  args: {
    name: "default",
    label: "Accept terms and conditions",
    description: "",
    error: "",
    size: "md",
    checked: false,
    required: false,
    disabled: false,
  },
};

// Sizes
export const Small: Story = {
  render: (args) => <CheckboxWrapper {...args} />,
  args: {
    name: "small",
    size: "sm",
    label: "Small checkbox",
    description: "This is a small checkbox",
    error: "",
  },
};

export const Medium: Story = {
  render: (args) => <CheckboxWrapper {...args} />,
  args: {
    name: "medium",
    size: "md",
    label: "Medium checkbox",
    description: "This is a medium checkbox",
    error: "",
  },
};

export const Large: Story = {
  render: (args) => <CheckboxWrapper {...args} />,
  args: {
    name: "large",
    size: "lg",
    label: "Large checkbox",
    description: "This is a large checkbox",
    error: "",
  },
};

// States
export const Checked: Story = {
  render: (args) => <CheckboxWrapper {...args} />,
  args: {
    name: "checked",
    label: "This checkbox is checked",
    checked: true,
    error: "",
  },
};

export const WithDescription: Story = {
  render: (args) => <CheckboxWrapper {...args} />,
  args: {
    name: "description",
    label: "Enable notifications",
    description: "Receive email notifications about important updates and changes to your account.",
    error: "",
  },
};

export const Required: Story = {
  render: (args) => <CheckboxWrapper {...args} />,
  args: {
    name: "required",
    label: "I agree to the terms of service",
    description: "Please read and accept our terms of service before proceeding.",
    required: true,
    error: "",
  },
};

export const WithError: Story = {
  render: (args) => <CheckboxWrapper {...args} />,
  args: {
    name: "error",
    label: "I agree to the privacy policy",
    description: "You must agree to our privacy policy to continue.",
    required: true,
    checked: false,
    error: "You must accept the privacy policy to proceed",
  },
};

export const Disabled: Story = {
  render: (args) => <CheckboxWrapper {...args} />,
  args: {
    name: "disabled",
    label: "This option is currently unavailable",
    description: "This feature will be available in a future update.",
    disabled: true,
    error: "",
  },
};

export const DisabledChecked: Story = {
  render: (args) => <CheckboxWrapper {...args} />,
  args: {
    name: "disabled-checked",
    label: "This option is permanently enabled",
    description: "This setting cannot be changed due to your current plan.",
    disabled: true,
    checked: true,
    error: "",
  },
};

// Complex examples
export const PrivacySettings: Story = {
  render: () => (
    <div className="w-96 space-y-4 p-6 bg-base-100 rounded-lg border">
      <h3 className="text-lg font-semibold mb-4">Privacy Settings</h3>
      <CheckboxWrapper
        name="analytics"
        label="Allow analytics"
        description="Help us improve our service by sharing anonymous usage data."
        checked={true}
        error=""
      />
      <CheckboxWrapper
        name="marketing"
        label="Marketing emails"
        description="Receive updates about new features and special offers."
        checked={false}
        error=""
      />
      <CheckboxWrapper
        name="required-legal"
        label="Legal notices"
        description="Required notifications about policy changes and legal updates."
        required={true}
        checked={true}
        disabled={true}
        error=""
      />
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Example of checkboxes used in a privacy settings form",
      },
    },
  },
};

export const FormValidation: Story = {
  render: () => (
    <div className="w-96 space-y-4 p-6 bg-base-100 rounded-lg border">
      <h3 className="text-lg font-semibold mb-4">Sign Up</h3>
      <CheckboxWrapper
        name="terms"
        label="I agree to the Terms of Service"
        required={true}
        checked={false}
        error="You must accept the terms to create an account"
      />
      <CheckboxWrapper
        name="privacy"
        label="I accept the Privacy Policy"
        required={true}
        checked={true}
        error=""
      />
      <CheckboxWrapper
        name="newsletter"
        label="Subscribe to newsletter"
        description="Get the latest updates and news delivered to your inbox."
        checked={false}
        error=""
      />
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Example showing form validation with required checkboxes",
      },
    },
  },
};

export const AllSizes: Story = {
  render: () => (
    <div className="w-96 space-y-4">
      <CheckboxWrapper name="size-sm" size="sm" label="Small checkbox" error="" />
      <CheckboxWrapper name="size-md" size="md" label="Medium checkbox" error="" />
      <CheckboxWrapper name="size-lg" size="lg" label="Large checkbox" error="" />
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Comparison of all available checkbox sizes",
      },
    },
  },
};

export const AllStates: Story = {
  render: () => (
    <div className="w-96 space-y-4">
      <CheckboxWrapper name="state-default" label="Default state" checked={false} error="" />
      <CheckboxWrapper name="state-checked" label="Checked state" checked={true} error="" />
      <CheckboxWrapper
        name="state-disabled"
        label="Disabled state"
        disabled={true}
        checked={false}
        error=""
      />
      <CheckboxWrapper
        name="state-disabled-checked"
        label="Disabled checked state"
        disabled={true}
        checked={true}
        error=""
      />
      <CheckboxWrapper
        name="state-error"
        label="Error state"
        checked={false}
        error="This field has an error"
      />
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "All available checkbox states displayed together",
      },
    },
  },
};
