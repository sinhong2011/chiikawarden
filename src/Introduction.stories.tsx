import type { Meta, StoryObj } from "@storybook/react";

const meta: Meta = {
  title: "Introduction/Welcome",
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component: "Welcome to the Chiikawarden Design System documentation",
      },
    },
  },
  tags: ["autodocs"],
};

export default meta;
type Story = StoryObj;

export const Welcome: Story = {
  render: () => (
    <div className="max-w-6xl  p-8 font-sans">
      <header className="mb-12 text-center">
        <h1 className="text-4xl font-bold text-base-content mb-4">Chiikawarden Design System</h1>
        <p className="text-xl text-base-content/70 max-w-3xl ">
          Welcome to the Chiikawarden component library! This Storybook contains all the reusable UI
          components, patterns, and guidelines for building consistent interfaces in the
          Chiikawarden password manager application.
        </p>
      </header>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold text-base-content mb-6">🎯 Overview</h2>
        <p className="text-base-content/80 mb-4">
          Chiikawarden is a modern password manager desktop application built with:
        </p>
        <ul className="space-y-2 text-base-content/80">
          <li>
            <strong>Frontend:</strong> React with TypeScript
          </li>
          <li>
            <strong>Backend:</strong> Tauri (Rust)
          </li>
          <li>
            <strong>Styling:</strong> TailwindCSS v4 with custom design tokens
          </li>
          <li>
            <strong>Components:</strong> HeroUI (NextUI) primitives
          </li>
          <li>
            <strong>Internationalization:</strong> Paraglide with support for English and Chinese
            variants
          </li>
        </ul>
      </section>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold text-base-content mb-6">🎨 Design Philosophy</h2>
        <p className="text-base-content/80 mb-6">
          Our design system is built around the principles of:
        </p>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="p-6 bg-base-200 rounded-lg">
            <h3 className="text-lg font-semibold text-base-content mb-3">Accessibility First</h3>
            <ul className="space-y-1 text-base-content/80">
              <li>• All components follow WCAG guidelines</li>
              <li>• Keyboard navigation support</li>
              <li>• Screen reader compatibility</li>
              <li>• High contrast support</li>
            </ul>
          </div>

          <div className="p-6 bg-base-200 rounded-lg">
            <h3 className="text-lg font-semibold text-base-content mb-3">Consistency</h3>
            <ul className="space-y-1 text-base-content/80">
              <li>• Unified color palette and typography</li>
              <li>• Consistent spacing and sizing</li>
              <li>• Predictable interaction patterns</li>
            </ul>
          </div>

          <div className="p-6 bg-base-200 rounded-lg">
            <h3 className="text-lg font-semibold text-base-content mb-3">Flexibility</h3>
            <ul className="space-y-1 text-base-content/80">
              <li>• Multiple component variants</li>
              <li>• Customizable sizes and states</li>
              <li>• Theme support (light/dark)</li>
            </ul>
          </div>

          <div className="p-6 bg-base-200 rounded-lg">
            <h3 className="text-lg font-semibold text-base-content mb-3">Performance</h3>
            <ul className="space-y-1 text-base-content/80">
              <li>• Optimized for desktop applications</li>
              <li>• Minimal bundle size impact</li>
              <li>• Efficient re-rendering</li>
            </ul>
          </div>
        </div>
      </section>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold text-base-content mb-6">🎨 Color Palette</h2>
        <p className="text-base-content/80 mb-6">
          Our design system uses a carefully crafted color palette inspired by the Dracula theme:
        </p>

        <div className="mb-8">
          <h3 className="text-lg font-semibold text-base-content mb-4">Primary Colors</h3>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <button
              type="button"
              className="p-4 rounded-lg text-center cursor-pointer transition-all duration-200 hover:scale-105 hover:shadow-lg border-none w-full"
              style={{ backgroundColor: "#8be9fd", color: "#171717" }}
              onClick={() => navigator.clipboard.writeText("#8be9fd")}
              title="Click to copy color code"
            >
              <div className="font-semibold">Primary</div>
              <div className="text-sm">#8be9fd</div>
              <div className="text-xs mt-1 opacity-70">Click to copy</div>
            </button>
            <button
              type="button"
              className="p-4 rounded-lg text-center cursor-pointer transition-all duration-200 hover:scale-105 hover:shadow-lg border-none w-full"
              style={{ backgroundColor: "#c4b5fd", color: "#171717" }}
              onClick={() => navigator.clipboard.writeText("#c4b5fd")}
              title="Click to copy color code"
            >
              <div className="font-semibold">Secondary</div>
              <div className="text-sm">#c4b5fd</div>
              <div className="text-xs mt-1 opacity-70">Click to copy</div>
            </button>
            <button
              type="button"
              className="p-4 rounded-lg text-center cursor-pointer transition-all duration-200 hover:scale-105 hover:shadow-lg border-none w-full"
              style={{ backgroundColor: "#50fa7b", color: "#171717" }}
              onClick={() => navigator.clipboard.writeText("#50fa7b")}
              title="Click to copy color code"
            >
              <div className="font-semibold">Accent</div>
              <div className="text-sm">#50fa7b</div>
              <div className="text-xs mt-1 opacity-70">Click to copy</div>
            </button>
          </div>
        </div>

        <div className="mb-8">
          <h3 className="text-lg font-semibold text-base-content mb-4">Status Colors</h3>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <button
              type="button"
              className="p-4 rounded-lg text-center cursor-pointer transition-all duration-200 hover:scale-105 hover:shadow-lg border-none w-full"
              style={{ backgroundColor: "#50fa7b", color: "#171717" }}
              onClick={() => navigator.clipboard.writeText("#50fa7b")}
              title="Click to copy color code"
            >
              <div className="font-semibold">Success</div>
              <div className="text-sm">#50fa7b</div>
              <div className="text-xs mt-1 opacity-70">Click to copy</div>
            </button>
            <button
              type="button"
              className="p-4 rounded-lg text-center cursor-pointer transition-all duration-200 hover:scale-105 hover:shadow-lg border-none w-full"
              style={{ backgroundColor: "#ffb86c", color: "#171717" }}
              onClick={() => navigator.clipboard.writeText("#ffb86c")}
              title="Click to copy color code"
            >
              <div className="font-semibold">Warning</div>
              <div className="text-sm">#ffb86c</div>
              <div className="text-xs mt-1 opacity-70">Click to copy</div>
            </button>
            <button
              type="button"
              className="p-4 rounded-lg text-center cursor-pointer transition-all duration-200 hover:scale-105 hover:shadow-lg border-none w-full"
              style={{ backgroundColor: "#ff5555", color: "#ffffff" }}
              onClick={() => navigator.clipboard.writeText("#ff5555")}
              title="Click to copy color code"
            >
              <div className="font-semibold">Error</div>
              <div className="text-sm">#ff5555</div>
              <div className="text-xs mt-1 opacity-70">Click to copy</div>
            </button>
            <button
              type="button"
              className="p-4 rounded-lg text-center cursor-pointer transition-all duration-200 hover:scale-105 hover:shadow-lg border-none w-full"
              style={{ backgroundColor: "#8be9fd", color: "#171717" }}
              onClick={() => navigator.clipboard.writeText("#8be9fd")}
              title="Click to copy color code"
            >
              <div className="font-semibold">Info</div>
              <div className="text-sm">#8be9fd</div>
              <div className="text-xs mt-1 opacity-70">Click to copy</div>
            </button>
          </div>
        </div>
      </section>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold text-base-content mb-6">📝 Typography</h2>
        <p className="text-base-content/80 mb-6">
          We use <strong>Poppins</strong> as our primary font family, providing excellent
          readability and a modern feel:
        </p>

        <div className="space-y-6">
          <div>
            <div className="text-4xl font-bold mb-2" style={{ fontFamily: "Poppins" }}>
              The quick brown fox jumps over the lazy dog
            </div>
            <div className="text-sm text-base-content/60">Poppins Bold, 36px</div>
          </div>

          <div>
            <div className="text-2xl font-semibold mb-2" style={{ fontFamily: "Poppins" }}>
              The quick brown fox jumps over the lazy dog
            </div>
            <div className="text-sm text-base-content/60">Poppins Semibold, 24px</div>
          </div>

          <div>
            <div className="text-base font-normal mb-2" style={{ fontFamily: "Poppins" }}>
              The quick brown fox jumps over the lazy dog
            </div>
            <div className="text-sm text-base-content/60">Poppins Regular, 16px</div>
          </div>
        </div>
      </section>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold text-base-content mb-6">🧩 Component Categories</h2>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="p-6 bg-base-200 rounded-lg">
            <h3 className="text-lg font-semibold text-base-content mb-3">Form Components</h3>
            <p className="text-sm text-base-content/70 mb-3">
              Interactive elements for user input and data collection:
            </p>
            <ul className="space-y-1 text-sm text-base-content/80">
              <li className="flex items-center justify-between">
                <span>• Button - Actions and navigation</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
              <li className="flex items-center justify-between">
                <span>• TextInput - Text and password input</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
              <li className="flex items-center justify-between">
                <span>• Checkbox - Boolean selections</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
              <li className="flex items-center justify-between">
                <span>• Select - Dropdown selections</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
              <li className="flex items-center justify-between">
                <span>• Radio Group - Single choice options</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
              <li className="flex items-center justify-between">
                <span>• Switch - Toggle switches</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
            </ul>
          </div>

          <div className="p-6 bg-base-200 rounded-lg">
            <h3 className="text-lg font-semibold text-base-content mb-3">Layout Components</h3>
            <p className="text-sm text-base-content/70 mb-3">
              Structural elements for organizing content:
            </p>
            <ul className="space-y-1 text-sm text-base-content/80">
              <li className="flex items-center justify-between">
                <span>• Modal - Overlay dialogs and confirmations</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
              <li className="flex items-center justify-between">
                <span>• Dropdown - Contextual menus and options</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
              <li className="flex items-center justify-between">
                <span>• Error Display - Error state presentation</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
            </ul>
          </div>

          <div className="p-6 bg-base-200 rounded-lg">
            <h3 className="text-lg font-semibold text-base-content mb-3">Feature Components</h3>
            <p className="text-sm text-base-content/70 mb-3">Application-specific components:</p>
            <ul className="space-y-1 text-sm text-base-content/80">
              <li className="flex items-center justify-between">
                <span>• Server Provider - Bitwarden server configuration</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
              <li className="flex items-center justify-between">
                <span>• Language Switcher - Internationalization controls</span>
                <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                  ✓ Migrated
                </span>
              </li>
              <li className="flex items-center justify-between">
                <span>• Error Boundary - Error handling and recovery</span>
                <span className="px-2 py-1 text-xs bg-yellow-100 text-yellow-800 rounded-full">
                  ⚠ In Progress
                </span>
              </li>
            </ul>
          </div>
        </div>
      </section>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold text-base-content mb-6">🌐 Internationalization</h2>
        <p className="text-base-content/80 mb-4">Chiikawarden supports multiple languages:</p>
        <ul className="space-y-2 text-base-content/80">
          <li>
            <strong>English</strong> (en) - Primary language
          </li>
          <li>
            <strong>简体中文</strong> (zh-CN) - Simplified Chinese
          </li>
          <li>
            <strong>繁體中文 (香港)</strong> (zh-HK) - Traditional Chinese (Hong Kong)
          </li>
          <li>
            <strong>繁體中文 (台灣)</strong> (zh-TW) - Traditional Chinese (Taiwan)
          </li>
        </ul>
        <p className="text-base-content/60 text-sm mt-4">
          Use the locale switcher in the Storybook toolbar to test components in different
          languages.
        </p>
      </section>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold text-base-content mb-6">🌙 Theme Support</h2>
        <p className="text-base-content/80 mb-4">
          All components support both light and dark themes:
        </p>
        <ul className="space-y-2 text-base-content/80">
          <li>
            <strong>Light Theme</strong> - Clean, bright interface for daytime use
          </li>
          <li>
            <strong>Dark Theme</strong> - Reduced eye strain for low-light environments
          </li>
        </ul>
        <p className="text-base-content/60 text-sm mt-4">
          Switch between themes using the theme toggle in the Storybook toolbar.
        </p>
      </section>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold text-base-content mb-6">🚀 Getting Started</h2>
        <ol className="space-y-3 text-base-content/80">
          <li>
            <strong>1. Browse Components</strong> - Explore the component library in the sidebar
          </li>
          <li>
            <strong>2. View Documentation</strong> - Each component includes usage examples and API
            documentation
          </li>
          <li>
            <strong>3. Test Interactions</strong> - Use the controls panel to test different
            component states
          </li>
          <li>
            <strong>4. Check Accessibility</strong> - Verify keyboard navigation and screen reader
            support
          </li>
        </ol>
      </section>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold text-base-content mb-6">📦 Component Usage</h2>
        <p className="text-base-content/80 mb-4">All components are designed to be:</p>
        <ul className="space-y-2 text-base-content/80 mb-6">
          <li>
            • <strong>Type-safe</strong> with full TypeScript support
          </li>
          <li>
            • <strong>Accessible</strong> by default
          </li>
          <li>
            • <strong>Themeable</strong> with consistent design tokens
          </li>
          <li>
            • <strong>Testable</strong> with proper data attributes
          </li>
        </ul>

        <div className="p-4 bg-base-300 rounded-lg">
          <div className="text-sm font-medium text-base-content mb-2">Example usage:</div>
          <pre className="text-sm text-base-content/80 overflow-x-auto">
            {`import { Button } from '@heroui/button';

function MyComponent() {
  return (
    <Button 
      color="primary" 
      size="md" 
      onPress={() => console.log('Button clicked!')}
    >
      Click me
    </Button>
  );
}`}
          </pre>
        </div>
      </section>

      <footer className="text-center py-8 border-t border-base-300">
        <p className="text-base-content/60">
          <strong>Need help?</strong> Check out the individual component documentation or reach out
          to the development team.
        </p>
      </footer>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story:
          "Complete overview of the Chiikawarden Design System, including color palette, typography, component categories, and usage guidelines.",
      },
    },
  },
};
