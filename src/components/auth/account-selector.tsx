import { useLingui } from "@lingui/react/macro";
import { useNavigate } from "@tanstack/react-router";
import { Check, Lock, Unlock, User, Users } from "lucide-react";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { Dropdown } from "@/components/ui/dropdown";
import { AnimatedSpinner } from "@/components/ui/icon/spinner";
import { useServerProviderQueries } from "@/hooks/queries/use-server-provider-queries";
import { userProviderService } from "@/services/user-provider.service";
import { useAuthStore } from "@/stores/auth.store";
import type { User as UserType, UserWithProvider } from "@/types/auth.types";

interface AccountSelectorProps {
  className?: string;
}

interface EnhancedAccountOption {
  user: UserWithProvider;
  isCurrentUser: boolean;
  isLocked: boolean;
  isLastLoggedIn: boolean;
  statusIcon: React.ReactNode;
  lastSignInText: string;
}

/**
 * Enhanced Account Selector Component
 *
 * A self-contained account selector that provides rich visual feedback
 * and automatic account management. Features include:
 *
 * - Automatic selection of last logged-in account as default
 * - Self-contained account switching without external callbacks
 * - Visual status indicators (lock icons, last sign-in info)
 * - Server provider identification for each account
 * - Loading states and smooth transition animations
 * - Progressive disclosure UI patterns
 * - Comprehensive performance optimizations
 *
 * @param className - Additional CSS classes
 */
