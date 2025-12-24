# Hyprstyle - Hyprland Theme Generator

Automatically generate color schemes from images and apply them consistently across all your Wayland applications.

## Overview

Hyprstyle extracts dominant colors from any image and generates a cohesive color palette that is automatically applied to:

- **Hyprland** - Window manager borders and decorations
- **Kitty** - Terminal emulator colors
- **Mako** - Notification daemon
- **Waybar** - Status bar
- **Wofi** - Application launcher

All configurations are backed up before changes, and you can restore previous themes at any time.

## Features

✨ **One-Command Theming**
- Pass an image file, get a fully themed system
- Automatically sets wallpaper and colors across all apps

🔄 **Automatic Backups**
- All changes are backed up with timestamps
- Easy restore to previous configurations

💾 **Palette Persistence**
- Generated color palettes saved as JSON
- Re-apply themes without re-processing images

🎨 **Consistent Colors**
- Extracts dominant colors from images
- Semantic color mapping (primary, accent, error, success, etc.)
- Light/dark variants for depth

🖼️ **Wallpaper Integration**
- Automatically sets the image as system wallpaper
- Works with hyprpaper (optional)
- Falls back gracefully if hyprpaper unavailable

🛡️ **Safe Updates**
- Validates template substitution
- Creates backups before any changes
- Clear error messages

## Installation

### Prerequisites

1. **Python 3** with PIL (included in most distributions)
   ```bash
   # Already installed on Arch
   ```

2. **PyWal** for color extraction
   ```bash
   paru -S python-pywal
   ```

3. **Bash 4.0+** (you have this)

### Setup

1. Clone or create the hyprstyle directory:
   ```bash
   mkdir -p ~/Developer/hyprstyle
   cd ~/Developer/hyprstyle
   ```

2. You already have the structure in place!

## Usage

### Generate Theme from Image

```bash
./hyprstyle.sh ~/Pictures/wallpaper.png
```

This will:
1. Extract colors from the image
2. Generate a color palette
3. **Backup** your current configuration
4. Update all application configs (Hyprland, Kitty, Mako, Waybar, Wofi)
5. Set the image as your wallpaper (via hyprpaper, if available)
6. Save the palette for future use
7. Show the backup location for reference

### Restore Previous Configuration

#### Method 1: Interactive Script (Recommended)

```bash
./restore-backup.sh
```

This will:
1. List all available backups
2. Prompt you to select one
3. Show what files will be restored
4. Ask for confirmation
5. Restore the selected backup

#### Method 2: Command-line

Restore a specific backup directly:
```bash
./restore-backup.sh 2025-12-25_143022
```

Or use the main script:
```bash
./hyprstyle.sh --restore 2025-12-25_143022
```

List available backups:
```bash
./hyprstyle.sh --list
```

### Apply Saved Palette

List saved palettes:
```bash
./hyprstyle.sh --list
```

Apply a palette:
```bash
./hyprstyle.sh --apply-palette wallpaper
```

### View Palette Details

See the exact colors in a palette:
```bash
./hyprstyle.sh --palette-info wallpaper
```

### Help

```bash
./hyprstyle.sh --help
```

## Directory Structure

```
~/Developer/hyprstyle/
├── hyprstyle.sh                    # Main executable for theme generation
├── restore-backup.sh               # Interactive backup restoration script
├── lib/                            # Utility libraries
│   ├── color-extraction.sh         # Color extraction from images
│   ├── config-updater.sh           # Apply colors to configs
│   └── backup-restore.sh           # Backup and restore logic
├── templates/                      # Config templates with placeholders
│   ├── hyprland.colors.conf
│   ├── kitty.conf
│   ├── mako.config
│   ├── waybar.style.css
│   └── wofi.style.css
├── colors.env                      # Generated color variables
├── backups/                        # Timestamped config backups
│   └── 2025-12-25_143022/
│       ├── .config/hypr/hyprland.conf
│       ├── .config/kitty/kitty.conf
│       └── ...
├── palettes/                       # Saved color palettes as JSON
│   └── wallpaper.json
├── .gitignore
└── README.md
```

## Color Palette Structure

Generated palettes use these semantic color names:

- **PRIMARY** - Main accent color (usually blue)
- **SECONDARY** - Secondary accent (usually cyan)
- **ACCENT** - Bright highlight color (usually magenta)
- **BG** - Background color
- **TEXT** - Foreground/text color
- **ERROR** - Error indicators (red)
- **SUCCESS** - Success indicators (green)
- **WARNING** - Warning indicators (yellow)
- **BG_LIGHT** - Lighter variant for depth
- **BG_DARK** - Darker variant for depth

### Palette JSON Format

Saved palettes follow this structure:

```json
{
  "name": "wallpaper",
  "timestamp": "2025-12-25T14:30:22Z",
  "source_image": "/home/user/Pictures/wallpaper.png",
  "colors": {
    "primary": "#89b4fa",
    "secondary": "#94e2d5",
    "accent": "#f5c2e7",
    "background": "#1e1e2e",
    "text": "#cdd6f4",
    "error": "#f38ba8",
    "success": "#a6e3a1",
    "warning": "#f9e2af",
    "bg_light": "#45475a",
    "bg_dark": "#0a0a0f"
  }
}
```

## Application Configuration

### Hyprland

Colors are written to `~/.config/hypr/colors.conf` and sourced in your main `hyprland.conf`:

