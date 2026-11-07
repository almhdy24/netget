#!/usr/bin/env python3
"""
NetGet Brand Asset Renderer
Renders master SVG assets to high-quality PNGs using rsvg-convert (cairo/pango engine).
Generates store icons, Android launcher mipmaps, and splash screen artwork.
"""

import os
import subprocess
import sys
from PIL import Image

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BRANDING_DIR = os.path.join(PROJECT_ROOT, 'assets', 'branding')
RES_DIR = os.path.join(PROJECT_ROOT, 'android', 'app', 'src', 'main', 'res')

def render_svg(svg_path: str, png_path: str, width: int, height: int):
    os.makedirs(os.path.dirname(png_path), exist_ok=True)
    cmd = [
        'rsvg-convert',
        '-w', str(width),
        '-h', str(height),
        svg_path,
        '-o', png_path
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error rendering {svg_path} -> {png_path}: {res.stderr}")
        sys.exit(1)
    
    # Verify with PIL
    img = Image.open(png_path)
    assert img.size == (width, height), f"Expected size {(width, height)}, got {img.size}"
    print(f"✓ Generated {os.path.relpath(png_path, PROJECT_ROOT)}: {img.size[0]}x{img.size[1]} ({os.path.getsize(png_path)} bytes)")

def main():
    icon_svg = os.path.join(BRANDING_DIR, 'netget_icon.svg')
    splash_svg = os.path.join(BRANDING_DIR, 'netget_splash.svg')
    logo_svg = os.path.join(BRANDING_DIR, 'netget_logo.svg')
    wordmark_svg = os.path.join(BRANDING_DIR, 'netget_wordmark.svg')

    assert os.path.exists(icon_svg), f"Missing {icon_svg}"
    assert os.path.exists(splash_svg), f"Missing {splash_svg}"
    assert os.path.exists(logo_svg), f"Missing {logo_svg}"
    assert os.path.exists(wordmark_svg), f"Missing {wordmark_svg}"

    print("=== Rendering Brand Master Assets ===")
    # 1. Master Icon (1024x1024)
    render_svg(icon_svg, os.path.join(BRANDING_DIR, 'netget_master_icon_1024.png'), 1024, 1024)

    # 2. Store Icons (512x512)
    render_svg(icon_svg, os.path.join(BRANDING_DIR, 'netget_store_icon_512.png'), 512, 512)
    render_svg(icon_svg, os.path.join(PROJECT_ROOT, 'tool', 'store_icon_512.png'), 512, 512)

    # 3. Logo and Wordmark PNGs
    render_svg(logo_svg, os.path.join(BRANDING_DIR, 'netget_logo.png'), 1120, 280)
    render_svg(wordmark_svg, os.path.join(BRANDING_DIR, 'netget_wordmark.png'), 680, 180)

    # 4. Splash Screen Artwork
    render_svg(splash_svg, os.path.join(BRANDING_DIR, 'splash_logo.png'), 480, 480)

    print("\n=== Rendering Android Launcher Mipmaps ===")
    mipmap_configs = [
        ('mipmap-mdpi', 48),
        ('mipmap-hdpi', 72),
        ('mipmap-xhdpi', 96),
        ('mipmap-xxhdpi', 144),
        ('mipmap-xxxhdpi', 192),
    ]
    for folder, size in mipmap_configs:
        dest = os.path.join(RES_DIR, folder, 'ic_launcher.png')
        render_svg(icon_svg, dest, size, size)

    print("\n=== Rendering Android Splash Drawables ===")
    splash_configs = [
        ('drawable', 360),
        ('drawable-hdpi', 240),
        ('drawable-xhdpi', 320),
        ('drawable-xxhdpi', 480),
        ('drawable-xxxhdpi', 640),
    ]
    for folder, size in splash_configs:
        dest = os.path.join(RES_DIR, folder, 'splash_logo.png')
        render_svg(splash_svg, dest, size, size)

    print("\nAll brand assets successfully generated from SVG master artwork!")

if __name__ == '__main__':
    main()
