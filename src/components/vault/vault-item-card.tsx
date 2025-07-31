import { Button } from "@heroui/button";
import { Card, CardBody } from "@heroui/card";
import { Chip } from "@heroui/chip";
import { CreditCard, Edit, Eye, FileText, Key, Shield, Star, Trash2, User } from "lucide-react";
import type React from "react";
import { cn } from "@/lib/utils";
import type { CipherType, CipherView } from "@/types/vault.types";
import {
  formatRelativeTime,
  getCipherTypeColor,
  getCipherTypeDisplayName,
} from "@/utils/vault-helpers";

export interface VaultItemCardProps {
  item: CipherView;
  onView?: (item: CipherView) => void;
  onEdit?: (item: CipherView) => void;
  onDelete?: (item: CipherView) => void;
  className?: string;
}

// Helper function to get cipher type icon
function getCipherTypeIcon(type: CipherType): React.ReactNode {
  const iconProps = { size: 16, className: "text-current" };

  switch (type) {
    case "Login":
      return <Key {...iconProps} />;
    case "SecureNote":
      return <FileText {...iconProps} />;
    case "Card":
      return <CreditCard {...iconProps} />;
    case "Identity":
      return <User {...iconProps} />;
    default:
      return <Key {...iconProps} />;
  }
}

// Helper function to get item subtitle based on type
function getItemSubtitle(item: CipherView): string {
  switch (item.cipher_type) {
    case "Login":
      return item.login?.username || item.login?.uris[0]?.uri || "No username";
    case "Card":
      return item.card?.number || "No card number";
    case "Identity":
      return (
        item.identity?.email ||
        `${item.identity?.first_name || ""} ${item.identity?.last_name || ""}`.trim() ||
        "No name"
      );
    case "SecureNote":
      return item.notes
        ? item.notes.length > 50
          ? `${item.notes.substring(0, 50)}...`
          : item.notes
        : "No notes";
    default:
      return "";
  }
}

export function VaultItemCard(props: VaultItemCardProps) {
  const { item, onView, onEdit, onDelete, className } = props;

  const handleView = () => {
    onView?.(item);
  };

  const handleEdit = () => {
    onEdit?.(item);
  };

  const handleDelete = () => {
    onDelete?.(item);
  };

  const subtitle = getItemSubtitle(item);
  const typeColor = getCipherTypeColor(item.cipher_type);
  const typeDisplayName = getCipherTypeDisplayName(item.cipher_type);
  const lastModified = formatRelativeTime(item.revision_date);

  return (
    <Card
      className={cn(
        "transition-all duration-200 hover:shadow-md hover:border-primary/20",
        className
      )}
      isHoverable
    >
      <CardBody className="p-4">
        <div className="flex items-center justify-between gap-4">
          {/* Left side - Item info */}
          <div className="flex items-center gap-3 flex-1 min-w-0">
            {/* Type icon and favorite indicator */}
            <div className="flex items-center gap-1">
              <div
                className={cn(
                  "flex items-center justify-center w-8 h-8 rounded-md",
                  `bg-${typeColor}/10 text-${typeColor}`
                )}
              >
                {getCipherTypeIcon(item.cipher_type)}
              </div>
              {item.favorite && (
                <Star
                  size={12}
                  className="text-warning fill-warning ml-1"
                  aria-label="Favorite item"
                />
              )}
              {item.reprompt && (
                <Shield
                  size={12}
                  className="text-info ml-1"
                  aria-label="Requires master password reprompt"
                />
              )}
            </div>

            {/* Item details */}
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 mb-1">
                <h3 className="font-medium text-foreground truncate">{item.name}</h3>
                <Chip
                  size="sm"
                  variant="flat"
                  color={
                    typeColor as
                      | "primary"
                      | "secondary"
                      | "success"
                      | "warning"
                      | "danger"
                      | "default"
                  }
                  className="text-xs"
                >
                  {typeDisplayName}
                </Chip>
              </div>

              {subtitle && <p className="text-sm text-muted-foreground truncate">{subtitle}</p>}

              <p className="text-xs text-muted-foreground mt-1">Modified {lastModified}</p>
            </div>
          </div>

          {/* Right side - Action buttons */}
          <div className="flex items-center gap-1 flex-shrink-0">
            <Button
              isIconOnly
              size="sm"
              variant="ghost"
              onPress={handleView}
              className="text-default-500 hover:text-primary hover:bg-primary/10"
              aria-label={`View ${item.name}`}
            >
              <Eye size={16} />
            </Button>

            <Button
              isIconOnly
              size="sm"
              variant="ghost"
              onPress={handleEdit}
              className="text-default-500 hover:text-warning hover:bg-warning/10"
              aria-label={`Edit ${item.name}`}
            >
              <Edit size={16} />
            </Button>

            <Button
              isIconOnly
              size="sm"
              variant="ghost"
              onPress={handleDelete}
              className="text-default-500 hover:text-danger hover:bg-danger/10"
              aria-label={`Delete ${item.name}`}
            >
              <Trash2 size={16} />
            </Button>
          </div>
        </div>
      </CardBody>
    </Card>
  );
}