```bash
source = ~/.config/hypr/colors.conf

general {
    col.active_border = $accent $secondary 45deg
    col.inactive_border = rgba(595959aa)
}
```

### Kitty

Terminal color codes (color0-15) are appended to your `~/.config/kitty/kitty.conf`:

```
foreground #cdd6f4
background #1e1e2e
color0 #0a0a0f
color1 #f38ba8
...
```

### Mako

Notification colors updated in `~/.config/mako/config`:

```
background-color=#1e1e2e80
text-color=#cdd6f4
border-color=#45475a66
```

### Waybar

Stylesheet colors updated in `~/.config/waybar/style.css`:

```css
window {
    background-color: rgba(30, 30, 46, 0.6);
    color: #cdd6f4;
}
```

### Wofi

Launcher colors updated in `~/.config/wofi/style.css`:

```css
window {
    background-color: rgba(30, 30, 46, 0.9);
    border: 2px solid #89b4fa;
}
```

## Workflow Examples

### Basic Daily Use

Generate a new theme from your wallpaper:
```bash
./hyprstyle.sh ~/Pictures/daily-wallpaper.png
# Reload Hyprland (Super+Shift+R)
```

### Multiple Theme Combinations

Create themes for different times of day:
```bash
./hyprstyle.sh ~/Pictures/morning.png      # Morning theme
./hyprstyle.sh ~/Pictures/evening.png      # Evening theme
./hyprstyle.sh ~/Pictures/night.png        # Night theme

# Later, switch themes:
./hyprstyle.sh --apply-palette morning
./hyprstyle.sh --apply-palette evening
```

### Git Integration

Track theme history in your backup repo:
```bash
# After running hyprstyle.sh:
cd ~/Documents/arch-backup
git add -A
git commit -m "Update theme from wallpaper"
git push
```

You can manually copy palettes to arch-backup:
```bash
cp ~/Developer/hyprstyle/palettes/*.json ~/Documents/arch-backup/palettes/
```

## Troubleshooting

### Missing PyWal

```
[ERROR] pywal not found. Install with: paru -S python-pywal
```

Install PyWal:
```bash
paru -S python-pywal
```

### Color Extraction Fails

Ensure the image file exists and is readable:
```bash
file ~/Pictures/your-image.png
```

Try with a different image format (JPG, PNG, WebP are all supported).

### No Backups Found

Backups are created in `~/Developer/hyprstyle/backups/` with timestamp directories. Check:
```bash
ls -la ~/Developer/hyprstyle/backups/
```

### Templates Not Found

Verify template files exist:
```bash
ls ~/Developer/hyprstyle/templates/
```

### Configs Not Updating

Check that you have write permissions:
```bash
ls -la ~/.config/hypr/
ls -la ~/.config/kitty/
```

## Advanced Usage

### Manual Palette Creation

Create a custom palette JSON manually:

```json
{
  "name": "my-custom-theme",
  "timestamp": "2025-12-25T14:30:22Z",
  "source_image": "custom",
  "colors": {
    "primary": "#your-color",
    "secondary": "#your-color",
    ...
  }
}
```

Save to `~/Developer/hyprstyle/palettes/my-custom-theme.json`

Then apply:
```bash
./hyprstyle.sh --apply-palette my-custom-theme
```

### Customizing Templates

Edit templates in `~/Developer/hyprstyle/templates/` to add more color variables or adjust the format:

```bash
# Example: Add a new placeholder
# In template file:
# some_setting = ${NEW_COLOR}

# Then use in hyprstyle:
# The substitution will work automatically
```

## File Changes on Update

When you run `hyprstyle.sh`, these files are modified:

| File | Modified | Backed Up |
|------|----------|-----------|
| `~/.config/hypr/colors.conf` | ✓ Created | ✓ |
| `~/.config/hypr/hyprland.conf` | Source added once | ✓ |
| `~/.config/kitty/kitty.conf` | Color section updated | ✓ |
| `~/.config/mako/config` | Colors updated | ✓ |
| `~/.config/waybar/style.css` | CSS replaced | ✓ |
| `~/.config/wofi/style.css` | CSS replaced | ✓ |

All backups are kept, so you can restore any previous configuration.

## Tips & Best Practices

1. **Use High-Quality Images** - Better images = better color extraction
2. **Dark Wallpapers Work Best** - Lighter wallpapers may produce less contrast
3. **Test Before Committing** - Apply a theme, reload Hyprland, then commit if happy
4. **Keep Multiple Palettes** - Save multiple palettes for different moods/seasons
5. **Backup Regularly** - The tool creates automatic backups, but also commit to git
6. **Consistent Naming** - Name palettes descriptively (e.g., `autumn-forest` vs `theme1`)

## Limitations

- **Neovim** not included (uses plugin-based themes, works independently)
- **Color extraction quality** depends on image quality
- **WCAG Contrast** not automatically enforced (you should visually verify)

## Contributing

To modify or extend hyprstyle:

1. Edit templates in `templates/` for app-specific colors
2. Edit library files in `lib/` for functionality
3. Edit `hyprstyle.sh` for new commands
4. Test thoroughly before committing

## License

Part of your personal Arch Linux configuration backup system.

---

**Quick Start:**
```bash
cd ~/Developer/hyprstyle

# Generate a new theme from an image
./hyprstyle.sh ~/Pictures/your-wallpaper.png
# Reload Hyprland (Super+Shift+R)

# Later, restore a previous theme:
./restore-backup.sh
# Select from list, confirm, done!
```
