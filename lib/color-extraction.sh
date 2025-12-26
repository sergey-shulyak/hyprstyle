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
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
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

    def create_light_bg(bg_color, text_color):
        # Create a light background color that has good contrast with dark background
        # Use a color between background and text that's much lighter than background
        bg_lum = get_luminance(bg_color)
        text_lum = get_luminance(text_color)

        # If background is dark (low luminance), create a light gray/text-based light color
        if bg_lum < 0.3:
            # Return a light gray that contrasts well with dark bg
            # Aim for at least 4:1 contrast
            return '#a0a0a0' if text_lum > 0.5 else '#c0c0c0'
        else:
            # If background is light, darken it
            return darken(bg_color, 0.25)

    def get_luminance(hex_color):
        rgb = hex_to_rgb(hex_color)
        # WCAG 2.0 relative luminance formula
        def adjust_channel(c):
            c = c / 255.0
            if c <= 0.03928:
                return c / 12.92
            else:
                return ((c + 0.055) / 1.055) ** 2.4
        r = adjust_channel(rgb[0])
        g = adjust_channel(rgb[1])
        b = adjust_channel(rgb[2])
        return 0.2126 * r + 0.7152 * g + 0.0722 * b

    def get_contrast_ratio(color1, color2):
        # Calculate WCAG contrast ratio between two colors
        l1 = get_luminance(color1)
        l2 = get_luminance(color2)
        lighter = max(l1, l2)
        darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)

    def ensure_contrast(bg_color, text_color, min_ratio=4.5):
        # Ensure minimum contrast ratio of 4.5:1 (AA standard)
        if get_contrast_ratio(bg_color, text_color) >= min_ratio:
            return bg_color, text_color

        # If contrast is insufficient, adjust text color
        bg_luminance = get_luminance(bg_color)
        if bg_luminance > 0.5:
            # Dark background, use light text
            return bg_color, '#f0f0f0'
        else:
            # Light background, use dark text
            return bg_color, '#1a1a1a'

    # Assign colors based on brightness/hue
    colors_hex = list(dict.fromkeys(colors_hex))  # Remove duplicates, keep order
    colors_hex = sorted(colors_hex, key=lambda x: get_luminance(x))

    # Use the darkest color as background
    bg = colors_hex[0]
    # Use the lightest as text
    text = colors_hex[-1]

    # Ensure good contrast with WCAG standards
    if get_luminance(bg) > 0.5:
        bg = '#1e1e2e'  # Fallback to dark

    # Ensure text has proper contrast with background
    bg, text = ensure_contrast(bg, text, min_ratio=4.5)

    # Assign other colors from the palette
    # Use colors that are far from background in luminance for better contrast
    primary = colors_hex[min(3, len(colors_hex)-1)]
    secondary = colors_hex[min(4, len(colors_hex)-1)]
    accent = colors_hex[min(5, len(colors_hex)-1)]

    # Ensure semantic colors have good contrast with background (min 3:1 for UI)
    if get_contrast_ratio(bg, primary) < 3:
        primary = text
    if get_contrast_ratio(bg, secondary) < 3:
        secondary = text
    if get_contrast_ratio(bg, accent) < 3:
        accent = text

    # Use fixed semantic colors, but ensure they have good contrast
    error = '#f38ba8'    # Red
    success = '#a6e3a1'  # Green
    warning = '#f9e2af'  # Yellow

    # Ensure error, success, warning have good contrast with background (min 3:1)
    if get_contrast_ratio(bg, error) < 3:
        error = '#ff6b9d'  # Brighter red
    if get_contrast_ratio(bg, success) < 3:
        success = '#5ff87f'  # Brighter green
    if get_contrast_ratio(bg, warning) < 3:
        warning = '#ffd93d'  # Brighter yellow

    # Helper function to convert hex to rgba hex format (with full opacity)
    def hex_to_rgba_hex(hex_color):
        hex_color = hex_color.lstrip('#').upper()
        return f"{hex_color}ff"

    # Generate BG_LIGHT with proper contrast
    bg_light = create_light_bg(bg, text)

    # Generate CURSORLINE color with good contrast to text for UI elements
    # This is used for line highlighting and should be very subtle, almost imperceptible
    def create_cursorline_bg(bg_color, text_color, primary_color):
        # For cursorline, use a color that's:
        # 1. Very subtle and non-intrusive
        # 2. Has good contrast with text for readability
        # 3. Doesn't conflict with syntax highlighting
        bg_lum = get_luminance(bg_color)
        text_lum = get_luminance(text_color)

        # If text is very light (light theme or light text on dark bg),
        # use an extremely subtle darkened primary for cursorline
        if text_lum > 0.6:
            # Text is light, so use an extremely subtle highlight
            # Darken the primary color very significantly for extreme subtlety
            primary_lum = get_luminance(primary_color)
            if primary_lum > 0.5:
                # Primary is light, darken it very significantly for extreme subtlety
                return darken(primary_color, 0.45)
            else:
                # Primary is dark, just barely lighten it
                return lighten(primary_color, 0.02)
        else:
            # Text is dark, use an extremely subtle highlight
            return lighten(bg_color, 0.02)

    cursorline = create_cursorline_bg(bg, text, primary)

    # Output color definitions (hex format)
    print(f"PRIMARY={primary}")
    print(f"SECONDARY={secondary}")
    print(f"ACCENT={accent}")
    print(f"BG={bg}")
    print(f"TEXT={text}")
    print(f"ERROR={error}")
    print(f"SUCCESS={success}")
    print(f"WARNING={warning}")
    print(f"BG_LIGHT={bg_light}")
    print(f"BG_DARK={darken(bg)}")
    print(f"CURSORLINE={cursorline}")

    # Output rgba hex format for use in Hyprland
    print(f"PRIMARY_RGBA='{hex_to_rgba_hex(primary)}'")
    print(f"SECONDARY_RGBA='{hex_to_rgba_hex(secondary)}'")
    print(f"ACCENT_RGBA='{hex_to_rgba_hex(accent)}'")
    print(f"BG_LIGHT_RGBA='{hex_to_rgba_hex(lighten(bg))}'")
    print(f"BG_DARK_RGBA='{hex_to_rgba_hex(darken(bg))}'")

    # Output RGB format for use in CSS (without alpha channel)
    def hex_to_rgb_str(hex_color):
        hex_color = hex_color.lstrip('#')
        r = int(hex_color[0:2], 16)
        g = int(hex_color[2:4], 16)
        b = int(hex_color[4:6], 16)
        return f"{r}, {g}, {b}"

    # Generate button background - slightly lighter than background for contrast
    button_bg = lighten(bg, 0.05)

    print(f"BG_LIGHT_RGB='{hex_to_rgb_str(bg_light)}'")
    print(f"BUTTON_BG='{button_bg}'")
    print(f"BUTTON_BG_RGB='{hex_to_rgb_str(button_bg)}'")
    print(f"ACCENT_RGB='{hex_to_rgb_str(accent)}'")

    # RGB format for hyprlock colors (without alpha, without # prefix)
    print(f"TEXT_RGB='{hex_to_rgb_str(text)}'")
    print(f"ERROR_RGB='{hex_to_rgb_str(error)}'")
    print(f"SUCCESS_RGB='{hex_to_rgb_str(success)}'")
    print(f"WARNING_RGB='{hex_to_rgb_str(warning)}'")

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
export PRIMARY SECONDARY ACCENT BG TEXT ERROR SUCCESS WARNING BG_LIGHT BG_DARK CURSORLINE BUTTON_BG
export PRIMARY_RGBA SECONDARY_RGBA ACCENT_RGBA BG_LIGHT_RGBA BG_DARK_RGBA BG_LIGHT_RGB BUTTON_BG_RGB ACCENT_RGB
export TEXT_RGB ERROR_RGB SUCCESS_RGB WARNING_RGB
EOF

    log_info "Color palette created successfully"
    return 0
}
