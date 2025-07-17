import { Button } from "@heroui/button";
import type { Meta, StoryObj } from "@storybook/react";
import React from "react";
import { Modal } from "./modal";

const meta: Meta<typeof Modal> = {
  title: "UI/Layout/Modal",
  component: Modal,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "A flexible modal component built on HeroUI Modal. Features multiple sizes, animation options, and accessibility support. Can be used for confirmations, forms, and content display.",
      },
    },
  },
  tags: ["autodocs"],
  argTypes: {
    size: {
      control: "select",
      options: ["sm", "md", "lg", "xl", "full"],
      description: "The size of the modal",
    },
    title: {
      control: "text",
      description: "The modal title",
    },
    description: {
      control: "text",
      description: "Optional description text",
    },
    showCloseButton: {
      control: "boolean",
      description: "Whether to show the close button",
    },
    closeOnOverlayClick: {
      control: "boolean",
      description: "Whether clicking the overlay closes the modal",
    },
    closeOnEscape: {
      control: "boolean",
      description: "Whether pressing escape closes the modal",
    },
    animateHeight: {
      control: "boolean",
      description: "Whether to animate height changes",
    },
    heightAnimationType: {
      control: "select",
      options: ["smooth", "spring", "bounce", "fast", "slow"],
      description: "The type of height animation",
    },
  },
};

export default meta;
type Story = StoryObj<typeof Modal>;

// Interactive wrapper component for stories
interface ModalWrapperProps {
  children?: React.ReactNode;
  [key: string]: unknown;
}

