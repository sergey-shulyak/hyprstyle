#!/bin/bash
#
# Color Extraction Library
# Extracts colors from images using pywal and generates color palette
#

set -e

# Colors for output
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
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

    def brighten(hex_color, factor=0.25):
        """Create a brighter, more saturated variant for ANSI bright colors.

        Smart brightening that avoids over-saturation and handles already-bright colors.
        """
        import colorsys
        rgb = hex_to_rgb(hex_color)
        r, g, b = rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0
        h, l, s = colorsys.rgb_to_hls(r, g, b)

        # Adaptive brightening based on current lightness
        if l > 0.7:
            # Already bright - use smaller factor to avoid washing out
            l = min(0.9, l + factor * 0.3)
        elif l > 0.5:
            # Medium brightness - moderate increase
            l = min(0.85, l + factor * 0.5)
        else:
            # Dark color - full brightening
            l = min(0.8, l + factor)

        # Boost saturation but cap it to avoid neon colors
        if s < 0.3:
            # Low saturation (grayish) - boost more
            s = min(0.5, s + 0.2)
        elif s < 0.7:
            # Medium saturation - moderate boost
            s = min(0.8, s + 0.1)
        # High saturation - leave as is to avoid over-saturation

        r, g, b = colorsys.hls_to_rgb(h, l, s)
        return rgb_to_hex((r * 255, g * 255, b * 255))

    def get_hue(hex_color):
        """Get the hue (0-360) of a color."""
        import colorsys
        rgb = hex_to_rgb(hex_color)
        r, g, b = rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        return h * 360  # Convert to degrees

    def get_saturation(hex_color):
        """Get the saturation (0-1) of a color."""
        import colorsys
        rgb = hex_to_rgb(hex_color)
        r, g, b = rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        return s

    def rotate_hue(hex_color, degrees):
        """Rotate the hue of a color by given degrees."""
        import colorsys
        rgb = hex_to_rgb(hex_color)
        r, g, b = rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        h = (h + degrees / 360.0) % 1.0
        r, g, b = colorsys.hls_to_rgb(h, l, s)
        return rgb_to_hex((r * 255, g * 255, b * 255))

    def set_hue(hex_color, target_hue_deg):
        """Set the hue of a color to a specific value (0-360 degrees)."""
        import colorsys
        rgb = hex_to_rgb(hex_color)
        r, g, b = rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        h = target_hue_deg / 360.0
        # Ensure reasonable saturation for chromatic colors
        s = max(s, 0.4) if s > 0.1 else 0.5
        r, g, b = colorsys.hls_to_rgb(h, l, s)
        return rgb_to_hex((r * 255, g * 255, b * 255))

    def classify_hue(hue_deg):
        """Classify a hue into ANSI color categories.

        Returns: 'red', 'yellow', 'green', 'cyan', 'blue', 'magenta', or 'neutral'
        """
        # Normalize to 0-360
        hue = hue_deg % 360

        # ANSI color hue ranges (approximate)
        if hue < 15 or hue >= 345:
            return 'red'
        elif 15 <= hue < 45:
            return 'orange'  # Will map to yellow or red
        elif 45 <= hue < 75:
            return 'yellow'
        elif 75 <= hue < 150:
            return 'green'
        elif 150 <= hue < 195:
            return 'cyan'
        elif 195 <= hue < 270:
            return 'blue'
        elif 270 <= hue < 345:
            return 'magenta'
        return 'neutral'

    def find_best_color_for_hue(colors, target_hue_category, bg_color, min_saturation=0.2):
        """Find the best color from palette matching a target hue category."""
        candidates = []
        for color in colors:
            sat = get_saturation(color)
            if sat < min_saturation:
                continue  # Skip grayish colors
            hue = get_hue(color)
            category = classify_hue(hue)
            if category == target_hue_category:
                contrast = get_contrast_ratio(bg_color, color)
                candidates.append((color, contrast, sat))
            # Map orange to either yellow or red based on context
            elif target_hue_category == 'yellow' and category == 'orange':
                contrast = get_contrast_ratio(bg_color, color)
                candidates.append((color, contrast * 0.8, sat))  # Slight penalty
            elif target_hue_category == 'red' and category == 'orange':
                contrast = get_contrast_ratio(bg_color, color)
                candidates.append((color, contrast * 0.9, sat))

        if candidates:
            # Sort by contrast (higher is better) then saturation
            candidates.sort(key=lambda x: (x[1], x[2]), reverse=True)
            return candidates[0][0]
        return None

    def generate_missing_color(base_color, target_hue_deg, bg_color):
        """Generate a color with target hue based on palette characteristics."""
        import colorsys
        rgb = hex_to_rgb(base_color)
        r, g, b = rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0
        h, l, s = colorsys.rgb_to_hls(r, g, b)

        # Use target hue but preserve palette's lightness/saturation style
        new_h = target_hue_deg / 360.0
        # Ensure good saturation for chromatic colors
        new_s = max(s, 0.5) if s > 0.15 else 0.6
        # Ensure good lightness for visibility
        new_l = l if 0.3 <= l <= 0.7 else 0.5

        r, g, b = colorsys.hls_to_rgb(new_h, new_l, new_s)
        result = rgb_to_hex((r * 255, g * 255, b * 255))

        # Ensure contrast with background
        if get_contrast_ratio(bg_color, result) < 3:
            # Adjust lightness for better contrast
            bg_lum = get_luminance(bg_color)
            if bg_lum < 0.5:
                new_l = min(0.8, new_l + 0.2)
            else:
                new_l = max(0.3, new_l - 0.2)
            r, g, b = colorsys.hls_to_rgb(new_h, new_l, new_s)
            result = rgb_to_hex((r * 255, g * 255, b * 255))

        return result

    # Target hues for ANSI colors (in degrees)
    ANSI_HUES = {
        'red': 0,
        'yellow': 60,
        'green': 120,
        'cyan': 180,
        'blue': 220,
        'magenta': 300
    }

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

    # Assign colors based on hue analysis
    colors_hex = list(dict.fromkeys(colors_hex))  # Remove duplicates, keep order
    colors_by_luminance = sorted(colors_hex, key=lambda x: get_luminance(x))

    # Use the darkest color as background
    bg = colors_by_luminance[0]
    # Use the lightest as text
    text = colors_by_luminance[-1]

    # Ensure good contrast with WCAG standards
    if get_luminance(bg) > 0.5:
        bg = '#1e1e2e'  # Fallback to dark

    # Ensure text has proper contrast with background
    bg, text = ensure_contrast(bg, text, min_ratio=4.5)

    # Find a representative chromatic color for generating missing hues
    # Prefer saturated colors from the middle of the luminance range
    chromatic_colors = [c for c in colors_hex if get_saturation(c) > 0.2]
    base_chromatic = chromatic_colors[len(chromatic_colors)//2] if chromatic_colors else colors_by_luminance[len(colors_by_luminance)//2]

    # === HUE-BASED ANSI COLOR ASSIGNMENT ===
    # Find or generate colors for each ANSI hue category

    # RED (ANSI 1/9) - Used for errors
    error = find_best_color_for_hue(colors_hex, 'red', bg)
    if not error:
        error = generate_missing_color(base_chromatic, ANSI_HUES['red'], bg)

    # GREEN (ANSI 2/10) - Used for success
    success = find_best_color_for_hue(colors_hex, 'green', bg)
    if not success:
        success = generate_missing_color(base_chromatic, ANSI_HUES['green'], bg)

    # YELLOW (ANSI 3/11) - Used for warnings
    warning = find_best_color_for_hue(colors_hex, 'yellow', bg)
    if not warning:
        warning = generate_missing_color(base_chromatic, ANSI_HUES['yellow'], bg)

    # BLUE (ANSI 4/12) - Primary accent
    primary = find_best_color_for_hue(colors_hex, 'blue', bg)
    if not primary:
        primary = generate_missing_color(base_chromatic, ANSI_HUES['blue'], bg)

    # MAGENTA (ANSI 5/13) - Accent color
    accent = find_best_color_for_hue(colors_hex, 'magenta', bg)
    if not accent:
        accent = generate_missing_color(base_chromatic, ANSI_HUES['magenta'], bg)

    # CYAN (ANSI 6/14) - Secondary accent
    secondary = find_best_color_for_hue(colors_hex, 'cyan', bg)
    if not secondary:
        secondary = generate_missing_color(base_chromatic, ANSI_HUES['cyan'], bg)

    # Ensure all semantic colors have good contrast with background (min 3:1 for UI)
    def ensure_ui_contrast(color, bg_color, target_hue, min_ratio=3.0):
        """Ensure color has adequate contrast, adjusting if needed."""
        if get_contrast_ratio(bg_color, color) >= min_ratio:
            return color
        # Regenerate with better contrast
        return generate_missing_color(color, target_hue, bg_color)

    error = ensure_ui_contrast(error, bg, ANSI_HUES['red'])
    success = ensure_ui_contrast(success, bg, ANSI_HUES['green'])
    warning = ensure_ui_contrast(warning, bg, ANSI_HUES['yellow'])
    primary = ensure_ui_contrast(primary, bg, ANSI_HUES['blue'])
    accent = ensure_ui_contrast(accent, bg, ANSI_HUES['magenta'])
    secondary = ensure_ui_contrast(secondary, bg, ANSI_HUES['cyan'])

    # === UI_ACCENT: Dominant color from image for UI elements ===
    # This is separate from ANSI colors - it's the most vibrant/prominent
    # color from the actual wallpaper, used for borders, buttons, highlights
    def find_ui_accent(colors, bg_color, min_saturation=0.25):
        """Find the most vibrant, high-contrast color from the palette for UI use."""
        candidates = []
        for color in colors:
            sat = get_saturation(color)
            lum = get_luminance(color)
            bg_lum = get_luminance(bg_color)

            # Skip colors too close to background
            if abs(lum - bg_lum) < 0.15:
                continue
            # Skip very desaturated colors
            if sat < min_saturation:
                continue

            contrast = get_contrast_ratio(bg_color, color)
            # Score based on saturation and contrast
            score = sat * 0.6 + (contrast / 10) * 0.4
            candidates.append((color, score, sat, contrast))

        if candidates:
            # Sort by score (higher is better)
            candidates.sort(key=lambda x: x[1], reverse=True)
            best = candidates[0]
            # Ensure minimum contrast of 3:1 for UI elements
            if best[3] >= 3:
                return best[0]
            # If best candidate lacks contrast, try to find one with better contrast
            for c in candidates:
                if c[3] >= 3:
                    return c[0]

        # Fallback: use the most saturated ANSI color that came from the image
        # Check which ANSI colors actually matched image colors vs were generated
        return None

    ui_accent = find_ui_accent(colors_hex, bg)

    # If no good UI accent found from image, pick from our assigned colors
    # Prefer colors that are likely from the image (have matching hues in palette)
    if not ui_accent:
        # Check which of our ANSI colors has a matching hue in the original palette
        for ansi_color in [error, warning, accent, primary, secondary, success]:
            ansi_hue = classify_hue(get_hue(ansi_color))
            for img_color in colors_hex:
                if get_saturation(img_color) > 0.2:
                    if classify_hue(get_hue(img_color)) == ansi_hue:
                        if get_contrast_ratio(bg, ansi_color) >= 3:
                            ui_accent = ansi_color
                            break
            if ui_accent:
                break

    # Final fallback: use the text color
    if not ui_accent:
        ui_accent = text

    # Also create a bright variant of UI_ACCENT for hover states etc.
    ui_accent_bright = brighten(ui_accent)
    if get_contrast_ratio(bg, ui_accent_bright) < 3:
        ui_accent_bright = lighten(ui_accent, 0.2)

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

    # UI accent colors - dominant color from image for borders, buttons, highlights
    print(f"UI_ACCENT={ui_accent}")
    print(f"UI_ACCENT_BRIGHT={ui_accent_bright}")

    # Generate bright variants for ANSI colors 8-15
    # These are more saturated and lighter versions of the base colors
    # With contrast validation to ensure readability

    def ensure_bright_contrast(bright_color, bg_color, base_color, target_hue, min_ratio=3.5):
        """Ensure bright color variant has good contrast with background."""
        if get_contrast_ratio(bg_color, bright_color) >= min_ratio:
            return bright_color
        # Try brightening more aggressively
        import colorsys
        rgb = hex_to_rgb(bright_color)
        r, g, b = rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        # Push lightness higher for dark backgrounds
        bg_lum = get_luminance(bg_color)
        if bg_lum < 0.5:
            l = min(0.9, l + 0.15)
        else:
            l = max(0.2, l - 0.15)
        r, g, b = colorsys.hls_to_rgb(h, l, s)
        return rgb_to_hex((r * 255, g * 255, b * 255))

    error_bright = ensure_bright_contrast(brighten(error), bg, error, ANSI_HUES['red'])
    success_bright = ensure_bright_contrast(brighten(success), bg, success, ANSI_HUES['green'])
    warning_bright = ensure_bright_contrast(brighten(warning), bg, warning, ANSI_HUES['yellow'])
    primary_bright = ensure_bright_contrast(brighten(primary), bg, primary, ANSI_HUES['blue'])
    accent_bright = ensure_bright_contrast(brighten(accent), bg, accent, ANSI_HUES['magenta'])
    secondary_bright = ensure_bright_contrast(brighten(secondary), bg, secondary, ANSI_HUES['cyan'])

    print(f"ERROR_BRIGHT={error_bright}")
    print(f"SUCCESS_BRIGHT={success_bright}")
    print(f"WARNING_BRIGHT={warning_bright}")
    print(f"PRIMARY_BRIGHT={primary_bright}")
    print(f"ACCENT_BRIGHT={accent_bright}")
    print(f"SECONDARY_BRIGHT={secondary_bright}")

    # ANSI color 7 (white) should be a dim white, not full text brightness
    # ANSI color 15 (bright white) is the full text color
    # Ensure WHITE_DIM has good contrast with both BG and TEXT
    bg_lum = get_luminance(bg)
    if bg_lum < 0.3:
        # Dark background - use a medium gray that contrasts with both
        white_dim = '#a0a0a0'
        # Ensure it contrasts with background (min 3:1)
        if get_contrast_ratio(bg, white_dim) < 3:
            white_dim = '#b0b0b0'
    else:
        # Light background - use darker gray
        white_dim = darken(text, 0.35)

    print(f"WHITE_DIM={white_dim}")

    # Output rgba hex format for use in Hyprland
    print(f"PRIMARY_RGBA='{hex_to_rgba_hex(primary)}'")
    print(f"SECONDARY_RGBA='{hex_to_rgba_hex(secondary)}'")
    print(f"ACCENT_RGBA='{hex_to_rgba_hex(accent)}'")
    print(f"BG_LIGHT_RGBA='{hex_to_rgba_hex(lighten(bg))}'")
    print(f"BG_DARK_RGBA='{hex_to_rgba_hex(darken(bg))}'")
    print(f"UI_ACCENT_RGBA='{hex_to_rgba_hex(ui_accent)}'")

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
    print(f"UI_ACCENT_RGB='{hex_to_rgb_str(ui_accent)}'")

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
# Bright variants for ANSI 16-color terminal support
export ERROR_BRIGHT SUCCESS_BRIGHT WARNING_BRIGHT PRIMARY_BRIGHT ACCENT_BRIGHT SECONDARY_BRIGHT WHITE_DIM
# UI accent - dominant color from image for borders, buttons, highlights
export UI_ACCENT UI_ACCENT_BRIGHT UI_ACCENT_RGBA UI_ACCENT_RGB
EOF

    log_info "Color palette created successfully"
    return 0
}
