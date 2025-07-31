import { Button } from "@heroui/button";
import type { Meta, StoryObj } from "@storybook/react";
import { AlertTriangle, Info, Trash2 } from "lucide-react";
import React from "react";
import { ConfirmPopover, Popover, type PopoverProps } from "./popover";

const meta: Meta<typeof Popover> = {
  title: "UI/Overlay/Popover",
  component: Popover,
  parameters: {
    layout: "centered",
    docs: {
      description: {
        component:
          "A flexible popover component built on HeroUI Popover. Features multiple placements, customizable content, and accessibility support. Can be used for tooltips, confirmations, and contextual information.",
      },
    },
  },
  argTypes: {
    placement: {
      control: "select",
      options: [
        "top",
        "bottom",
        "left",
        "right",
        "top-start",
        "top-end",
        "bottom-start",
        "bottom-end",
        "left-start",
        "left-end",
        "right-start",
        "right-end",
      ],
    },
    backdrop: {
      control: "select",
      options: ["transparent", "opaque", "blur"],
    },
  },
};

export default meta;
type Story = StoryObj<typeof meta>;

// Wrapper component for stories
function PopoverWrapper(args: Partial<PopoverProps>) {
  const [open, setOpen] = React.useState(false);

  return (
    <div className="p-8">
      <Popover
        {...args}
        open={open}
        onOpenChange={setOpen}
        trigger={<Button onPress={() => setOpen(true)}>Open Popover</Button>}
      >
        <div className="p-4">
          <h4 className="font-medium mb-2">Popover Content</h4>
          <p className="text-sm text-base-content/70 mb-4">
            This is the content inside the popover. It can contain any React elements.
          </p>
          <Button size="sm" onPress={() => setOpen(false)}>
            Close
          </Button>
        </div>
      </Popover>
    </div>
  );
}

// Default story
export const Default: Story = {
  render: (args) => <PopoverWrapper {...args} />,
  args: {
    placement: "bottom",
    showArrow: true,
    backdrop: "transparent",
  },
};

// Placements
export const Placements: Story = {
  render: () => (
    <div className="grid grid-cols-3 gap-8 p-8">
      {[
        "top",
        "top-start",
        "top-end",
        "bottom",
        "bottom-start",
        "bottom-end",
        "left",
        "left-start",
        "left-end",
        "right",
        "right-start",
        "right-end",
      ].map((placement) => {
        const [open, setOpen] = React.useState(false);
        return (
          <Popover
            key={placement}
            open={open}
            onOpenChange={setOpen}
            placement={placement as PopoverProps["placement"]}
            trigger={
              <Button size="sm" onPress={() => setOpen(true)}>
                {placement}
              </Button>
            }
          >
            <div className="p-3">
              <p className="text-sm">Placement: {placement}</p>
            </div>
          </Popover>
        );
      })}
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: "Different placement options for the popover.",
      },
    },
  },
};

// Confirm Popover Stories
export const ConfirmDestructive: Story = {
  render: () => {
    const [open, setOpen] = React.useState(false);

    return (
      <div className="p-8">
        <ConfirmPopover
          open={open}
          onOpenChange={setOpen}
          trigger={
            <Button
              color="danger"
              variant="light"
              startContent={<Trash2 size={16} />}
              onPress={() => setOpen(true)}
            >
              Delete Item
            </Button>
          }
          title="Delete Item"
          message="Are you sure you want to delete this item? This action cannot be undone."
          confirmText="Delete"
          cancelText="Cancel"
          variant="destructive"
          icon={<Trash2 className="w-4 h-4" />}
          onConfirm={() => {
            console.log("Item deleted");
            setOpen(false);
          }}
          onCancel={() => setOpen(false)}
        />
      </div>
    );
  },
  parameters: {
    docs: {
      description: {
        story: "Destructive confirmation popover for delete actions.",
      },
    },
  },
};

export const ConfirmPrimary: Story = {
  render: () => {
    const [open, setOpen] = React.useState(false);

    return (
      <div className="p-8">
        <ConfirmPopover
          open={open}
          onOpenChange={setOpen}
          trigger={
            <Button color="primary" startContent={<Info size={16} />} onPress={() => setOpen(true)}>
              Save Changes
            </Button>
          }
          title="Save Changes"
          message="Do you want to save your changes before continuing?"
          confirmText="Save"
          cancelText="Discard"
          variant="primary"
          icon={<Info className="w-4 h-4" />}
          onConfirm={() => {
            console.log("Changes saved");
            setOpen(false);
          }}
          onCancel={() => setOpen(false)}
        />
      </div>
    );
  },
  parameters: {
    docs: {
      description: {
        story: "Primary confirmation popover for save actions.",
      },
    },
  },
};

export const ConfirmWithLoading: Story = {
  render: () => {
    const [open, setOpen] = React.useState(false);
    const [isLoading, setIsLoading] = React.useState(false);

    return (
      <div className="p-8">
        <ConfirmPopover
          open={open}
          onOpenChange={setOpen}
          trigger={
            <Button
              color="warning"
              variant="light"
              startContent={<AlertTriangle size={16} />}
              onPress={() => setOpen(true)}
            >
              Process Data
            </Button>
          }
          title="Process Data"
          message="This will process all the data in the background. This may take a few minutes."
          confirmText="Process"
          cancelText="Cancel"
          variant="primary"
          icon={<AlertTriangle className="w-4 h-4" />}
          isLoading={isLoading}
          onConfirm={async () => {
            setIsLoading(true);
            // Simulate async operation
            await new Promise((resolve) => setTimeout(resolve, 2000));
            setIsLoading(false);
            setOpen(false);
            console.log("Data processed");
          }}
          onCancel={() => setOpen(false)}
        />
      </div>
    );
  },
  parameters: {
    docs: {
      description: {
        story: "Confirmation popover with loading state during async operations.",
      },
    },
  },
};
