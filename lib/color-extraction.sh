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

# Convert hex color to rgba format (for Hyprland gradients)
hex_to_rgba() {
    local hex="$1"
    local alpha="${2:-ff}"  # Default to full opacity

    # Remove '#' if present
    hex="${hex#\#}"

    # Convert to uppercase for consistency
    hex="${hex^^}"

    # Extract RGB components
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))

    # Convert alpha from hex to decimal
    local a=$((16#${alpha}))

    echo "rgba($r, $g, $b, 0x${alpha})"
}

# Extract colors from image using ImageMagick
extract_colors_from_image() {
    local image_path="$1"

    if [ ! -f "$image_path" ]; then
        log_error "Image file not found: $image_path"
        return 1
    fi

    log_info "Extracting colors from: $image_path"

    # Run pywal to generate colors (even if we don't use its JSON directly)
    wal -i "$image_path" -n 2>/dev/null

    if [ $? -ne 0 ]; then
        log_error "Failed to extract colors"
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

    # Extract dominant colors from image using ImageMagick
    # This doesn't depend on pywal's JSON output format
    local temp_py=$(mktemp)
    cat > "$temp_py" << 'PYTHON_SCRIPT'
import subprocess
import sys
import os
from collections import Counter

try:
    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not image_path:
        print("Error: Image path required", file=sys.stderr)
        sys.exit(1)

    # Use ImageMagick to extract 10 dominant colors
    try:
        result = subprocess.run(
            ['convert', image_path, '-resize', '100x100', '-colors', '10',
             '-depth', '8', '-format', '%c', 'histogram:info:-'],
            capture_output=True, text=True, timeout=10
        )
        output = result.stdout
    except:
        # Fallback to magick if convert is deprecated
        result = subprocess.run(
            ['magick', image_path, '-resize', '100x100', '-colors', '10',
             '-depth', '8', '-format', '%c', 'histogram:info:-'],
            capture_output=True, text=True, timeout=10
        )
        output = result.stdout

    # Parse histogram output and extract hex colors
    colors_hex = []
    for line in output.split('\n'):
        line = line.strip()
        if not line:
            continue
        # Extract hex color (format: "count: (r,g,b) #HEXCOLOR")
        if '#' in line:
            try:
                hex_color = '#' + line.split('#')[1].split()[0]
                if len(hex_color) == 7:  # Valid hex color
                    colors_hex.append(hex_color)
            except:
                pass

    if len(colors_hex) < 8:
        # Fallback to hardcoded defaults if extraction fails
        print("WARNING: Using default color palette", file=sys.stderr)
        colors_hex = ['#1e1e2e', '#89b4fa', '#94e2d5', '#f5c2e7',
                      '#f38ba8', '#a6e3a1', '#f9e2af', '#cdd6f4']

    # Helper functions
    def hex_to_rgb(hex_color):
        hex_color = hex_color.lstrip('#')
        return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

    def rgb_to_hex(rgb):
        return '#{:02x}{:02x}{:02x}'.format(int(rgb[0]), int(rgb[1]), int(rgb[2]))

    def lighten(hex_color, factor=0.15):
        rgb = hex_to_rgb(hex_color)
        rgb = tuple(min(255, int(c + 255 * factor)) for c in rgb)
        return rgb_to_hex(rgb)

    def darken(hex_color, factor=0.15):
        rgb = hex_to_rgb(hex_color)
        rgb = tuple(max(0, int(c - 255 * factor)) for c in rgb)
        return rgb_to_hex(rgb)

    def get_luminance(hex_color):
        rgb = hex_to_rgb(hex_color)
        # Calculate relative luminance
        return (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255

    # Assign colors based on brightness/hue
    colors_hex = list(dict.fromkeys(colors_hex))  # Remove duplicates, keep order
    colors_hex = sorted(colors_hex, key=lambda x: (get_luminance(x), x))

    # Use the darkest color as background
    bg = colors_hex[0]
    # Use the lightest as text
    text = colors_hex[-1]
    # Ensure good contrast
    if get_luminance(bg) > 0.5:
        bg = '#1e1e2e'  # Fallback to dark
    if get_luminance(text) < 0.5:
        text = '#cdd6f4'  # Fallback to light

    # Assign other colors from the palette
    primary = colors_hex[min(3, len(colors_hex)-1)]    # Blue-ish
    secondary = colors_hex[min(4, len(colors_hex)-1)]  # Cyan-ish
    accent = colors_hex[min(5, len(colors_hex)-1)]     # Magenta-ish
    error = '#f38ba8'    # Red (fixed)
    success = '#a6e3a1'  # Green (fixed)
    warning = '#f9e2af'  # Yellow (fixed)

    # Helper function to convert hex to rgba hex format (with full opacity)
    def hex_to_rgba_hex(hex_color):
        hex_color = hex_color.lstrip('#').upper()
        return f"{hex_color}ff"

    # Output color definitions (hex format)
    print(f"PRIMARY={primary}")
    print(f"SECONDARY={secondary}")
    print(f"ACCENT={accent}")
    print(f"BG={bg}")
    print(f"TEXT={text}")
    print(f"ERROR={error}")
    print(f"SUCCESS={success}")
    print(f"WARNING={warning}")
    print(f"BG_LIGHT={lighten(bg)}")
    print(f"BG_DARK={darken(bg)}")

    # Output rgba hex format for use in Hyprland
    print(f"ACCENT_RGBA='{hex_to_rgba_hex(accent)}'")
    print(f"BG_LIGHT_RGBA='{hex_to_rgba_hex(lighten(bg))}'")
    print(f"BG_DARK_RGBA='{hex_to_rgba_hex(darken(bg))}'")

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT

    # Run extraction script
    local palette=$(python3 "$temp_py" "$image_path" 2>&1)
    local result=$?

    rm -f "$temp_py"

    if [ $result -ne 0 ]; then
        log_error "Failed to extract colors from image"
        return 1
    fi

    # Write to colors.env
    cat > "$colors_file" << EOF
# Color palette - auto-generated by hyprstyle
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Source image: $image_path

# Semantic colors
$palette

# Export for use in other scripts and templates
export PRIMARY SECONDARY ACCENT BG TEXT ERROR SUCCESS WARNING BG_LIGHT BG_DARK
export ACCENT_RGBA BG_LIGHT_RGBA BG_DARK_RGBA
EOF

    log_info "Color palette created successfully"
    return 0
}
