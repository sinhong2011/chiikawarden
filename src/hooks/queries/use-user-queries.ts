import { useQuery, useQueryClient } from "@tanstack/react-query";
import { queryKeys } from "@/lib/query-key";
import { commands } from "@/lib/tauri-commands";

/**
 * TanStack Query hooks for user management
 * Provides queries for fetching user data from the database
 */
export const useUserQueries = () => {
  const queryClient = useQueryClient();

  // Query for all users from database (for account discovery/selection)
  const allUsersQuery = useQuery({
    queryKey: queryKeys.users.all(),
    queryFn: async () => {
      const result = await commands.getAllUsers();
      if (result.status === "error") {
        throw new Error(`Failed to fetch users: ${result.error}`);
      }
      return result.data;
    },
    staleTime: 10 * 60 * 1000, // 10 minutes - user list doesn't change frequently
    gcTime: 30 * 60 * 1000, // 30 minutes cache
    refetchOnMount: false, // Don't refetch on mount since user list is stable
    refetchOnWindowFocus: false, // Don't refetch on window focus
    retry: 2,
  });

  return {
    // Database queries
    allUsers: allUsersQuery, // All users from database (User[] from tauri-commands)

    // Helper functions
    invalidateAllUsers: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.users.all() });
    },
  };
};
