import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { useHeroForm } from "../use-hero-form";

// Test schema
const testSchema = z.object({
  email: z.string().email("Invalid email"),
  password: z.string().min(8, "Password must be at least 8 characters"),
  name: z.string().min(1, "Name is required"),
});

type TestFormData = z.infer<typeof testSchema>;

describe("useHeroForm", () => {
  it("should initialize with default values", () => {
    const { result } = renderHook(() =>
      useHeroForm<TestFormData>({
        schema: testSchema,
        defaultValues: {
          email: "",
          password: "",
          name: "",
        },
      })
    );

    expect(result.current.isSubmitting).toBe(false);
    expect(result.current.submitError).toBe(null);
    expect(result.current.validationErrors).toEqual({});
    expect(result.current.form).toBeDefined();
    expect(typeof result.current.handleSubmit).toBe("function");
    expect(typeof result.current.setValidationErrors).toBe("function");
    expect(typeof result.current.clearValidationErrors).toBe("function");
    expect(typeof result.current.reset).toBe("function");
  });

  it("should handle form submission successfully", async () => {
    const mockOnSubmit = vi.fn().mockResolvedValue(undefined);

    const { result } = renderHook(() =>
      useHeroForm<TestFormData>({
        schema: testSchema,
        defaultValues: {
          email: "test@example.com",
          password: "password123",
          name: "Test User",
        },
        onSubmit: mockOnSubmit,
      })
    );

    // Set form values
    act(() => {
      result.current.form.setValue("email", "test@example.com");
      result.current.form.setValue("password", "password123");
      result.current.form.setValue("name", "Test User");
    });

    // Submit form
    await act(async () => {
      await result.current.handleSubmit();
    });

    expect(mockOnSubmit).toHaveBeenCalledWith(
      {
        email: "test@example.com",
        password: "password123",
        name: "Test User",
      },
      expect.any(Object)
    );
  });

  it("should handle form submission errors", async () => {
    const mockError = new Error("Submission failed");
    const mockOnSubmit = vi.fn().mockRejectedValue(mockError);
    const mockOnError = vi.fn();

    const { result } = renderHook(() =>
      useHeroForm<TestFormData>({
        schema: testSchema,
        defaultValues: {
          email: "test@example.com",
          password: "password123",
          name: "Test User",
        },
        onSubmit: mockOnSubmit,
        onError: mockOnError,
      })
    );

    // Set form values
    act(() => {
      result.current.form.setValue("email", "test@example.com");
      result.current.form.setValue("password", "password123");
      result.current.form.setValue("name", "Test User");
    });

    // Submit form
    await act(async () => {
      await result.current.handleSubmit();
    });

    expect(result.current.submitError).toBe("Submission failed");
    expect(mockOnError).toHaveBeenCalledWith(mockError);
  });

  it("should manage validation errors", () => {
    const { result } = renderHook(() =>
      useHeroForm<TestFormData>({
        schema: testSchema,
      })
    );

    const testErrors = {
      email: "Email is required",
      password: ["Password too short", "Password must contain numbers"],
    };

    act(() => {
      result.current.setValidationErrors(testErrors);
    });

    expect(result.current.validationErrors).toEqual(testErrors);

    act(() => {
      result.current.clearValidationErrors();
    });

    expect(result.current.validationErrors).toEqual({});
  });

  it("should reset form and clear errors", () => {
    const { result } = renderHook(() =>
      useHeroForm<TestFormData>({
        schema: testSchema,
        defaultValues: {
          email: "test@example.com",
          password: "password123",
          name: "Test User",
        },
      })
    );

    // Set some errors
    act(() => {
      result.current.setValidationErrors({ email: "Some error" });
    });

    // Reset form
    act(() => {
      result.current.reset();
    });

    expect(result.current.validationErrors).toEqual({});
    expect(result.current.submitError).toBe(null);
  });

  it("should work without schema", () => {
    const { result } = renderHook(() =>
      useHeroForm({
        defaultValues: {
          email: "",
          password: "",
        },
      })
    );

    expect(result.current.form).toBeDefined();
    expect(result.current.isSubmitting).toBe(false);
  });

  it("should work without onSubmit", async () => {
    const { result } = renderHook(() =>
      useHeroForm<TestFormData>({
        schema: testSchema,
        defaultValues: {
          email: "test@example.com",
          password: "password123",
          name: "Test User",
        },
      })
    );

    // Should not throw when calling handleSubmit without onSubmit
    await act(async () => {
      await result.current.handleSubmit();
    });

    expect(result.current.isSubmitting).toBe(false);
  });
});
