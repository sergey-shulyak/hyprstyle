#!/bin/bash
#
# Restore Configuration Backup
# Interactive script to restore a previous Hyprland theme/config backup
#
# Usage:
#   ./restore-backup.sh              Interactive backup selection
#   ./restore-backup.sh <backup>     Restore specific backup (YYYY-MM-DD_HHMMSS)
#

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Directories
LIB_DIR="$SCRIPT_DIR/lib"
BACKUPS_DIR="$SCRIPT_DIR/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source libraries
source "$LIB_DIR/backup-restore.sh"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n" >&2
}

# Show available backups and let user select one
interactive_backup_select() {
    print_header "Available Backups"

    # Get list of backups sorted by newest first
    local backups=($(ls -1tr "$BACKUPS_DIR" | tac))

    if [ ${#backups[@]} -eq 0 ]; then
        return 1
    fi

    # Display backups with numbers
    local i=1
    for backup in "${backups[@]}"; do
        local backup_date=$(echo "$backup" | cut -d'_' -f1-3)
        local backup_time=$(echo "$backup" | cut -d'_' -f4)
        # Format time HH:MM:SS
        local formatted_time="${backup_time:0:2}:${backup_time:2:2}:${backup_time:4:2}"

        printf "  %2d) %s at %s\n" "$i" "$backup_date" "$formatted_time"
        ((i++))
    done

    echo ""
    read -p "Select backup to restore (1-${#backups[@]}): " selection

    # Validate selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#backups[@]} ]; then
        log_error "Invalid selection"
        return 1
    fi

    # Convert to array index (1-based to 0-based)
    local index=$((selection - 1))
    echo "${backups[$index]}"
}

# Show detailed info about a backup before restoring
show_backup_info() {
    local backup_name="$1"
    local backup_path="$BACKUPS_DIR/$backup_name"

    if [ ! -d "$backup_path" ]; then
        log_error "Backup not found: $backup_name"
        return 1
    fi

    echo -e "\n${BLUE}Backup Details:${NC}"
    echo "  Name: $backup_name"

    # Show file count
    local file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l)
    echo "  Files: $file_count"

    # Show files in backup
    echo "  Contents:"
    find "$backup_path" -type f 2>/dev/null | sed 's|^|    |'

    echo ""
}

# Confirm before restoring
confirm_restore() {
    local backup_name="$1"

    read -p "Are you sure you want to restore this backup? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "Restore cancelled"
        return 1
    fi

    return 0
}

# Main script
main() {
    local backup_name="${1:-}"

    print_header "Restore Configuration Backup"

    # If no backup specified, let user choose
    if [ -z "$backup_name" ]; then
        # Check if backups exist
        if [ ! -d "$BACKUPS_DIR" ] || [ -z "$(ls -A "$BACKUPS_DIR" 2>/dev/null)" ]; then
            log_error "No backups available"
            log_info "Generate a theme first with: ./hyprstyle.sh <image>"
            return 1
        fi

        backup_name=$(interactive_backup_select) || return 1
    fi

    # Show backup info
    show_backup_info "$backup_name" || return 1

    # Confirm restore
    if ! confirm_restore "$backup_name"; then
        return 1
    fi

    # Perform restore
    log_info "Restoring from backup: $backup_name"

    if ! restore_backup "$BACKUPS_DIR" "$backup_name"; then
        log_error "Restore failed"
        return 1
    fi

    print_header "Restore Complete"
    echo -e "${GREEN}✓ Configuration restored successfully!${NC}"
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo "  1. Reload Hyprland with: super+shift+r"
    echo "  2. Or restart your session"
    echo ""

    return 0
}

# Run main function
main "$@"
