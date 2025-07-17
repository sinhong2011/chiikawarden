import type React from "react";
import { useCallback, useState } from "react";
import type { PopoverProps } from "@/components/ui/popover";

export interface UseModalOptions {
  defaultOpen?: boolean;
  onOpen?: () => void;
  onClose?: () => void;
  closeOnEscape?: boolean;
  closeOnOverlayClick?: boolean;
}

export interface UseModalReturn {
  isOpen: boolean;
  open: () => void;
  close: () => void;
  toggle: () => void;
  setOpen: (open: boolean) => void;
  modalProps: {
    open: boolean;
    onOpenChange: (open: boolean) => void;
  };
}

/**
 * Hook for managing modal state and providing convenient methods
 *
 * @param options - Configuration options for the modal
 * @returns Object with modal state and control methods
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const modal = useModal({
 *     onOpen: () => console.log('Modal opened'),
 *     onClose: () => console.log('Modal closed')
 *   });
 *
 *   return (
 *     <div>
 *       <Button onClick={modal.open}>Open Modal</Button>
 *       <Modal {...modal.modalProps} title="My Modal">
 *         <p>Modal content here</p>
 *       </Modal>
 *     </div>
 *   );
 * }
 * ```
 */
export function useModal(options: UseModalOptions = {}): UseModalReturn {
  const { defaultOpen = false, onOpen, onClose } = options;

  const [isOpen, setIsOpen] = useState(defaultOpen);

  const open = useCallback(() => {
    setIsOpen(true);
    onOpen?.();
  }, [onOpen]);

  const close = useCallback(() => {
    setIsOpen(false);
    onClose?.();
  }, [onClose]);

  const toggle = useCallback(() => {
    if (isOpen) {
      close();
    } else {
      open();
    }
  }, [isOpen, close, open]);

  const handleOpenChange = useCallback(
    (open: boolean) => {
      if (open) {
        onOpen?.();
      } else {
        onClose?.();
      }
      setIsOpen(open);
    },
    [onOpen, onClose]
  );

  return {
    isOpen,
    open,
    close,
    toggle,
    setOpen: setIsOpen,
    modalProps: {
      open: isOpen,
      onOpenChange: handleOpenChange,
    },
  };
}

/**
 * Hook for managing multiple modals with unique identifiers
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const modals = useMultiModal();
 *
 *   return (
 *     <div>
 *       <Button onClick={() => modals.open('confirm')}>Open Confirm</Button>
 *       <Button onClick={() => modals.open('settings')}>Open Settings</Button>
 *
 *       <Modal {...modals.getModalProps('confirm')} title="Confirm Action">
 *         <p>Are you sure?</p>
 *       </Modal>
 *
 *       <Modal {...modals.getModalProps('settings')} title="Settings">
 *         <p>Settings content</p>
 *       </Modal>
 *     </div>
 *   );
 * }
 * ```
 */
export function useMultiModal() {
  const [openModals, setOpenModals] = useState<Set<string>>(new Set());

  const isOpen = useCallback(
    (id: string): boolean => {
      return openModals.has(id);
    },
    [openModals]
  );

  const open = useCallback((id: string) => {
    setOpenModals((prev) => new Set([...prev, id]));
  }, []);

  const close = useCallback((id: string) => {
    setOpenModals((prev) => {
      const newSet = new Set(prev);
      newSet.delete(id);
      return newSet;
    });
  }, []);

  const toggle = useCallback(
    (id: string) => {
      if (isOpen(id)) {
        close(id);
      } else {
        open(id);
      }
    },
    [isOpen, close, open]
  );

  const closeAll = useCallback(() => {
    setOpenModals(new Set());
  }, []);

  const getModalProps = useCallback(
    (id: string) => ({
      open: isOpen(id),
      onOpenChange: (isModalOpen: boolean) => {
        if (isModalOpen) {
          open(id);
        } else {
          close(id);
        }
      },
    }),
    [isOpen, close, open]
  );

  return {
    isOpen,
    open,
    close,
    toggle,
    closeAll,
    getModalProps,
    openModals,
  };
}

/**
 * Hook for managing modal with async operations (loading states)
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const modal = useAsyncModal({
 *     onConfirm: async () => {
 *       await saveData();
 *       return true; // Close modal on success
 *     }
 *   });
 *
 *   return (
 *     <div>
 *       <Button onClick={modal.open}>Open Modal</Button>
 *       <Modal {...modal.modalProps} title="Save Data">
 *         <p>Do you want to save?</p>
 *         <div className="flex gap-2 mt-4">
 *           <Button onClick={modal.confirm} disabled={modal.isLoading}>
 *             {modal.isLoading ? 'Saving...' : 'Save'}
 *           </Button>
 *           <Button onClick={modal.close} variant="ghost">
 *             Cancel
 *           </Button>
 *         </div>
 *       </Modal>
 *     </div>
 *   );
 * }
 * ```
 */
