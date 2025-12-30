#!/bin/bash
#
# Backup and Restore Library
# Handles backing up and restoring configuration files
#

set -e

# Colors for output
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

log_info() {
    printf "%b\n" "${GREEN}[INFO]${NC} $1" >&2
}

log_error() {
    printf "%b\n" "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    printf "%b\n" "${YELLOW}[WARN]${NC} $1" >&2
}

# Create timestamped backup of configuration files
backup_configs() {
    local backup_dir="$1"
    local timestamp=$(date '+%Y-%m-%d_%H%M%S')
    local backup_path="$backup_dir/$timestamp"

    log_info "Creating backup: $backup_path"

    mkdir -p "$backup_path"

    # Files to backup
    local files_to_backup=(
        "$HOME/.config/hypr/hyprland.conf"
        "$HOME/.config/hypr/colors.conf"
        "$HOME/.config/kitty/kitty.conf"
        "$HOME/.config/mako/config"
        "$HOME/.config/waybar/style.css"
        "$HOME/.config/wofi/style.css"
        "/etc/ly/config.ini"
    )

    local backed_up=0
    for file in "${files_to_backup[@]}"; do
        if [ -f "$file" ]; then
            local rel_path="${file#$HOME/}"
            local backup_file="$backup_path/$rel_path"
            mkdir -p "$(dirname "$backup_file")"
            cp "$file" "$backup_file"
            log_info "Backed up: $rel_path"
            ((backed_up++))
        fi
    done

    log_info "Backup complete: $backed_up files backed up"
    echo "$backup_path"
    return 0
}

# Restore from specific backup
restore_backup() {
    local backup_dir="$1"
    local backup_name="$2"
    local backup_path="$backup_dir/$backup_name"

    if [ ! -d "$backup_path" ]; then
        log_error "Backup not found: $backup_path"
        return 1
    fi

    log_info "Restoring from backup: $backup_name"

    local restore_failed=0

    # Find all backed up files and restore them
    while IFS= read -r file; do
        local rel_path="${file#$backup_path/}"
        local target="$HOME/$rel_path"

        # Check if this is a system file (/etc/...) that should be restored to root
        if [[ "$rel_path" == "etc/"* ]]; then
            # Restore to /etc/... instead of $HOME/etc/...
            target="/${rel_path}"
        fi

        # Check if we need sudo for this file
        if [[ "$target" == "/etc/"* ]] && [ ! -w "$(dirname "$target")" ]; then
            log_warn "File requires sudo to restore: $rel_path"
            printf "%b\n" "${YELLOW}[SUDO]${NC} Password required to restore system files:" >&2

            # Create parent directory if needed (with sudo if necessary)
            local parent_dir="$(dirname "$target")"
            if [ ! -d "$parent_dir" ]; then
                if ! sudo mkdir -p "$parent_dir"; then
                    log_error "Failed to create directory: $parent_dir"
                    restore_failed=1
                    continue
                fi
            fi

            # Copy with sudo
            if sudo cp "$file" "$target"; then
                log_info "Restored: $rel_path (via sudo)"
            else
                log_error "Failed to restore: $rel_path"
                restore_failed=1
            fi
        else
            # Regular restore (user permissions)
            mkdir -p "$(dirname "$target")" 2>/dev/null || true
            if cp "$file" "$target"; then
                log_info "Restored: $rel_path"
            else
                log_error "Failed to restore: $rel_path"
                restore_failed=1
            fi
        fi
    done < <(find "$backup_path" -type f)

    if [ $restore_failed -ne 0 ]; then
        log_error "Some files failed to restore"
        return 1
    fi

    log_info "Restore complete"
    return 0
}

# List available backups
list_backups() {
    local backup_dir="$1"

    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        log_warn "No backups found"
        return 0
    fi

    echo -e "\n${BLUE}Available backups:${NC}" >&2
    ls -t "$backup_dir" | while read -r backup; do
        local backup_date=$(echo "$backup" | cut -d'_' -f1-3)
        local backup_time=$(echo "$backup" | cut -d'_' -f4 | sed 's/\(..\)/\1:\1:/g' | sed 's/:$//')
        echo "  $backup" >&2
    done
    echo "" >&2
}

