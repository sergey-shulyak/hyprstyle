#!/bin/bash
#
# Hyprstyle - Hyprland Theme Generator
# Generates color schemes from images and applies them to all configured applications
#
# Usage:
#   ./hyprstyle.sh <image>              Generate theme from image
#   ./hyprstyle.sh --restore <backup>   Restore from backup
#   ./hyprstyle.sh --apply-palette <name> Apply saved palette
#   ./hyprstyle.sh --list               List backups and palettes
#   ./hyprstyle.sh --palette-info <name> Show palette details
#

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Directories
TEMPLATES_DIR="$SCRIPT_DIR/templates"
LIB_DIR="$SCRIPT_DIR/lib"
BACKUPS_DIR="$SCRIPT_DIR/backups"
PALETTES_DIR="$SCRIPT_DIR/palettes"
COLORS_ENV="$SCRIPT_DIR/colors.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source libraries
source "$LIB_DIR/color-extraction.sh"
source "$LIB_DIR/config-updater.sh"
source "$LIB_DIR/backup-restore.sh"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# Show usage information
show_usage() {
    cat << 'EOF'
Hyprstyle - Generate Hyprland color schemes from images

USAGE:
  ./hyprstyle.sh <image>              Generate theme from image file
  ./hyprstyle.sh --restore <backup>   Restore configuration from backup
  ./hyprstyle.sh --apply-palette <name> Apply previously saved color palette
  ./hyprstyle.sh --list               List available backups and palettes
  ./hyprstyle.sh --palette-info <name> Display palette color information
  ./hyprstyle.sh --help               Show this help message

EXAMPLES:
  # Generate theme from wallpaper
  ./hyprstyle.sh ~/Pictures/wallpaper.png

  # Restore previous configuration
  ./hyprstyle.sh --restore 2025-12-25_143022

  # Apply previously used color palette
  ./hyprstyle.sh --apply-palette my-theme

  # View available themes
  ./hyprstyle.sh --list

REQUIREMENTS:
  - pywal (for color extraction): paru -S python-pywal
  - python3
  - bash 4+

EOF
}

# Validate that all required libraries and templates exist
validate_setup() {
    local valid=1

    if [ ! -d "$TEMPLATES_DIR" ]; then
        log_error "Templates directory not found: $TEMPLATES_DIR"
        valid=0
    fi

    if [ ! -d "$LIB_DIR" ]; then
        log_error "Libraries directory not found: $LIB_DIR"
        valid=0
    fi

    # Check for all template files
    local required_templates=(
        "hyprland.colors.conf"
        "kitty.conf"
        "mako.config"
        "waybar.style.css"
        "wofi.style.css"
    )

    for template in "${required_templates[@]}"; do
        if [ ! -f "$TEMPLATES_DIR/$template" ]; then
            log_error "Template not found: $TEMPLATES_DIR/$template"
            valid=0
        fi
    done

    if [ $valid -eq 0 ]; then
        return 1
    fi

    return 0
}

# Main function to generate theme from image
generate_theme_from_image() {
    local image_path="$1"

    print_header "Generating Theme from Image"

    # Check dependencies
    if ! check_dependencies; then
        log_error "Missing required dependencies"
        return 1
    fi

    # Create backup before making changes
    log_info "Backing up current configuration..."
    local backup_path=$(backup_configs "$BACKUPS_DIR")
    log_info "Backup created at: $backup_path"

    # Extract colors and create colors.env
    if ! create_colors_env "$COLORS_ENV" "$image_path"; then
        log_error "Failed to create color palette"
        return 1
    fi

    # Load colors from colors.env
    if ! load_colors "$COLORS_ENV"; then
        log_error "Failed to load colors"
        return 1
    fi

    # Update all configurations
    if ! update_all_configs "$TEMPLATES_DIR"; then
        log_error "Failed to update configurations"
        log_warn "You can restore from backup: $backup_path"
        return 1
    fi

    # Set wallpaper
    set_wallpaper "$image_path"

    print_header "Theme Generation Complete"
    log_info "Colors exported to: $COLORS_ENV"

    # Save palette for future use
    local palette_name=$(basename "$image_path" | sed 's/\.[^.]*$//')
    if save_palette "$PALETTES_DIR" "$image_path" "$palette_name"; then
        log_info "Palette saved as: $palette_name"
    fi

    # Reload components
    reload_components

    echo -e "\n${GREEN}✓ Theme generated successfully!${NC}"
    echo -e "\nNext steps:"
    echo "  1. Commit changes to git (optional)"
    echo "  2. To restore this backup later: ./hyprstyle.sh --restore $backup_path"
    echo ""

    return 0
}

