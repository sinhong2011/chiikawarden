import type { Meta, StoryObj } from "@storybook/react";
import { useState } from "react";
import { Controller, useForm } from "react-hook-form";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { PasswordInput } from "./password-input";

const meta: Meta<typeof PasswordInput> = {
  title: "UI/Form/PasswordInput",
  component: PasswordInput,
  parameters: {
    layout: "centered",
    docs: {
      description: {
        component: `
A specialized input component for password fields with built-in show/hide toggle functionality.

## Features
- Built-in show/hide password toggle functionality
- Consistent styling with other form components  
- Integration with react-hook-form and zod validation
- TypeScript type safety
- Accessibility support with proper ARIA labels
- Lock icon as default start content

## Usage
Use this component for any password input fields in forms. It automatically includes the show/hide toggle button and proper password field attributes.
        `,
      },
    },
  },
  argTypes: {
    name: {
      control: "text",
      description: "The name attribute for the input field",
    },
    label: {
      control: "text",
      description: "Label text for the input",
    },
    placeholder: {
      control: "text", 
      description: "Placeholder text for the input",
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
      description: "Whether the field is disabled",
    },
    readOnly: {
      control: "boolean",
      description: "Whether the field is read-only",
    },
    showToggle: {
      control: "boolean",
      description: "Whether to show the show/hide toggle button",
    },
    defaultVisible: {
      control: "boolean",
      description: "Whether password is visible by default",
    },
    size: {
      control: "select",
      options: ["sm", "md", "lg"],
      description: "Size of the input",
    },
    variant: {
      control: "select",
      options: ["flat", "bordered", "faded", "underlined"],
      description: "Visual variant of the input",
    },
  },
  tags: ["autodocs"],
};

export default meta;
type Story = StoryObj<typeof meta>;

// Wrapper component for controlled stories
const PasswordInputWrapper = (args: React.ComponentProps<typeof PasswordInput>) => {
  const [value, setValue] = useState("");
  
  return (
    <div className="w-80">
      <PasswordInput
        {...args}
        value={value}
        onChange={(e) => setValue(e.target.value)}
      />
    </div>
  );
};

// Default story
export const Default: Story = {
  render: (args) => <PasswordInputWrapper {...args} />,
  args: {
    name: "password",
    label: "Password",
    placeholder: "Enter your password",
    error: "",
    size: "md",
    variant: "flat",
  },
};

// Variants
export const Bordered: Story = {
  render: (args) => <PasswordInputWrapper {...args} />,
  args: {
    name: "password",
    label: "Password",
    placeholder: "Enter your password",
    variant: "bordered",
    size: "lg",
  },
};

export const WithError: Story = {
  render: (args) => <PasswordInputWrapper {...args} />,
  args: {
    name: "password",
    label: "Password",
    placeholder: "Enter your password",
    error: "Password must be at least 8 characters long",
    variant: "bordered",
  },
};

export const Required: Story = {
  render: (args) => <PasswordInputWrapper {...args} />,
  args: {
    name: "password",
    label: "Password",
    placeholder: "Enter your password",
    required: true,
    variant: "bordered",
  },
};

export const Disabled: Story = {
  render: (args) => <PasswordInputWrapper {...args} />,
  args: {
    name: "password",
    label: "Password",
    placeholder: "Enter your password",
    disabled: true,
    variant: "bordered",
  },
};

export const ReadOnly: Story = {
  render: (args) => <PasswordInputWrapper {...args} />,
  args: {
    name: "password",
    label: "Password",
    value: "readonly-password",
    readOnly: true,
    variant: "bordered",
  },
};

export const NoToggle: Story = {
  render: (args) => <PasswordInputWrapper {...args} />,
  args: {
    name: "password",
    label: "Password",
    placeholder: "Enter your password",
    showToggle: false,
    variant: "bordered",
  },
};

export const DefaultVisible: Story = {
  render: (args) => <PasswordInputWrapper {...args} />,
  args: {
    name: "password",
    label: "Password",
    placeholder: "Enter your password",
    defaultVisible: true,
    variant: "bordered",
  },
};

// Sizes
export const Small: Story = {
  render: (args) => <PasswordInputWrapper {...args} />,
  args: {
    name: "password",
    label: "Password",
    placeholder: "Enter your password",
    size: "sm",
    variant: "bordered",
  },
};

export const Large: Story = {
  render: (args) => <PasswordInputWrapper {...args} />,
  args: {
    name: "password",
    label: "Master Password",
    placeholder: "Enter your master password",
    size: "lg",
    variant: "bordered",
  },
};

// Form integration example
const FormSchema = z.object({
  password: z.string().min(8, "Password must be at least 8 characters long"),
  confirmPassword: z.string(),
}).refine((data) => data.password === data.confirmPassword, {
  message: "Passwords don't match",
  path: ["confirmPassword"],
});

type FormData = z.infer<typeof FormSchema>;

export const WithReactHookForm: Story = {
  render: () => {
    const {
      control,
      handleSubmit,
      formState: { errors },
    } = useForm<FormData>({
      resolver: zodResolver(FormSchema),
      defaultValues: {
        password: "",
        confirmPassword: "",
      },
    });

    const onSubmit = (data: FormData) => {
      console.log("Form submitted:", data);
    };

    return (
      <form onSubmit={handleSubmit(onSubmit)} className="w-80 space-y-4">
        <Controller
          name="password"
          control={control}
          render={({ field, fieldState }) => (
            <PasswordInput
              {...field}
              label="Password"
              placeholder="Enter your password"
              error={fieldState.error?.message}
              required
              variant="bordered"
            />
          )}
        />
        
        <Controller
          name="confirmPassword"
          control={control}
          render={({ field, fieldState }) => (
            <PasswordInput
              {...field}
              label="Confirm Password"
              placeholder="Confirm your password"
              error={fieldState.error?.message}
              required
              variant="bordered"
            />
          )}
        />
        
        <button
          type="submit"
          className="w-full px-4 py-2 bg-primary text-primary-foreground rounded-md hover:bg-primary/90 transition-colors"
        >
          Submit
        </button>
      </form>
    );
  },
  parameters: {
    docs: {
      description: {
        story: "Example of PasswordInput used with react-hook-form and zod validation",
      },
    },
  },
};
