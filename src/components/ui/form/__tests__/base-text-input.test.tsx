import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { BaseTextInput } from "../base-text-input";

describe("BaseTextInput", () => {
  it("renders with basic props", () => {
    render(
      <BaseTextInput
        name="test"
        label="Test Input"
        placeholder="Enter text"
      />
    );

    expect(screen.getByLabelText("Test Input")).toBeInTheDocument();
    expect(screen.getByPlaceholderText("Enter text")).toBeInTheDocument();
  });

  it("shows error message when error prop is provided", () => {
    render(
      <BaseTextInput
        name="test"
        label="Test Input"
        error="This field is required"
      />
    );

    expect(screen.getByText("This field is required")).toBeInTheDocument();
  });

  it("shows required indicator when required prop is true", () => {
    render(
      <BaseTextInput
        name="test"
        label="Test Input"
        required
      />
    );

    // The required indicator is added via CSS content, so we check for the class
    const label = screen.getByText("Test Input");
    expect(label).toHaveClass("after:content-['*']");
  });

  it("handles input changes", async () => {
    const user = userEvent.setup();
    const handleChange = vi.fn();

    render(
      <BaseTextInput
        name="test"
        label="Test Input"
        onChange={handleChange}
      />
    );

    const input = screen.getByLabelText("Test Input");
    await user.type(input, "hello");

    expect(handleChange).toHaveBeenCalled();
  });

  it("supports different input types", () => {
    render(
      <BaseTextInput
        name="email"
        type="email"
        label="Email Input"
      />
    );

    const input = screen.getByLabelText("Email Input");
    expect(input).toHaveAttribute("type", "email");
  });

  it("shows start content when provided", () => {
    render(
      <BaseTextInput
        name="test"
        label="Test Input"
        startContent={<span data-testid="start-icon">📧</span>}
      />
    );

    expect(screen.getByTestId("start-icon")).toBeInTheDocument();
  });

  it("shows end content when provided", () => {
    render(
      <BaseTextInput
        name="test"
        label="Test Input"
        endContent={<span data-testid="end-icon">🔍</span>}
      />
    );

    expect(screen.getByTestId("end-icon")).toBeInTheDocument();
  });

  it("handles disabled state", () => {
    render(
      <BaseTextInput
        name="test"
        label="Test Input"
        disabled
      />
    );

    const input = screen.getByLabelText("Test Input");
    expect(input).toBeDisabled();
  });

  it("handles readonly state", () => {
    render(
      <BaseTextInput
        name="test"
        label="Test Input"
        readOnly
      />
    );

    const input = screen.getByLabelText("Test Input");
    expect(input).toHaveAttribute("readonly");
  });

  it("calls validation function on blur", async () => {
    const user = userEvent.setup();
    const validate = vi.fn().mockReturnValue("Validation error");

    render(
      <BaseTextInput
        name="test"
        label="Test Input"
        validate={validate}
      />
    );

    const input = screen.getByLabelText("Test Input");
    await user.type(input, "test");
    await user.tab(); // Trigger blur

    expect(validate).toHaveBeenCalledWith("test");
  });
});
