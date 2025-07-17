import { motion, AnimatePresence } from "framer-motion";
import type React from "react";
import { cn } from "@/lib/utils";

export interface AnimatedCollapseProps {
  isOpen: boolean;
  children: React.ReactNode;
  className?: string;
  animationDuration?: number;
}

export function AnimatedCollapse({
  isOpen,
  children,
  className,
  animationDuration = 0.3,
}: AnimatedCollapseProps) {
  return (
    <AnimatePresence initial={false}>
      {isOpen && (
        <motion.div
          initial={{ height: 0, opacity: 0 }}
          animate={{ height: "auto", opacity: 1 }}
          exit={{ height: 0, opacity: 0 }}
          transition={{
            duration: animationDuration,
            ease: "easeOut",
          }}
          style={{ overflow: "hidden" }}
          className={cn("", className)}
        >
          <motion.div
            initial={{ y: -10 }}
            animate={{ y: 0 }}
            exit={{ y: -10 }}
            transition={{
              duration: animationDuration,
              ease: "easeOut",
            }}
          >
            {children}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