# Save color palette as JSON
save_palette() {
    local palette_dir="$1"
    local image_path="$2"
    local palette_name="$3"
    local colors_env="$4"

    # If colors_env not provided, try to derive it
    if [ -z "$colors_env" ]; then
        colors_env="$palette_dir/../colors.env"
    fi

    # Resolve to absolute path
    colors_env="$(cd "$(dirname "$colors_env")" && pwd)/$(basename "$colors_env")"

    if [ ! -f "$colors_env" ]; then
        log_error "colors.env not found: $colors_env"
        return 1
    fi

    log_info "Saving palette as JSON: $palette_name"

    mkdir -p "$palette_dir"

    # Parse colors.env and create JSON
    local json_file="$palette_dir/$palette_name.json"
    python3 << PYTHON_EOF
import json
import os
from datetime import datetime

# Load colors from env file
colors_env = "$colors_env"
colors = {}

with open(colors_env) as f:
    for line in f:
        line = line.strip()
        if line.startswith('export ') or line.startswith('#') or not line:
            continue
        if '=' in line:
            key, value = line.split('=', 1)
            colors[key.lower()] = value

# Create JSON structure
palette = {
    "name": "$palette_name",
    "timestamp": datetime.now().isoformat() + "Z",
    "source_image": "$image_path",
    "colors": colors
}

# Write JSON
with open("$json_file", 'w') as f:
    json.dump(palette, f, indent=2)

print("Saved: $json_file")
PYTHON_EOF

    return $?
}

# Load palette from JSON and apply it
load_palette() {
    local palette_dir="$1"
    local palette_name="$2"
    local output_colors_env="$3"

    local json_file="$palette_dir/$palette_name.json"

    if [ ! -f "$json_file" ]; then
        log_error "Palette not found: $json_file"
        return 1
    fi

    log_info "Loading palette: $palette_name"

    # Parse JSON and create colors.env
    python3 << PYTHON_EOF
import json

def hex_to_rgba_hex(hex_color):
    hex_color = hex_color.lstrip('#').upper()
    return f"{hex_color}ff"

json_file = "$json_file"
with open(json_file) as f:
    palette = json.load(f)

colors = palette['colors']

# Write colors.env
with open("$output_colors_env", 'w') as f:
    f.write(f"# Color palette - loaded from: $palette_name\n")
    f.write(f"# Generated: {palette['timestamp']}\n")
    f.write(f"# Source image: {palette['source_image']}\n\n")
    for key, value in colors.items():
        f.write(f"{key.upper()}={value}\n")

    # Add rgba hex format for specific colors needed by Hyprland
    f.write(f"\n# Rgba hex format for Hyprland\n")
    f.write(f"ACCENT_RGBA='{hex_to_rgba_hex(colors.get('accent', '#888888'))}'\n")
    f.write(f"BG_LIGHT_RGBA='{hex_to_rgba_hex(colors.get('bg_light', '#999999'))}'\n")
    f.write(f"BG_DARK_RGBA='{hex_to_rgba_hex(colors.get('bg_dark', '#000000'))}'\n")

    f.write("\nexport " + " ".join(colors.keys()).upper() + " ACCENT_RGBA BG_LIGHT_RGBA BG_DARK_RGBA\n")

print("Loaded palette: $palette_name")
PYTHON_EOF

    return $?
}

# List available palettes
list_palettes() {
    local palette_dir="$1"

    if [ ! -d "$palette_dir" ] || [ -z "$(ls -A "$palette_dir" 2>/dev/null)" ]; then
        log_warn "No saved palettes found"
        return 0
    fi

    echo -e "\n${BLUE}Available color palettes:${NC}" >&2
    ls "$palette_dir" | grep -E '\.json$' | sed 's/\.json$//' | while read -r palette; do
        echo "  $palette" >&2
    done
    echo "" >&2
}

# Get info about a specific palette
palette_info() {
    local palette_dir="$1"
    local palette_name="$2"

    local json_file="$palette_dir/$palette_name.json"

    if [ ! -f "$json_file" ]; then
        log_error "Palette not found: $palette_name"
        return 1
    fi

    echo -e "\n${BLUE}Palette: $palette_name${NC}" >&2
    python3 << PYTHON_EOF
import json
import sys

json_file = "$json_file"
with open(json_file) as f:
    palette = json.load(f)

print(f"  Timestamp: {palette['timestamp']}", file=sys.stderr)
print(f"  Source Image: {palette['source_image']}", file=sys.stderr)
print(f"  Colors:", file=sys.stderr)
for key, value in sorted(palette['colors'].items()):
    print(f"    {key.upper():12} = {value}", file=sys.stderr)
PYTHON_EOF

    echo "" >&2
    return 0
}
