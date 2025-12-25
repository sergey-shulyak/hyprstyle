#!/bin/bash
#
# Config Updater Library
# Applies color values to config file templates
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Source colors from colors.env file
load_colors() {
    local colors_file="$1"

    if [ ! -f "$colors_file" ]; then
        log_error "Colors file not found: $colors_file"
        return 1
    fi

    # Source the colors
    set -a
    source "$colors_file"
    set +a

    return 0
}

# Apply template substitution
apply_template() {
    local template_file="$1"
    local output_file="$2"
    local temp_file="${output_file}.tmp"

    if [ ! -f "$template_file" ]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    log_info "Applying template: $(basename "$template_file")"

    # Use sed for Hyprland templates (uses @@ format), envsubst for others (uses ${} format)
    if [[ "$template_file" == *"hyprland"* ]]; then
        # Use sed to replace @@VARNAME@@ with environment variable values
        sed_cmd="cat \"$template_file\""
        for var in PRIMARY SECONDARY ACCENT BG TEXT ERROR SUCCESS WARNING BG_LIGHT BG_DARK ACCENT_RGBA BG_LIGHT_RGBA BG_DARK_RGBA; do
            value=$(eval echo \$${var})
            sed_cmd="$sed_cmd | sed \"s|@@${var}@@|${value}|g\""
        done
        eval "$sed_cmd" > "$temp_file"
    else
        # Use envsubst for ${VARNAME} format
        envsubst < "$template_file" > "$temp_file"
    fi

    if [ $? -ne 0 ]; then
        log_error "Failed to apply template: $template_file"
        rm -f "$temp_file"
        return 1
    fi

    # Move temp to output (atomic operation)
    mv "$temp_file" "$output_file"
    log_info "Updated: $output_file"
    return 0
}

# Update Hyprland colors
update_hyprland() {
    local template_dir="$1"
    local config_dir="$HOME/.config/hypr"

    log_info "Updating Hyprland configuration..."

    # Create colors.conf from template
    apply_template \
        "$template_dir/hyprland.colors.conf" \
        "$config_dir/colors.conf" || return 1

    # Check if colors.conf is sourced in hyprland.conf
    if ! grep -q "source = ~/.config/hypr/colors.conf" "$config_dir/hyprland.conf"; then
        log_warn "Adding 'source = ~/.config/hypr/colors.conf' to hyprland.conf"
        echo "source = ~/.config/hypr/colors.conf" >> "$config_dir/hyprland.conf"
    fi

    return 0
}

# Update Kitty configuration
update_kitty() {
    local template_dir="$1"
    local config_dir="$HOME/.config/kitty"
    local config_file="$config_dir/kitty.conf"

    log_info "Updating Kitty configuration..."

    # Apply full template (replaces entire file)
    apply_template "$template_dir/kitty.conf" "$config_file" || return 1

    log_info "Updated: $config_file"
    return 0
}

# Update Mako configuration
update_mako() {
    local template_dir="$1"
    local config_dir="$HOME/.config/mako"
    local config_file="$config_dir/config"

    log_info "Updating Mako configuration..."

    if [ ! -d "$config_dir" ]; then
        log_warn "Mako config directory not found, creating: $config_dir"
        mkdir -p "$config_dir"
    fi

    apply_template "$template_dir/mako.config" "$config_file" || return 1

    return 0
}

# Update Waybar configuration
update_waybar() {
    local template_dir="$1"
    local config_dir="$HOME/.config/waybar"
    local style_file="$config_dir/style.css"

    log_info "Updating Waybar configuration..."

    if [ ! -d "$config_dir" ]; then
        log_error "Waybar config directory not found: $config_dir"
        return 1
    fi

    # Create temporary file with new styles
    local temp_file=$(mktemp)
    apply_template "$template_dir/waybar.style.css" "$temp_file" || return 1

    # Replace existing style.css
    mv "$temp_file" "$style_file"
    log_info "Updated: $style_file"

    return 0
}

# Update Wofi configuration
update_wofi() {
    local template_dir="$1"
    local config_dir="$HOME/.config/wofi"
    local style_file="$config_dir/style.css"

    log_info "Updating Wofi configuration..."

    if [ ! -d "$config_dir" ]; then
        log_warn "Wofi config directory not found, creating: $config_dir"
        mkdir -p "$config_dir"
    fi

    apply_template "$template_dir/wofi.style.css" "$style_file" || return 1

    return 0
}

# Update all application configurations
update_all_configs() {
    local template_dir="$1"

    log_info "Updating all application configurations..."

    update_hyprland "$template_dir" || log_warn "Failed to update Hyprland"
    update_kitty "$template_dir" || log_warn "Failed to update Kitty"
    update_mako "$template_dir" || log_warn "Failed to update Mako"
    update_waybar "$template_dir" || log_warn "Failed to update Waybar"
    update_wofi "$template_dir" || log_warn "Failed to update Wofi"

    log_info "Configuration update complete"
    return 0
}

# Validate that substitution worked correctly
validate_color_format() {
    local file="$1"
    local color_pattern="$2"

    # Check if file contains template placeholders
    if grep -q '\${[A-Z_]*}' "$file"; then
        log_warn "File still contains template placeholders: $file"
        return 1
    fi

    return 0
}

# Set wallpaper using hyprpaper
set_wallpaper() {
    local image_path="$1"

    if [ ! -f "$image_path" ]; then
        log_warn "Image file not found, skipping wallpaper: $image_path"
        return 0
    fi

    # Check if hyprpaper is available
    if ! command -v hyprpaper &>/dev/null; then
        log_warn "hyprpaper not found, skipping wallpaper setting"
        return 0
    fi

    log_info "Setting wallpaper with hyprpaper..."

    # Create hyprpaper config
    local hyprpaper_config="$HOME/.config/hypr/hyprpaper.conf"

    # Get all monitors from Hyprland
    local monitors
    if command -v jq &>/dev/null; then
        monitors=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | .name')
    else
        # Fallback: Extract monitor names using grep and tr
        # Monitor JSON starts with "name" as the second key after "id"
        monitors=$(hyprctl monitors -j 2>/dev/null | grep '"name"' | head -n $(hyprctl monitors -j 2>/dev/null | grep -c '^\s*{') | sed 's/.*"name"\s*:\s*"\([^"]*\)".*/\1/')
    fi

    if [ -z "$monitors" ]; then
        log_warn "Could not detect monitors, skipping wallpaper"
        return 0
    fi

    # Generate hyprpaper config
    {
        echo "preload = $image_path"
        while read -r monitor; do
            echo "wallpaper = $monitor,$image_path"
        done <<< "$monitors"
    } > "$hyprpaper_config"

    log_info "Created hyprpaper config at $hyprpaper_config"

    # Restart hyprpaper to apply new config
    pkill hyprpaper 2>/dev/null || true
    sleep 0.5
    hyprpaper & 2>/dev/null || true

    return 0
}