export const AccountSelector = React.memo(function AccountSelector({
  className,
}: AccountSelectorProps) {
  const { t } = useLingui();
  const navigate = useNavigate();
  const authStore = useAuthStore();
  const { providerInfo, setCurrentProvider } = useServerProviderQueries();

  // Component state
  const [selectedAccountId, setSelectedAccountId] = useState<string | null>(null);
  const [switchingAccountId, setSwitchingAccountId] = useState<string | null>(null);
  const [isInitialized, setIsInitialized] = useState(false);
  const [usersWithProviders, setUsersWithProviders] = useState<UserWithProvider[]>([]);

  // Load users with provider information
  useEffect(() => {
    const loadUsersWithProviders = async () => {
      try {
        const users = await userProviderService.getAllUsersWithProviders();
        setUsersWithProviders(users);
      } catch (error) {
        console.error("Failed to load users with providers:", error);
      }
    };

    if (authStore.allUsers?.length > 0) {
      loadUsersWithProviders();
    }
  }, [authStore.allUsers]);

  // Initialize default selection from last logged-in user
  useEffect(() => {
    const initializeDefaultSelection = async () => {
      if (isInitialized || !usersWithProviders?.length) return;

      try {
        const lastLoggedInUserId = await authStore.getLastLoggedInUserId();
        if (lastLoggedInUserId) {
          const lastLoggedInUser = usersWithProviders.find(
            (user) => user.id === lastLoggedInUserId
          );
          if (lastLoggedInUser) {
            setSelectedAccountId(lastLoggedInUserId);
          } else {
            // Fallback to current user or first available user
            const currentUser = usersWithProviders.find((u) => u.id === authStore.user?.id);
            const defaultUser = currentUser || usersWithProviders[0];
            setSelectedAccountId(defaultUser.id);
          }
        } else {
          // No last logged-in user, default to current user or first available
          const currentUser = usersWithProviders.find((u) => u.id === authStore.user?.id);
          const defaultUser = currentUser || usersWithProviders[0];
          setSelectedAccountId(defaultUser.id);
        }
      } catch (error) {
        console.error("Failed to initialize default account selection:", error);
        // Fallback to first available user
        if (usersWithProviders?.length > 0) {
          const currentUser = usersWithProviders.find((u) => u.id === authStore.user?.id);
          const defaultUser = currentUser || usersWithProviders[0];
          setSelectedAccountId(defaultUser.id);
        }
      } finally {
        setIsInitialized(true);
      }
    };

    initializeDefaultSelection();
  }, [usersWithProviders, authStore.user, isInitialized, authStore.getLastLoggedInUserId]);

  // Transform users into enhanced account options
  const enhancedAccountOptions = useMemo(() => {
    if (!usersWithProviders || usersWithProviders.length === 0 || !isInitialized) {
      return [];
    }

    return usersWithProviders.map((user): EnhancedAccountOption => {
      const isCurrentUser = authStore.user?.id === user.id;
      const isLocked = !isCurrentUser || authStore.authStatus === "locked";
      const isLastLoggedIn = selectedAccountId === user.id;
      const isSwitching = switchingAccountId === user.id;

      // Determine status icon
      let statusIcon: React.ReactNode;
      if (isSwitching) {
        statusIcon = <AnimatedSpinner />;
      } else if (isCurrentUser && !isLocked) {
        statusIcon = <Unlock className="w-4 h-4 text-success" />;
      } else if (isCurrentUser && isLocked) {
        statusIcon = <Lock className="w-4 h-4 text-warning" />;
      } else {
        statusIcon = <Lock className="w-4 h-4 text-default-400" />;
      }

      // Determine last sign-in text
      let lastSignInText: string;
      if (isCurrentUser && !isLocked) {
        lastSignInText = t`Currently signed in` /* 当前已登录 */;
      } else if (isCurrentUser && isLocked) {
        lastSignInText = t`Locked - needs unlock` /* 已锁定 - 需要解锁 */;
      } else if (isLastLoggedIn) {
        lastSignInText = t`Last signed in` /* 上次登录 */;
      } else {
        lastSignInText = t`Requires sign in` /* 需要登录 */;
      }

      return {
        user,
        isCurrentUser,
        isLocked,
        isLastLoggedIn,
        statusIcon,
        lastSignInText,
      };
    });
  }, [
    usersWithProviders,
    authStore.user,
    authStore.authStatus,
    selectedAccountId,
    switchingAccountId,
    isInitialized,
    t,
  ]);

  // Transform enhanced options to dropdown format
  const dropdownOptions = useMemo(() => {
    return enhancedAccountOptions.map((option) => ({
      value: option.user.id,
      label: `${option.user.email} (${option.user.provider_label})`,
      disabled: switchingAccountId === option.user.id,
      endContent: (
        <div className="flex items-center gap-2">
          {option.isLastLoggedIn && <Check className="w-3 h-3 text-primary flex-shrink-0" />}
          {option.statusIcon}
        </div>
      ),
    }));
  }, [enhancedAccountOptions, switchingAccountId]);

  // Enhanced account switching logic with navigation and provider switching
  const handleAccountSwitch = useCallback(
    async (userId: string) => {
      console.log(`[AccountSelector] Starting account switch to user: ${userId}`);

      if (switchingAccountId) {
        console.log(
          `[AccountSelector] Account switch already in progress for: ${switchingAccountId}`
        );
        return; // Prevent multiple switches
      }

      if (userId === authStore.user?.id) {
        console.log(
          `[AccountSelector] User ${userId} is already the current user, skipping switch`
        );
        return; // Prevent switching to current user
      }

      const targetUser = usersWithProviders?.find((user) => user.id === userId);
      if (!targetUser) {
        console.error(`[AccountSelector] Target user not found for account switch: ${userId}`);
        return;
      }

      console.log(
        `[AccountSelector] Switching to user: ${targetUser.email} (${targetUser.provider_label})`
      );

      try {
        setSwitchingAccountId(userId);

        // Update selected account for UI feedback
        setSelectedAccountId(userId);
        console.log(`[AccountSelector] Updated selected account ID to: ${userId}`);

        // Set the selected account email for form prefilling
        authStore.setSelectedAccountEmail(targetUser.email);
        console.log(`[AccountSelector] Set selected account email: ${targetUser.email}`);

        // Update last logged-in user ID
        await authStore.setLastLoggedInUserId(userId);
        console.log(`[AccountSelector] Updated last logged-in user ID: ${userId}`);

        // Check if we need to switch server providers
        const currentProvider = providerInfo.data?.current_provider;
        if (currentProvider && currentProvider.id !== targetUser.server_provider_id) {
          console.log(
            `[AccountSelector] Switching server provider from ${currentProvider.id} to ${targetUser.server_provider_id}`
          );
          await setCurrentProvider.mutateAsync(targetUser.server_provider_id);
          console.log(`[AccountSelector] Server provider switch completed`);
        } else {
          console.log(`[AccountSelector] No server provider switch needed`);
        }

        // If switching to a different user, we need to logout current user
        // and prepare for login flow with the selected account
        if (authStore.user && authStore.user.id !== userId) {
          console.log(`[AccountSelector] Logging out current user: ${authStore.user.email}`);
          await authStore.logout();
          console.log(`[AccountSelector] Current user logged out successfully`);
        }

        // Prepare navigation parameters
        const navigationParams = {
          to: "/unlock" as const,
          search: {
            accountId: userId,
            email: targetUser.email,
            providerId: targetUser.server_provider_id,
          },
        };

        console.log(`[AccountSelector] Navigating to unlock page with params:`, navigationParams);

        // Navigate to unlock page with account context
        navigate(navigationParams);

        console.log(`[AccountSelector] Navigation to unlock page initiated successfully`);
      } catch (error) {
        console.error(`[AccountSelector] Failed to switch account:`, error);

        // Provide more specific error information
        if (error instanceof Error) {
          console.error(`[AccountSelector] Error details: ${error.message}`);
          console.error(`[AccountSelector] Error stack:`, error.stack);
        }

        // Revert selection on error
        if (authStore.user) {
          console.log(
            `[AccountSelector] Reverting selection to current user: ${authStore.user.id}`
          );
          setSelectedAccountId(authStore.user.id);
        } else {
          console.log(`[AccountSelector] No current user to revert to, clearing selection`);
          setSelectedAccountId(null);
        }
      } finally {
        setSwitchingAccountId(null);
        console.log(`[AccountSelector] Account switch process completed for user: ${userId}`);
      }
    },
    [
      switchingAccountId,
      authStore,
      usersWithProviders,
      providerInfo.data?.current_provider,
      setCurrentProvider,
      navigate,
    ]
  );

  // Don't render if no accounts or not initialized
  if (!usersWithProviders || usersWithProviders.length === 0 || !isInitialized) {
    return null;
  }

  // Show loading state during initialization
  if (!isInitialized) {
    return (
      <div className={className}>
        <div className="flex items-center gap-2 p-2 border border-default-200 rounded-lg">
          <AnimatedSpinner />
          <span className="text-sm text-muted-foreground">
            {t`Loading accounts...` /* 加载账户中... */}
          </span>
        </div>
      </div>
    );
  }

  return (
    <div className={className}>
      <Dropdown
        placeholder={t`Switch Account` /* 切换账户 */}
        options={dropdownOptions}
        value={selectedAccountId || ""}
        onChange={handleAccountSwitch}
        variant="bordered"
        size="sm"
        className="min-w-[280px]"
        startContent={<Users className="w-4 h-4 text-default-500" />}
        aria-label={t`Account selector` /* 账户选择器 */}
        disabled={!!switchingAccountId}
      />
    </div>
  );
});