const ModalWrapper = (props: ModalWrapperProps) => {
  const [open, setOpen] = React.useState(false);

  return (
    <div className="p-8">
      <Button onPress={() => setOpen(true)}>Open Modal</Button>
      <Modal {...props} open={open} onOpenChange={setOpen}>
        {props.children || (
          <div className="space-y-4">
            <p className="text-base-content">
              This is the modal content. You can put any content here including forms, images, or
              complex layouts.
            </p>
            <div className="flex justify-end gap-2">
              <Button variant="bordered" onPress={() => setOpen(false)}>
                Cancel
              </Button>
              <Button onPress={() => setOpen(false)}>Confirm</Button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
};

// Default story
export const Default: Story = {
  render: (args) => <ModalWrapper {...args} />,
  args: {
    title: "Modal Title",
    description: "This is a description of what this modal does.",
    size: "md",
    showCloseButton: true,
    closeOnOverlayClick: true,
    closeOnEscape: true,
    animateHeight: false,
  },
};

// Sizes
export const Small: Story = {
  render: (args) => <ModalWrapper {...args} />,
  args: {
    title: "Small Modal",
    size: "sm",
    children: (
      <div className="space-y-4">
        <p className="text-base-content">This is a small modal for simple confirmations.</p>
        <div className="flex justify-end gap-2">
          <Button variant="bordered" size="sm">
            Cancel
          </Button>
          <Button size="sm">OK</Button>
        </div>
      </div>
    ),
  },
};

export const Medium: Story = {
  render: (args) => <ModalWrapper {...args} />,
  args: {
    title: "Medium Modal",
    size: "md",
    children: (
      <div className="space-y-4">
        <p className="text-base-content">
          This is a medium modal suitable for most use cases. It provides a good balance between
          content space and screen real estate.
        </p>
        <div className="flex justify-end gap-2">
          <Button variant="bordered">Cancel</Button>
          <Button>Save</Button>
        </div>
      </div>
    ),
  },
};

export const Large: Story = {
  render: (args) => <ModalWrapper {...args} />,
  args: {
    title: "Large Modal",
    size: "lg",
    children: (
      <div className="space-y-4">
        <p className="text-base-content">
          This is a large modal for complex forms or detailed content. It provides ample space for
          extensive information and multiple form fields.
        </p>
        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-2">
            <label htmlFor="firstName" className="text-sm font-medium">
              First Name
            </label>
            <input
              id="firstName"
              className="w-full px-3 py-2 border rounded-md"
              placeholder="Enter first name"
            />
          </div>
          <div className="space-y-2">
            <label htmlFor="lastName" className="text-sm font-medium">
              Last Name
            </label>
            <input
              id="lastName"
              className="w-full px-3 py-2 border rounded-md"
              placeholder="Enter last name"
            />
          </div>
        </div>
        <div className="flex justify-end gap-2">
          <Button variant="bordered">Cancel</Button>
          <Button>Save</Button>
        </div>
      </div>
    ),
  },
};

export const ExtraLarge: Story = {
  render: (args) => <ModalWrapper {...args} />,
  args: {
    title: "Extra Large Modal",
    size: "xl",
    children: (
      <div className="space-y-6">
        <p className="text-base-content">
          This is an extra large modal for complex layouts, data tables, or detailed content views.
        </p>
        <div className="grid grid-cols-3 gap-4">
          {Array.from({ length: 6 }, (_, i) => (
            <div key={`section-${Date.now()}-${i}`} className="p-4 border rounded-lg">
              <h4 className="font-medium mb-2">Section {i + 1}</h4>
              <p className="text-sm text-base-content/70">Content for section {i + 1}</p>
            </div>
          ))}
        </div>
        <div className="flex justify-end gap-2">
          <Button variant="bordered">Cancel</Button>
          <Button>Save All</Button>
        </div>
      </div>
    ),
  },
};

export const FullScreen: Story = {
  render: (args) => <ModalWrapper {...args} />,
  args: {
    title: "Full Screen Modal",
    size: "full",
    children: (
      <div className="space-y-6">
        <p className="text-base-content">
          This is a full screen modal that takes up most of the viewport. Ideal for complex
          applications or detailed workflows.
        </p>
        <div className="grid grid-cols-4 gap-4">
          {Array.from({ length: 12 }, (_, i) => (
            <div
              key={`item-${Date.now()}-${i}`}
              className="aspect-square bg-base-200 rounded-lg p-4 flex items-center justify-center"
            >
              <span className="text-sm font-medium">Item {i + 1}</span>
            </div>
          ))}
        </div>
        <div className="flex justify-end gap-2">
          <Button variant="bordered">Cancel</Button>
          <Button>Apply Changes</Button>
        </div>
      </div>
    ),
  },
};

// No Close Button
export const NoCloseButton: Story = {
  render: (args) => <ModalWrapper {...args} />,
  args: {
    title: "Confirmation Required",
    showCloseButton: false,
    closeOnOverlayClick: false,
    closeOnEscape: false,
    children: (
      <div className="space-y-4">
        <p className="text-base-content">
          This action cannot be undone. Are you sure you want to delete this item?
        </p>
        <div className="flex justify-end gap-2">
          <Button variant="bordered">Cancel</Button>
          <Button color="danger">Delete</Button>
        </div>
      </div>
    ),
  },
};

// Animation Examples
export const WithHeightAnimation: Story = {
  render: () => {
    const [open, setOpen] = React.useState(false);
    const [showExtra, setShowExtra] = React.useState(false);

    return (
      <div className="p-8">
        <Button onPress={() => setOpen(true)}>Open Animated Modal</Button>
        <Modal
          open={open}
          onOpenChange={setOpen}
          title="Height Animation Demo"
          animateHeight={true}
          heightAnimationType="smooth"
        >
          <div className="space-y-4">
            <p className="text-base-content">
              This modal demonstrates height animation. Click the button below to see the content
              expand.
            </p>
            <Button onPress={() => setShowExtra(!showExtra)}>
              {showExtra ? "Hide" : "Show"} Extra Content
            </Button>
            {showExtra && (
              <div className="space-y-4 p-4 bg-base-200 rounded-lg">
                <h4 className="font-medium">Extra Content</h4>
                <p className="text-sm text-base-content/70">
                  This content appears with a smooth height animation. The modal container
                  automatically adjusts its height to accommodate the new content.
                </p>
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <label htmlFor="field1" className="text-sm font-medium">
                      Field 1
                    </label>
                    <input id="field1" className="w-full px-3 py-2 border rounded-md" />
                  </div>
                  <div className="space-y-2">
                    <label htmlFor="field2" className="text-sm font-medium">
                      Field 2
                    </label>
                    <input id="field2" className="w-full px-3 py-2 border rounded-md" />
                  </div>
                </div>
              </div>
            )}
            <div className="flex justify-end gap-2">
              <Button variant="bordered" onPress={() => setOpen(false)}>
                Close
              </Button>
            </div>
          </div>
        </Modal>
      </div>
    );
  },
  parameters: {
    docs: {
      description: {
        story: "Modal with smooth height animation when content changes",
      },
    },
  },
};

// Form Modal Example
export const FormModal: Story = {
  render: () => {
    const [open, setOpen] = React.useState(false);

    return (
      <div className="p-8">
        <Button onPress={() => setOpen(true)}>Add New User</Button>
        <Modal
          open={open}
          onOpenChange={setOpen}
          title="Add New User"
          description="Fill in the details to create a new user account"
          size="lg"
        >
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <label htmlFor="firstNameReq" className="text-sm font-medium">
                  First Name *
                </label>
                <input
                  id="firstNameReq"
                  className="w-full px-3 py-2 border rounded-md"
                  placeholder="John"
                />
              </div>
              <div className="space-y-2">
                <label htmlFor="lastNameReq" className="text-sm font-medium">
                  Last Name *
                </label>
                <input
                  id="lastNameReq"
                  className="w-full px-3 py-2 border rounded-md"
                  placeholder="Doe"
                />
              </div>
            </div>
            <div className="space-y-2">
              <label htmlFor="emailReq" className="text-sm font-medium">
                Email Address *
              </label>
              <input
                id="emailReq"
                className="w-full px-3 py-2 border rounded-md"
                type="email"
                placeholder="john.doe@example.com"
              />
            </div>
            <div className="space-y-2">
              <label htmlFor="roleSelect" className="text-sm font-medium">
                Role
              </label>
              <select id="roleSelect" className="w-full px-3 py-2 border rounded-md">
                <option>User</option>
                <option>Admin</option>
                <option>Manager</option>
              </select>
            </div>
            <div className="flex items-center gap-2">
              <input type="checkbox" id="send-invite" />
              <label htmlFor="send-invite" className="text-sm">
                Send invitation email
              </label>
            </div>
            <div className="flex justify-end gap-2 pt-4">
              <Button variant="bordered" onPress={() => setOpen(false)}>
                Cancel
              </Button>
              <Button onPress={() => setOpen(false)}>Create User</Button>
            </div>
          </div>
        </Modal>
      </div>
    );
  },
  parameters: {
    docs: {
      description: {
        story: "Example of using a modal for form input",
      },
    },
  },
};

// Confirmation Modal
export const ConfirmationModal: Story = {
  render: () => {
    const [open, setOpen] = React.useState(false);

    return (
      <div className="p-8">
        <Button variant="solid" onPress={() => setOpen(true)}>
          Delete Account
        </Button>
        <Modal
          open={open}
          onOpenChange={setOpen}
          title="Delete Account"
          size="sm"
          showCloseButton={false}
          closeOnOverlayClick={false}
          closeOnEscape={false}
        >
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <div className="flex-shrink-0 w-10 h-10 bg-error/10 rounded-full flex items-center justify-center">
                <svg
                  className="w-5 h-5 text-error"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <title>Warning icon</title>
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4.1c-.77-.833-2.694-.833-3.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z"
                  />
                </svg>
              </div>
              <div>
                <h4 className="font-medium text-base-content">Are you absolutely sure?</h4>
                <p className="text-sm text-base-content/70 mt-1">
                  This action cannot be undone. This will permanently delete your account and remove
                  all associated data.
                </p>
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="bordered" onPress={() => setOpen(false)}>
                Cancel
              </Button>
              <Button variant="solid" onPress={() => setOpen(false)}>
                Delete Account
              </Button>
            </div>
          </div>
        </Modal>
      </div>
    );
  },
  parameters: {
    docs: {
      description: {
        story: "Example of using a modal for destructive confirmations",
      },
    },
  },
};