export interface UseAsyncModalOptions extends UseModalOptions {
  onConfirm?: () => Promise<boolean | undefined>;
  onCancel?: () => void;
}

export function useAsyncModal(options: UseAsyncModalOptions = {}) {
  const { onConfirm, onCancel, ...modalOptions } = options;
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const modal = useModal(modalOptions);

  const confirm = useCallback(async () => {
    if (!onConfirm) return;

    try {
      setIsLoading(true);
      setError(null);

      const result = await onConfirm();

      // Close modal if onConfirm returns true or undefined
      if (result !== false) {
        modal.close();
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setIsLoading(false);
    }
  }, [onConfirm, modal.close]);

  const cancel = useCallback(() => {
    onCancel?.();
    modal.close();
  }, [onCancel, modal.close]);

  const clearError = useCallback(() => {
    setError(null);
  }, []);

  return {
    ...modal,
    isLoading,
    error,
    confirm,
    cancel,
    clearError,
  };
}

/**
 * Hook for confirmation dialogs with customizable actions
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const confirm = useConfirmModal({
 *     title: "Delete Item",
 *     message: "Are you sure you want to delete this item?",
 *     onConfirm: () => deleteItem(),
 *   });
 *
 *   return (
 *     <div>
 *       <Button onClick={() => confirm.show()}>Delete</Button>
 *       {confirm.modal}
 *     </div>
 *   );
 * }
 * ```
 */
export interface UseConfirmModalOptions {
  title?: string;
  message?: string;
  confirmText?: string;
  cancelText?: string;
  variant?: "destructive" | "primary" | "secondary";
  onConfirm?: () => void | Promise<void>;
  onCancel?: () => void;
}

export function useConfirmModal(options: UseConfirmModalOptions = {}) {
  const {
    title = "Confirm Action",
    message = "Are you sure you want to proceed?",
    confirmText = "Confirm",
    cancelText = "Cancel",
    variant = "primary",
    onConfirm,
    onCancel,
  } = options;

  const modal = useAsyncModal({
    onConfirm: async () => {
      await onConfirm?.();
      return true; // Close modal after confirmation
    },
    onCancel,
  });

  const show = useCallback(() => modal.open(), [modal.open]);

  return {
    show,
    isOpen: modal.isOpen,
    close: modal.close,
    isLoading: modal.isLoading,
    error: modal.error,
    // Modal props for easy integration
    modalProps: {
      ...modal.modalProps,
      title,
      size: "sm" as const,
      closeOnOverlayClick: false,
    },
    // Content configuration
    content: {
      message,
      confirmText,
      cancelText,
      variant,
    },
    // Actions
    confirm: modal.confirm,
    cancel: modal.cancel,
  };
}

/**
 * Hook for popover-based confirmation dialogs
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const confirm = useConfirmPopover({
 *     title: "Delete Item",
 *     message: "Are you sure you want to delete this item?",
 *     onConfirm: () => deleteItem(),
 *   });
 *
 *   return (
 *     <div>
 *       {confirm.popover}
 *     </div>
 *   );
 * }
 * ```
 */
export interface UseConfirmPopoverOptions {
  title?: string;
  message?: string;
  confirmText?: string;
  cancelText?: string;
  variant?: "destructive" | "primary" | "secondary";
  placement?: PopoverProps["placement"];
  icon?: React.ReactNode;
  onConfirm?: () => void | Promise<void>;
  onCancel?: () => void;
}

export function useConfirmPopover(options: UseConfirmPopoverOptions = {}) {
  const {
    title,
    message = "Are you sure you want to proceed?",
    confirmText = "Confirm",
    cancelText = "Cancel",
    variant = "primary",
    placement = "bottom-start",
    icon,
    onConfirm,
    onCancel,
  } = options;

  const [isOpen, setIsOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const open = useCallback(() => {
    setIsOpen(true);
    setError(null);
  }, []);

  const close = useCallback(() => {
    if (!isLoading) {
      setIsOpen(false);
      setError(null);
    }
  }, [isLoading]);

  const confirm = useCallback(async () => {
    if (!onConfirm) return;

    try {
      setIsLoading(true);
      setError(null);

      await onConfirm();
      setIsOpen(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setIsLoading(false);
    }
  }, [onConfirm]);

  const cancel = useCallback(() => {
    onCancel?.();
    close();
  }, [onCancel, close]);

  return {
    isOpen,
    open,
    close,
    confirm,
    cancel,
    isLoading,
    error,
    // Props for the ConfirmPopover component
    popoverProps: {
      open: isOpen,
      onOpenChange: setIsOpen,
      title,
      message,
      confirmText,
      cancelText,
      variant,
      placement,
      icon,
      isLoading,
      error,
      onConfirm: confirm,
      onCancel: cancel,
    },
  };
}