/**
 * Account Selector with Icon Only
 *
 * A more compact version that shows only an icon button
 * for use in constrained header spaces. This version is also
 * self-contained and uses the same enhanced functionality as
 * the main AccountSelector.
 */
interface AccountSelectorCompactProps {
  className?: string;
  showLabel?: boolean;
}

export const AccountSelectorCompact = React.memo(function AccountSelectorCompact({
  className,
  showLabel = false,
}: AccountSelectorCompactProps) {
  const { t } = useLingui();
  const navigate = useNavigate();
  const authStore = useAuthStore();
  const { providerInfo, setCurrentProvider } = useServerProviderQueries();

  // Component state
  const [selectedAccountId, setSelectedAccountId] = useState<string | null>(null);
  const [switchingAccountId, setSwitchingAccountId] = useState<string | null>(null);
  const [isInitialized, setIsInitialized] = useState(false);
  const [usersWithProviders, setUsersWithProviders] = useState<UserWithProvider[]>([]);

  // Load users with provider information
  useEffect(() => {
    const loadUsersWithProviders = async () => {
      try {
        const users = await userProviderService.getAllUsersWithProviders();
        setUsersWithProviders(users);
      } catch (error) {
        console.error("Failed to load users with providers:", error);
      }
    };

    if (authStore.allUsers?.length > 0) {
      loadUsersWithProviders();
    }
  }, [authStore.allUsers]);

  // Initialize default selection from last logged-in user
  useEffect(() => {
    const initializeDefaultSelection = async () => {
      if (isInitialized || !usersWithProviders?.length) return;

      try {
        const lastLoggedInUserId = await authStore.getLastLoggedInUserId();
        if (lastLoggedInUserId) {
          const lastLoggedInUser = usersWithProviders.find(
            (user) => user.id === lastLoggedInUserId
          );
          if (lastLoggedInUser) {
            setSelectedAccountId(lastLoggedInUserId);
          } else {
            const currentUser = usersWithProviders.find((u) => u.id === authStore.user?.id);
            const defaultUser = currentUser || usersWithProviders[0];
            setSelectedAccountId(defaultUser.id);
          }
        } else {
          const currentUser = usersWithProviders.find((u) => u.id === authStore.user?.id);
          const defaultUser = currentUser || usersWithProviders[0];
          setSelectedAccountId(defaultUser.id);
        }
      } catch (error) {
        console.error("Failed to initialize compact account selection:", error);
        if (usersWithProviders?.length > 0) {
          const currentUser = usersWithProviders.find((u) => u.id === authStore.user?.id);
          const defaultUser = currentUser || usersWithProviders[0];
          setSelectedAccountId(defaultUser.id);
        }
      } finally {
        setIsInitialized(true);
      }
    };

    initializeDefaultSelection();
  }, [usersWithProviders, authStore.user, isInitialized, authStore.getLastLoggedInUserId]);

  // Transform users into compact dropdown options
  const accountOptions = useMemo(() => {
    if (!usersWithProviders || usersWithProviders.length === 0 || !isInitialized) {
      return [];
    }

    return usersWithProviders.map((user) => {
      const isCurrentUser = authStore.user?.id === user.id;
      const isLocked = !isCurrentUser || authStore.authStatus === "locked";
      const isSwitching = switchingAccountId === user.id;

      let statusIcon: React.ReactNode;
      if (isSwitching) {
        statusIcon = <AnimatedSpinner />;
      } else if (isCurrentUser && !isLocked) {
        statusIcon = <Unlock className="w-3 h-3 text-success" />;
      } else {
        statusIcon = <Lock className="w-3 h-3 text-default-400" />;
      }

      return {
        value: user.id,
        label: `${user.email} (${user.provider_label})`,
        disabled: isSwitching,
        endContent: statusIcon,
      };
    });
  }, [usersWithProviders, authStore.user, authStore.authStatus, switchingAccountId, isInitialized]);

  // Enhanced account switching logic with navigation and provider switching
  const handleAccountSwitch = useCallback(
    async (userId: string) => {
      if (switchingAccountId || userId === authStore.user?.id) {
        return;
      }

      const targetUser = usersWithProviders?.find((user) => user.id === userId);
      if (!targetUser) {
        console.error("Target user not found for compact account switch");
        return;
      }

      try {
        setSwitchingAccountId(userId);
        setSelectedAccountId(userId);
        authStore.setSelectedAccountEmail(targetUser.email);
        await authStore.setLastLoggedInUserId(userId);

        // Check if we need to switch server providers
        const currentProvider = providerInfo.data?.current_provider;
        if (currentProvider && currentProvider.id !== targetUser.server_provider_id) {
          console.log(
            `Switching server provider from ${currentProvider.id} to ${targetUser.server_provider_id}`
          );
          await setCurrentProvider.mutateAsync(targetUser.server_provider_id);
        }

        if (authStore.user && authStore.user.id !== userId) {
          await authStore.logout();
        }

        // Navigate to unlock page with account context
        navigate({
          to: "/unlock",
          search: {
            accountId: userId,
            email: targetUser.email,
            providerId: targetUser.server_provider_id,
          },
        });
      } catch (error) {
        console.error("Failed to switch account in compact selector:", error);
        if (authStore.user) {
          setSelectedAccountId(authStore.user.id);
        }
      } finally {
        setSwitchingAccountId(null);
      }
    },
    [
      switchingAccountId,
      authStore,
      usersWithProviders,
      providerInfo.data?.current_provider,
      setCurrentProvider,
      navigate,
    ]
  );

  // Don't render if no accounts
  if (!usersWithProviders || usersWithProviders.length === 0 || !isInitialized) {
    return null;
  }

  const accountCount = usersWithProviders.length;

  return (
    <div className={className}>
      <Dropdown
        placeholder={showLabel ? t`Accounts (${accountCount})` /* 账户 (${accountCount}) */ : ""}
        options={accountOptions}
        value={selectedAccountId || ""}
        onChange={handleAccountSwitch}
        variant="light"
        size="sm"
        className="min-w-fit"
        startContent={<User className="w-4 h-4 text-default-500" />}
        aria-label={t`${accountCount} accounts` /* ${accountCount} 个账户 */}
        showArrow={false}
        disabled={!!switchingAccountId}
      />
    </div>
  );
});
