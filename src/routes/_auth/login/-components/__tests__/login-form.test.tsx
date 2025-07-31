import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { PreloginResponse } from "@/services/auth.service";
import LoginForm from "../login-form";

// Mock the auth queries hook
const mockLoginMutation = {
  mutateAsync: vi.fn(),
  isPending: false,
  isError: false,
  error: null as Error | null,
};

vi.mock("@/hooks/queries/use-auth-queries", () => ({
  useAuthQueries: () => ({
    login: mockLoginMutation,
  }),
}));

// Mock the router
vi.mock("@tanstack/react-router", () => ({
  useNavigate: () => vi.fn(),
}));

// Mock Lingui
vi.mock("@lingui/react/macro", () => ({
  useLingui: () => ({
    t: (template: TemplateStringsArray) => template[0],
  }),
}));

// Mock logging
vi.mock("@/lib/logging", () => ({
  logInfo: vi.fn(),
  logError: vi.fn(),
  logDebug: vi.fn(),
}));

describe("LoginForm", () => {
  let queryClient: QueryClient;

  const mockProps = {
    email: "test@example.com",
    kdfSettings: {
      kdf: 0,
      kdfIterations: 600000,
      kdfMemory: null,
      kdfParallelism: null,
    } as PreloginResponse,
    rememberMe: false,
    onBack: vi.fn(),
    onSuccess: vi.fn(),
  };

  beforeEach(() => {
    queryClient = new QueryClient({
      defaultOptions: {
        queries: { retry: false },
        mutations: { retry: false },
      },
    });
    vi.clearAllMocks();
    mockLoginMutation.isPending = false;
    mockLoginMutation.isError = false;
    mockLoginMutation.error = null;
  });

  const renderLoginForm = (props = mockProps) => {
    return render(
      <QueryClientProvider client={queryClient}>
        <LoginForm {...props} />
      </QueryClientProvider>
    );
  };

  it("renders login form with email display", () => {
    renderLoginForm();

    expect(screen.getByText("test@example.com")).toBeInTheDocument();
    expect(screen.getByLabelText(/master password/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /sign in/i })).toBeInTheDocument();
  });

  it("shows loading state when mutation is pending", () => {
    mockLoginMutation.isPending = true;
    renderLoginForm();

    const submitButton = screen.getByRole("button", { name: /signing in/i });
    expect(submitButton).toBeDisabled();
    expect(screen.getByText(/signing in/i)).toBeInTheDocument();
  });

  it("displays error message when mutation fails", () => {
    mockLoginMutation.isError = true;
    mockLoginMutation.error = new Error(
      "Login failed. Please check your credentials and try again."
    );
    renderLoginForm();

    expect(
      screen.getByText(/login failed\. please check your credentials and try again\./i)
    ).toBeInTheDocument();
  });

  it("displays fallback error message when mutation fails with non-Error object", () => {
    mockLoginMutation.isError = true;
    mockLoginMutation.error = null; // This will trigger the fallback
    renderLoginForm();

    expect(
      screen.getByText(/login failed\. please check your credentials and try again\./i)
    ).toBeInTheDocument();
  });

  it("calls mutation with correct credentials on form submit", async () => {
    mockLoginMutation.mutateAsync.mockResolvedValue(true);
    renderLoginForm();

    const passwordInput = screen.getByLabelText(/master password/i);
    const submitButton = screen.getByRole("button", { name: /sign in/i });

    fireEvent.change(passwordInput, { target: { value: "testpassword123" } });
    fireEvent.click(submitButton);

    await waitFor(() => {
      expect(mockLoginMutation.mutateAsync).toHaveBeenCalledWith({
        email: "test@example.com",
        password: "testpassword123",
        rememberMe: false,
      });
    });
  });

  it("calls onSuccess callback when provided", async () => {
    const onSuccess = vi.fn();
    mockLoginMutation.mutateAsync.mockResolvedValue(true);
    renderLoginForm({ ...mockProps, onSuccess });

    const passwordInput = screen.getByLabelText(/master password/i);
    const submitButton = screen.getByRole("button", { name: /sign in/i });

    fireEvent.change(passwordInput, { target: { value: "testpassword123" } });
    fireEvent.click(submitButton);

    await waitFor(() => {
      expect(onSuccess).toHaveBeenCalled();
    });
  });

  it("validates required password field", async () => {
    renderLoginForm();

    const submitButton = screen.getByRole("button", { name: /sign in/i });
    fireEvent.click(submitButton);

    await waitFor(() => {
      expect(screen.getByText(/validation.password_required/)).toBeInTheDocument();
    });

    expect(mockLoginMutation.mutateAsync).not.toHaveBeenCalled();
  });

  it("handles mutation errors gracefully", async () => {
    const consoleErrorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    mockLoginMutation.mutateAsync.mockRejectedValue(new Error("Network error"));
    renderLoginForm();

    const passwordInput = screen.getByLabelText(/master password/i);
    const submitButton = screen.getByRole("button", { name: /sign in/i });

    fireEvent.change(passwordInput, { target: { value: "testpassword123" } });
    fireEvent.click(submitButton);

    await waitFor(() => {
      expect(consoleErrorSpy).toHaveBeenCalledWith("Login failed:", expect.any(Error));
    });

    consoleErrorSpy.mockRestore();
  });
});
