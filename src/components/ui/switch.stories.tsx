import type { Meta, StoryObj } from "@storybook/react";
import React from "react";
import { Switch } from "./switch";

const meta: Meta<typeof Switch> = {
  title: "UI/Switch",
  component: Switch,
  parameters: {
    layout: "centered",
    docs: {
      description: {
        component:
          "A standalone toggle switch component built on HeroUI Switch with support for different sizes, states, and validation. Can be used independently in any context, not just within forms.",
      },
    },
  },
  tags: ["autodocs"],
  argTypes: {
    name: {
      control: "text",
      description: "The name attribute for the switch input",
    },
    label: {
      control: "text",
      description: "The label text displayed next to the switch",
    },
    description: {
      control: "text",
      description: "Optional description text shown below the label",
    },
    checked: {
      control: "boolean",
      description: "Whether the switch is checked/on",
    },
    error: {
      control: "text",
      description: "Error message to display below the switch",
    },
    required: {
      control: "boolean",
      description: "Whether the switch is required",
    },
    disabled: {
      control: "boolean",
      description: "Whether the switch is disabled",
    },
    size: {
      control: "select",
      options: ["sm", "md", "lg"],
      description: "The size of the switch",
    },
  },
};

export default meta;
type Story = StoryObj<typeof Switch>;

// Interactive wrapper component for stories
interface SwitchWrapperProps {
  checked?: boolean;
  [key: string]: unknown;
}

const SwitchWrapper = (props: SwitchWrapperProps) => {
  const [checked, setChecked] = React.useState(props.checked || false);

  return (
    <div className="w-80">
      <Switch
        label={(props.label as string) || "Switch"}
        {...props}
        checked={checked}
        onCheckedChange={setChecked}
      />
    </div>
  );
};

// Default story
export const Default: Story = {
  render: (args) => <SwitchWrapper {...args} />,
  args: {
    name: "default",
    label: "Enable notifications",
    description: "",
    error: "",
    checked: false,
    required: false,
    disabled: false,
    size: "md",
  },
};

// Sizes
export const Small: Story = {
  render: (args) => <SwitchWrapper {...args} />,
  args: {
    name: "small",
    label: "Small switch",
    description: "This is a small-sized switch",
    size: "sm",
    error: "",
  },
};

export const Medium: Story = {
  render: (args) => <SwitchWrapper {...args} />,
  args: {
    name: "medium",
    label: "Medium switch",
    description: "This is a medium-sized switch (default)",
    size: "md",
    error: "",
  },
};

export const Large: Story = {
  render: (args) => <SwitchWrapper {...args} />,
  args: {
    name: "large",
    label: "Large switch",
    description: "This is a large-sized switch",
    size: "lg",
    error: "",
  },
};

// States
export const Checked: Story = {
  render: (args) => <SwitchWrapper {...args} />,
  args: {
    name: "checked",
    label: "This switch is on",
    description: "The switch starts in the checked/on state",
    checked: true,
    error: "",
  },
};

export const WithDescription: Story = {
  render: (args) => <SwitchWrapper {...args} />,
  args: {
    name: "description",
    label: "Advanced mode",
    description: "Enable advanced features and configuration options",
    error: "",
  },
};

export const Required: Story = {
  render: (args) => <SwitchWrapper {...args} />,
  args: {
    name: "required",
    label: "Accept terms and conditions",
    description: "You must accept the terms to continue",
    required: true,
    error: "",
  },
};

export const Disabled: Story = {
  render: (args) => <SwitchWrapper {...args} />,
  args: {
    name: "disabled",
    label: "Disabled switch",
    description: "This switch cannot be toggled",
    disabled: true,
    error: "",
  },
};

export const WithError: Story = {
  render: (args) => <SwitchWrapper {...args} />,
  args: {
    name: "error",
    label: "Privacy settings",
    description: "Configure your privacy preferences",
    error: "You must enable privacy settings to continue",
  },
};

// Size comparison
export const SizeComparison: Story = {
  render: () => (
    <div className="space-y-6 w-96">
      <h3 className="text-lg font-semibold">Switch Sizes</h3>
      <SwitchWrapper
        name="size-sm"
        label="Small switch"
        description="Small size (sm)"
        size="sm"
        error=""
      />
      <SwitchWrapper
        name="size-md"
        label="Medium switch"
        description="Medium size (md) - default"
        size="md"
        error=""
      />
      <SwitchWrapper
        name="size-lg"
        label="Large switch"
        description="Large size (lg)"
        size="lg"
        error=""
      />
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Comparison of all available switch sizes",
      },
    },
  },
};

// Settings form example
export const SettingsForm: Story = {
  render: () => (
    <div className="w-96 space-y-6 p-6 bg-base-100 rounded-lg border">
      <h3 className="text-lg font-semibold mb-4">Application Settings</h3>
      <SwitchWrapper
        name="notifications"
        label="Push notifications"
        description="Receive push notifications for important updates"
        checked={true}
        error=""
      />
      <SwitchWrapper
        name="dark-mode"
        label="Dark mode"
        description="Use dark theme for better viewing in low light"
        error=""
      />
      <SwitchWrapper
        name="analytics"
        label="Analytics"
        description="Help improve the app by sharing anonymous usage data"
        checked={true}
        error=""
      />
      <SwitchWrapper
        name="auto-backup"
        label="Automatic backup"
        description="Automatically backup your data to the cloud"
        required={true}
        error=""
      />
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Example of switches used in a settings form",
      },
    },
  },
};

// Interactive playground
export const InteractivePlayground: Story = {
  render: (args) => <SwitchWrapper {...args} />,
  args: {
    name: "playground",
    label: "Interactive Switch",
    description: "Use the controls panel to test different configurations",
    checked: false,
    error: "",
    required: false,
    disabled: false,
    size: "md",
  },
  parameters: {
    docs: {
      description: {
        story: "Interactive playground to test all Switch component props and configurations.",
      },
    },
  },
};
