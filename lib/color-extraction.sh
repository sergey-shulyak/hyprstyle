#!/bin/bash
#
# Color Extraction Library
# Extracts colors from images using pywal and generates color palette
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

# Check if required tools are installed
check_dependencies() {
    local missing=0

    if ! command -v wal &>/dev/null; then
        log_error "pywal not found. Install with: paru -S python-pywal"
        missing=1
    fi

    if ! command -v python &>/dev/null; then
        log_error "Python not found"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        return 1
    fi
    return 0
}

# Extract colors from image using pywal
extract_colors_from_image() {
    local image_path="$1"

    if [ ! -f "$image_path" ]; then
        log_error "Image file not found: $image_path"
        return 1
    fi

    log_info "Extracting colors from: $image_path"

    # Use wal to extract colors (generates ~/.config/wal/colorscheme.json)
    wal -i "$image_path" -c -s -t 2>/dev/null

    if [ $? -ne 0 ]; then
        log_error "Failed to extract colors with pywal"
        return 1
    fi

    log_info "Colors extracted successfully"
    return 0
}

# Parse wal colorscheme and generate our color variables
generate_color_palette() {
    local wal_file="$HOME/.config/wal/colorscheme.json"

    if [ ! -f "$wal_file" ]; then
        log_error "Wal colorscheme file not found: $wal_file"
        return 1
    fi

    log_info "Generating color palette from wal output"

    # Parse JSON and extract colors
    local colors=()
    colors+=($(python -c "import json; data=json.load(open('$wal_file')); print(data['special']['background'])")_)
    colors+=($(python -c "import json; data=json.load(open('$wal_file')); print(data['special']['foreground'])")_)
    colors+=($(python -c "import json; data=json.load(open('$wal_file')); [print(c.strip()) for c in data['colors'].values()]" 2>/dev/null)_)

    # Extract key colors from palette
    python3 << 'PYTHON_EOF'
import json
import sys

wal_file = "$HOME/.config/wal/colorscheme.json"
try:
    with open(wal_file.replace('$HOME', os.path.expanduser('~'))) as f:
        data = json.load(f)
except:
    sys.exit(1)

# Get colors from wal output
colors = data['colors']
special = data['special']

# Map wal colors to our semantic names
bg = special['background']
text = special['foreground']

# Use bright colors from palette for accents
color1 = colors.get('1', '#ff0000')  # Red
color2 = colors.get('2', '#00ff00')  # Green
color3 = colors.get('3', '#ffff00')  # Yellow
color4 = colors.get('4', '#0000ff')  # Blue
color5 = colors.get('5', '#ff00ff')  # Magenta
color6 = colors.get('6', '#00ffff')  # Cyan

# Output as environment variables
print(f"PRIMARY={color4}")      # Blue as primary
print(f"SECONDARY={color6}")    # Cyan as secondary
print(f"ACCENT={color5}")       # Magenta as accent
print(f"BG={bg}")
print(f"TEXT={text}")
print(f"ERROR={color1}")        # Red for errors
print(f"SUCCESS={color2}")      # Green for success
print(f"WARNING={color3}")      # Yellow for warnings
PYTHON_EOF

}

# Generate light/dark variants of a color
generate_variants() {
    local bg_color="$1"

    python3 << PYTHON_EOF
import colorsys
import sys

def hex_to_rgb(hex_color):
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

def rgb_to_hex(rgb):
    return '#{:02x}{:02x}{:02x}'.format(int(rgb[0]), int(rgb[1]), int(rgb[2]))

def lighten(hex_color, factor=0.2):
    rgb = hex_to_rgb(hex_color)
    rgb = tuple(min(255, c + int(255 * factor)) for c in rgb)
    return rgb_to_hex(rgb)

def darken(hex_color, factor=0.2):
    rgb = hex_to_rgb(hex_color)
    rgb = tuple(max(0, c - int(255 * factor)) for c in rgb)
    return rgb_to_hex(rgb)

bg = "$bg_color"
print(f"BG_LIGHT={lighten(bg, 0.15)}")
print(f"BG_DARK={darken(bg, 0.15)}")
PYTHON_EOF
}

# Create colors.env file with all color variables
create_colors_env() {
    local colors_file="$1"
    local image_path="$2"

    log_info "Creating colors environment file: $colors_file"

    # Extract colors from image
    extract_colors_from_image "$image_path" || return 1

    # Get base colors
    local wal_file="$HOME/.config/wal/colorscheme.json"
    local palette=$(python3 << 'PYTHON_EOF'
import json
import os

wal_file = os.path.expanduser("~/.config/wal/colorscheme.json")
with open(wal_file) as f:
    data = json.load(f)

colors = data['colors']
special = data['special']

bg = special['background']
text = special['foreground']

# Color mapping (using standard ANSI positions)
primary = colors.get('4', '#0000ff')      # Blue
secondary = colors.get('6', '#00ffff')    # Cyan
accent = colors.get('5', '#ff00ff')       # Magenta
error = colors.get('1', '#ff0000')        # Red
success = colors.get('2', '#00ff00')      # Green
warning = colors.get('3', '#ffff00')      # Yellow

print(f"PRIMARY={primary}")
print(f"SECONDARY={secondary}")
print(f"ACCENT={accent}")
print(f"BG={bg}")
print(f"TEXT={text}")
print(f"ERROR={error}")
print(f"SUCCESS={success}")
print(f"WARNING={warning}")

# Generate variants
import colorsys

def hex_to_rgb(hex_color):
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

def rgb_to_hex(rgb):
    return '#{:02x}{:02x}{:02x}'.format(int(rgb[0]), int(rgb[1]), int(rgb[2]))

def lighten(hex_color, factor=0.15):
    rgb = hex_to_rgb(hex_color)
    rgb = tuple(min(255, c + int(255 * factor)) for c in rgb)
    return rgb_to_hex(rgb)

def darken(hex_color, factor=0.15):
    rgb = hex_to_rgb(hex_color)
    rgb = tuple(max(0, c - int(255 * factor)) for c in rgb)
    return rgb_to_hex(rgb)

print(f"BG_LIGHT={lighten(bg)}")
print(f"BG_DARK={darken(bg)}")
PYTHON_EOF
)

    # Write to colors.env
    cat > "$colors_file" << EOF
# Color palette - auto-generated by hyprstyle
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Source image: $image_path

# Semantic colors
$palette

# Export for use in other scripts
export PRIMARY SECONDARY ACCENT BG TEXT ERROR SUCCESS WARNING BG_LIGHT BG_DARK
EOF

    log_info "Color palette created successfully"
    return 0
}
