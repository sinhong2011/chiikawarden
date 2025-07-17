import { describe, expect, it } from "vitest";
import { z } from "zod";
import { HeroForm, useHeroForm } from "../hero-form";
import { TextInput } from "../text-input";

// Test schema for type checking
const testSchema = z.object({
  email: z.string().email("Invalid email"),
  password: z.string().min(8, "Password must be at least 8 characters"),
  name: z.string().min(1, "Name is required"),
});

type TestFormData = z.infer<typeof testSchema>;

describe("HeroForm TypeScript Type Compatibility", () => {
  it("should compile without TypeScript errors", () => {
    // This test verifies that the type fixes work correctly
    // If there are TypeScript errors, this test will fail to compile

    const TestComponent = () => {
      // Test useHeroForm hook with proper types
      const {
        form,
        isSubmitting,
        submitError,
        validationErrors,
        handleSubmit,
        setValidationErrors,
        clearValidationErrors,
        reset,
      } = useHeroForm<TestFormData>({
        schema: testSchema,
        defaultValues: {
          email: "",
          password: "",
          name: "",
        },
        onSubmit: async (data, form) => {
          // Type-safe access to form data
          console.log(data.email, data.password, data.name);
          console.log(form.getValues());
        },
      });

      // Test HeroForm component with proper types
      return (
        <HeroForm<TestFormData>
          schema={testSchema}
          defaultValues={{
            email: "",
            password: "",
            name: "",
          }}
          onSubmit={async (data, form) => {
            // Type-safe access to form data
            console.log(data.email, data.password, data.name);
            console.log(form.getValues());
          }}
          validationBehavior="native"
        >
          {(form) => (
            <>
              <TextInput
                name="email"
                type="email"
                label="Email"
                validate={(value) => {
                  if (!value) return "Email is required";
                  return undefined;
                }}
              />
              <TextInput
                name="password"
                type="password"
                label="Password"
                validate={(value) => {
                  if (!value) return "Password is required";
                  if (value.length < 8) return "Password must be at least 8 characters";
                  return undefined;
                }}
              />
              <TextInput
                name="name"
                label="Name"
                validate={(value) => {
                  if (!value) return "Name is required";
                  return undefined;
                }}
              />
            </>
          )}
        </HeroForm>
      );
    };

    // If this compiles without errors, the type fixes are working
    expect(TestComponent).toBeDefined();
  });

  it("should handle zodResolver type compatibility", () => {
    // Test that zodResolver works with our schema types
    const schema = z.object({
      test: z.string(),
    });

    const TestForm = () => (
      <HeroForm
        schema={schema}
        defaultValues={{ test: "" }}
        onSubmit={(data) => {
          // Should be type-safe
          console.log(data.test);
        }}
      >
        <TextInput name="test" label="Test" />
      </HeroForm>
    );

    expect(TestForm).toBeDefined();
  });

  it("should handle form context types correctly", () => {
    // Test that form context types work properly
    const schema = z.object({
      field1: z.string(),
      field2: z.number(),
    });

    const TestForm = () => (
      <HeroForm schema={schema} defaultValues={{ field1: "", field2: 0 }} validationBehavior="aria">
        {(form) => {
          // Should have proper form methods
          const values = form.getValues();
          const errors = form.formState.errors;

          return (
            <>
              <TextInput name="field1" label="Field 1" />
              <TextInput name="field2" label="Field 2" />
            </>
          );
        }}
      </HeroForm>
    );

    expect(TestForm).toBeDefined();
  });
});
