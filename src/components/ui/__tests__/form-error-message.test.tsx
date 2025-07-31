import { render, renderHook, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { FormErrorMessage, useFormErrorMessage } from "../form-error-message";

describe("FormErrorMessage", () => {
  it("renders nothing when no error is provided", () => {
    const { container } = render(<FormErrorMessage />);
    expect(container.firstChild).toBeNull();
  });

  it("renders nothing when error is null", () => {
    const { container } = render(<FormErrorMessage error={null} />);
    expect(container.firstChild).toBeNull();
  });

  it("renders nothing when error is undefined", () => {
    const { container } = render(<FormErrorMessage error={undefined} />);
    expect(container.firstChild).toBeNull();
  });

  it("renders nothing when error is empty string", () => {
    const { container } = render(<FormErrorMessage error="" />);
    expect(container.firstChild).toBeNull();
  });

  it("renders nothing when error array is empty", () => {
    const { container } = render(<FormErrorMessage error={[]} />);
    expect(container.firstChild).toBeNull();
  });

  it("renders nothing when error array contains only empty strings", () => {
    const { container } = render(<FormErrorMessage error={["", "", ""]} />);
    expect(container.firstChild).toBeNull();
  });

  it("renders single error message", () => {
    render(<FormErrorMessage error="This field is required" />);
    expect(screen.getByText("This field is required")).toBeInTheDocument();
  });

  it("renders multiple error messages as a list", () => {
    const errors = ["Email is required", "Email must be valid"];
    render(<FormErrorMessage error={errors} />);

    expect(screen.getByText("Email is required")).toBeInTheDocument();
    expect(screen.getByText("Email must be valid")).toBeInTheDocument();
    expect(screen.getByRole("list")).toBeInTheDocument();
  });

  it("filters out empty strings from error array", () => {
    const errors = ["Valid error", "", "Another valid error"];
    render(<FormErrorMessage error={errors} />);

    expect(screen.getByText("Valid error")).toBeInTheDocument();
    expect(screen.getByText("Another valid error")).toBeInTheDocument();
    expect(screen.getByRole("list")).toBeInTheDocument();

    // Should only have 2 list items (after filtering empty strings)
    const listItems = screen.getAllByRole("listitem");
    expect(listItems).toHaveLength(2);
  });

  it("has proper accessibility attributes", () => {
    render(<FormErrorMessage error="Test error" />);

    const errorContainer = screen.getByRole("alert");
    expect(errorContainer).toHaveAttribute("aria-live", "polite");
    expect(errorContainer).toHaveAttribute("aria-atomic", "true");
  });

  it("shows error icon by default", () => {
    render(<FormErrorMessage error="Test error" />);

    const icon = screen.getByRole("alert").querySelector("svg");
    expect(icon).toBeInTheDocument();
    expect(icon).toHaveAttribute("aria-hidden", "true");
  });

  it("hides error icon when showIcon is false", () => {
    render(<FormErrorMessage error="Test error" showIcon={false} />);

    const icon = screen.getByRole("alert").querySelector("svg");
    expect(icon).not.toBeInTheDocument();
  });

  it("uses custom icon when provided", () => {
    const CustomIcon = () => <span data-testid="custom-icon">!</span>;
    render(<FormErrorMessage error="Test error" icon={<CustomIcon />} />);

    expect(screen.getByTestId("custom-icon")).toBeInTheDocument();
  });

  it("applies custom className", () => {
    render(<FormErrorMessage error="Test error" className="custom-class" />);

    const errorContainer = screen.getByRole("alert");
    expect(errorContainer).toHaveClass("custom-class");
  });

  it("applies size classes correctly", () => {
    const { rerender } = render(<FormErrorMessage error="Test error" size="sm" />);
    let errorContainer = screen.getByRole("alert");
    expect(errorContainer).toHaveClass("gap-2");

    rerender(<FormErrorMessage error="Test error" size="md" />);
    errorContainer = screen.getByRole("alert");
    expect(errorContainer).toHaveClass("gap-2.5");

    rerender(<FormErrorMessage error="Test error" size="lg" />);
    errorContainer = screen.getByRole("alert");
    expect(errorContainer).toHaveClass("gap-3");
  });

  it("uses provided id", () => {
    render(<FormErrorMessage error="Test error" id="custom-error-id" />);

    const errorContainer = screen.getByRole("alert");
    expect(errorContainer).toHaveAttribute("id", "custom-error-id");
  });

  it("passes through container props", () => {
    render(
      <FormErrorMessage
        error="Test error"
        containerProps={
          { "data-testid": "error-container" } as React.HTMLAttributes<HTMLDivElement>
        }
      />
    );

    expect(screen.getByTestId("error-container")).toBeInTheDocument();
  });

  it("applies animation classes by default", () => {
    render(<FormErrorMessage error="Test error" />);

    const errorContainer = screen.getByRole("alert");
    expect(errorContainer).toHaveClass("animate-in", "slide-in-from-top-1", "duration-200");
  });

  it("does not apply animation classes when animate is false", () => {
    render(<FormErrorMessage error="Test error" animate={false} />);

    const errorContainer = screen.getByRole("alert");
    expect(errorContainer).not.toHaveClass("animate-in");
    expect(errorContainer).not.toHaveClass("slide-in-from-top-1");
    expect(errorContainer).not.toHaveClass("duration-200");
  });
});

describe("useFormErrorMessage", () => {
  it("returns hasError false when no error", () => {
    const { result } = renderHook(() => useFormErrorMessage());
    expect(result.current.hasError).toBe(false);
    expect(result.current.errorId).toBeUndefined();
    expect(result.current.errorProps).toEqual({});
  });

  it("returns hasError false when error is empty string", () => {
    const { result } = renderHook(() => useFormErrorMessage(""));
    expect(result.current.hasError).toBe(false);
  });

  it("returns hasError true when error exists", () => {
    const { result } = renderHook(() => useFormErrorMessage("Test error"));
    expect(result.current.hasError).toBe(true);
    expect(result.current.errorId).toBeDefined();
    expect(result.current.errorProps).toEqual({
      "aria-describedby": result.current.errorId,
      "aria-invalid": true,
    });
  });

  it("returns hasError true when error array has valid errors", () => {
    const { result } = renderHook(() => useFormErrorMessage(["Error 1", "Error 2"]));
    expect(result.current.hasError).toBe(true);
  });

  it("returns hasError false when error array is empty or contains only empty strings", () => {
    const { result } = renderHook(() => useFormErrorMessage(["", "", ""]));
    expect(result.current.hasError).toBe(false);
  });
});