# Restore from backup
restore_from_backup() {
    local backup_name="$1"

    print_header "Restoring from Backup"

    if [ -z "$backup_name" ]; then
        log_error "Backup name required"
        list_backups "$BACKUPS_DIR"
        return 1
    fi

    if ! restore_backup "$BACKUPS_DIR" "$backup_name"; then
        return 1
    fi

    # Reload components
    reload_components

    print_header "Restore Complete"
    echo -e "${GREEN}✓ Configuration restored successfully!${NC}"
    echo -e "\nNext steps:"
    echo "  1. Your theme has been restored and components reloaded"
    echo ""

    return 0
}

# Apply saved palette
apply_palette() {
    local palette_name="$1"

    print_header "Applying Palette"

    if [ -z "$palette_name" ]; then
        log_error "Palette name required"
        list_palettes "$PALETTES_DIR"
        return 1
    fi

    # Create backup before making changes
    log_info "Backing up current configuration..."
    local backup_path=$(backup_configs "$BACKUPS_DIR")
    log_info "Backup created at: $backup_path"

    # Load palette into colors.env
    if ! load_palette "$PALETTES_DIR" "$palette_name" "$COLORS_ENV"; then
        return 1
    fi

    # Load colors
    if ! load_colors "$COLORS_ENV"; then
        log_error "Failed to load colors"
        return 1
    fi

    # Update all configurations
    if ! update_all_configs "$TEMPLATES_DIR"; then
        log_error "Failed to update configurations"
        log_warn "You can restore from backup: $backup_path"
        return 1
    fi

    # Reload components
    reload_components

    print_header "Palette Applied"
    echo -e "${GREEN}✓ Palette applied successfully!${NC}"
    echo -e "\nNext steps:"
    echo "  1. Your theme has been applied and components reloaded"
    echo ""

    return 0
}

# List backups and palettes
list_all() {
    print_header "Available Backups and Palettes"

    list_backups "$BACKUPS_DIR"
    list_palettes "$PALETTES_DIR"
}

# Reload all components after theme changes
reload_components() {
    print_header "Reloading Components"

    # Reload Hyprland
    if command -v hyprctl &>/dev/null; then
        log_info "Reloading Hyprland..."
        hyprctl reload 2>/dev/null || log_warn "Failed to reload Hyprland"
    else
        log_warn "hyprctl not found, skipping Hyprland reload"
    fi

    # Restart Waybar
    if systemctl --user is-enabled waybar &>/dev/null; then
        log_info "Restarting Waybar..."
        systemctl --user restart waybar 2>/dev/null || log_warn "Failed to restart Waybar"
    else
        log_warn "Waybar not enabled, skipping restart"
    fi

    # Restart Mako
    if systemctl --user is-enabled mako &>/dev/null; then
        log_info "Restarting Mako..."
        systemctl --user restart mako 2>/dev/null || log_warn "Failed to restart Mako"
    else
        log_warn "Mako not enabled, skipping restart"
    fi

    log_info "Component reload complete"
    return 0
}

# Main script logic
main() {
    # Validate setup
    if ! validate_setup; then
        log_error "Setup validation failed"
        return 1
    fi

    # Parse arguments
    case "${1:-}" in
        --help|-h)
            show_usage
            return 0
            ;;
        --list|-l)
            list_all
            return 0
            ;;
        --restore|-r)
            restore_from_backup "$2"
            return $?
            ;;
        --apply-palette|-p)
            apply_palette "$2"
            return $?
            ;;
        --palette-info|-i)
            palette_info "$PALETTES_DIR" "$2"
            return $?
            ;;
        "")
            show_usage
            return 1
            ;;
        *)
            if [ ! -f "$1" ]; then
                log_error "Image file not found: $1"
                return 1
            fi
            generate_theme_from_image "$1"
            return $?
            ;;
    esac
}

# Run main function
main "$@"
