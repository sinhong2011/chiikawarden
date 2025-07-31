import type { Meta, StoryObj } from "@storybook/react";
import { NavigationTab, type NavigationTabProps } from "./navigation-tab";

const meta: Meta<typeof NavigationTab> = {
  title: "Internal/Layout/NavigationTab",
  component: NavigationTab,
  parameters: {
    layout: "centered",
    docs: {
      description: {
        component:
          "A minimalist navigation tab component with icon-only buttons and hover tooltips. Features route-based active tab highlighting, programmatic navigation, and accessibility support through screen reader labels and descriptive tooltips.",
      },
    },
  },
  argTypes: {
    className: {
      control: "text",
      description: "Additional CSS classes to apply to the component",
    },
  },
};

export default meta;
type Story = StoryObj<typeof meta>;

// Default story showing the navigation tabs
export const Default: Story = {
  args: {},
  render: (args: NavigationTabProps) => (
    <div className="w-16 h-64 border border-divider rounded-lg bg-background">
      <NavigationTab {...args} />
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story:
          "Default navigation tab component with icon-only buttons. Hover over each tab to see the tooltip with the tab label and description. The tooltips appear on the right side with a 300ms delay.",
      },
    },
  },
};

// Story showing the component in a sidebar layout
export const InSidebar: Story = {
  args: {},
  render: (args: NavigationTabProps) => (
    <div className="flex h-96 border border-divider rounded-lg overflow-hidden">
      <aside className="w-16 border-r border-divider bg-background">
        <div className="p-2">
          <NavigationTab {...args} />
        </div>
      </aside>
      <main className="flex-1 p-6 bg-content1">
        <div className="text-center text-default-500">
          <h3 className="text-lg font-medium mb-2">Main Content Area</h3>
          <p className="text-sm">
            Hover over the navigation tabs on the left to see the tooltips in action.
            The tabs show only icons for a clean, minimalist design.
          </p>
        </div>
      </main>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story:
          "Navigation tab component integrated into a typical sidebar layout. This demonstrates how the component works in a real application context with proper spacing and layout.",
      },
    },
  },
};

// Story showing different tooltip placements
export const TooltipPlacements: Story = {
  args: {},
  render: (args: NavigationTabProps) => (
    <div className="grid grid-cols-2 gap-8 p-8">
      <div>
        <h4 className="text-sm font-medium mb-4 text-center">Default (Right Placement)</h4>
        <div className="w-16 h-64 border border-divider rounded-lg bg-background">
          <NavigationTab {...args} />
        </div>
      </div>
      <div>
        <h4 className="text-sm font-medium mb-4 text-center">Tooltip Features</h4>
        <div className="space-y-3 text-sm text-default-600">
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-primary rounded-full" />
            <span>300ms hover delay</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-primary rounded-full" />
            <span>100ms close delay</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-primary rounded-full" />
            <span>Right-side placement</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-primary rounded-full" />
            <span>Label + description content</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-primary rounded-full" />
            <span>Screen reader accessible</span>
          </div>
        </div>
      </div>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story:
          "Demonstration of the tooltip functionality and features. The tooltips are positioned to the right of the tabs with appropriate delays and styling.",
      },
    },
  },
};

// Story showing accessibility features
export const Accessibility: Story = {
  args: {},
  render: (args: NavigationTabProps) => (
    <div className="space-y-6">
      <div className="w-16 h-64 border border-divider rounded-lg bg-background">
        <NavigationTab {...args} />
      </div>
      <div className="max-w-md">
        <h4 className="text-sm font-medium mb-3">Accessibility Features</h4>
        <ul className="space-y-2 text-sm text-default-600">
          <li>• Screen reader labels with tab name and description</li>
          <li>• Proper ARIA labels for navigation context</li>
          <li>• Keyboard navigation support through HeroUI Tabs</li>
          <li>• High contrast tooltips with proper z-index layering</li>
          <li>• Focus indicators for keyboard users</li>
        </ul>
      </div>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story:
          "The component maintains full accessibility while providing a minimalist design. Screen readers will announce both the tab label and description, and keyboard navigation works as expected.",
      },
    },
  },
};
