import {
  Button,
  Dropdown,
  DropdownItem,
  DropdownMenu,
  DropdownSection,
  DropdownTrigger,
} from "@heroui/react";
import { useNavigate } from "@tanstack/react-router";
import { ChevronsUpDownIcon, LogOut, Settings, User, Users } from "lucide-react";
import { useRef } from "react";
import { useAuthQueries } from "@/hooks/queries/use-auth-queries";
import { useAuth } from "@/hooks/use-auth";
import { cn } from "@/lib/utils";

export interface AccountDropdownProps {
  className?: string;
}

/**
 * Account Dropdown Component
 *
 * Provides account management functionality in a dropdown menu:
 * - User information display
 * - Account switching (when multiple accounts are supported)
 * - Account settings navigation
 * - Logout functionality
 *
 * Positioned at the bottom of the sidebar with proper z-index layering.
 * Uses HeroUI components with custom styling following the established patterns.
 *
 * @example
 * ```tsx
 * <AccountDropdown className="mt-auto" />
 * ```
 */
export function AccountDropdown({ className }: AccountDropdownProps) {
  const navigate = useNavigate();
  const auth = useAuth();
  const { logout } = useAuthQueries();

  // Debug logging in development (only when auth state changes)
  const authStateRef = useRef<string>("");
  if (process.env.NODE_ENV === "development") {
    const currentAuthState = `${auth.isAuthenticated}-${auth.authStatus}-${auth.email}`;
    if (currentAuthState !== authStateRef.current) {
      console.log("AccountDropdown - Auth state changed:", {
        isAuthenticated: auth.isAuthenticated,
        email: auth.email,
        authStatus: auth.authStatus,
        isUnlocked: auth.isUnlocked,
      });
      authStateRef.current = currentAuthState;
    }
  }

  // Handle logout action
  const handleLogout = async () => {
    try {
      await logout.mutateAsync();
      // Navigation will be handled by auth state change
    } catch (error) {
      console.error("Logout failed:", error);
    }
  };

  // Handle account settings navigation
  const handleAccountSettings = () => {
    navigate({ to: "/settings/account" });
  };

  // Handle account switching (placeholder for future implementation)
  const handleSwitchAccount = () => {
    // TODO: Implement account switching functionality
    console.log("Switch account functionality not yet implemented");
  };

  // Don't render if user is not authenticated
  if (!auth.isAuthenticated || !auth.email) {
    return null;
  }

  return (
    <div className={cn("w-full", className)}>
      <Dropdown
        placement="top-start"
        classNames={{
          base: "before:bg-default-200",
          content: "p-0 border-small border-divider bg-background",
        }}
        // Higher z-index than regular dropdowns to prevent layering issues
        style={{ zIndex: 1100 }}
      >
        <DropdownTrigger>
          <Button
            variant="light"
            className={cn(
              "w-full h-12 px-1 justify-start gap-3",
              "hover:bg-default-100 transition-colors",
              "data-[hover=true]:bg-default-100"
            )}
            startContent={
              <div className="flex items-center justify-center w-8 h-8 rounded-full bg-primary/10">
                <User className="w-4 h-4 text-primary" />
              </div>
            }
            endContent={<ChevronsUpDownIcon className="w-4 h-4 text-default-400" />}
          >
            <div className="flex flex-col items-start min-w-0 flex-1">
              <span className="text-sm font-medium text-foreground truncate">Account</span>
              <span className="text-xs text-muted-foreground truncate">{auth.email}</span>
            </div>
          </Button>
        </DropdownTrigger>

        <DropdownMenu
          aria-label="Account actions"
          className="w-60"
          itemClasses={{
            base: "gap-2",
          }}
        >
          {/* User Information Section */}
          <DropdownSection title="Account" className="mb-0">
            <DropdownItem
              key="user-info"
              className="h-14 gap-2 opacity-100"
              textValue={auth.email}
              isReadOnly
            >
              <div className="flex items-center gap-3">
                <div className="flex items-center justify-center w-10 h-10 rounded-full bg-primary/10">
                  <User className="w-5 h-5 text-primary" />
                </div>
                <div className="flex flex-col">
                  <span className="text-sm font-medium">{auth.email}</span>
                  <span className="text-xs text-muted-foreground">
                    {auth.isUnlocked ? "Unlocked" : "Locked"}
                  </span>
                </div>
              </div>
            </DropdownItem>
          </DropdownSection>

          {/* Actions Section */}
          <DropdownSection title="Actions" showDivider>
            <DropdownItem
              key="switch-account"
              className="text-default-500"
              startContent={<Users className="w-4 h-4" />}
              onPress={handleSwitchAccount}
            >
              Switch Account
            </DropdownItem>
            <DropdownItem
              key="account-settings"
              className="text-default-500"
              startContent={<Settings className="w-4 h-4" />}
              onPress={handleAccountSettings}
            >
              Account Settings
            </DropdownItem>
          </DropdownSection>

          {/* Logout Section */}
          <DropdownSection showDivider>
            <DropdownItem
              key="logout"
              className="text-danger"
              color="danger"
              startContent={<LogOut className="w-4 h-4" />}
              onPress={handleLogout}
              isDisabled={logout.isPending}
            >
              {logout.isPending ? "Logging out..." : "Logout"}
            </DropdownItem>
          </DropdownSection>
        </DropdownMenu>
      </Dropdown>
    </div>
  );
}
