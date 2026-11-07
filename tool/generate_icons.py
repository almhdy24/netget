#!/usr/bin/env python3
"""
NetGet Icon Generator
Generates Android adaptive vector XML icons (background, foreground, monochrome),
status bar notification icon (ic_stat_download.xml), and PNG fallbacks using pure Python stdlib.
"""

import os
import struct
import zlib

def write_png(file_path: str, width: int, height: int, rgba_bytes: bytes):
    """Write an uncompressed PNG using pure Python stdlib (struct + zlib)."""
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    raw_data = bytearray()
    row_len = width * 4
    for y in range(height):
        raw_data.append(0)  # filter type 0 (None)
        raw_data.extend(rgba_bytes[y * row_len : (y + 1) * row_len])

    png_header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) # 8-bit RGBA
    idat = chunk(b'IDAT', zlib.compress(bytes(raw_data), 9))
    iend = chunk(b'IEND', b'')

    with open(file_path, 'wb') as f:
        f.write(png_header + ihdr + idat + iend)

def render_icon_bitmap(size: int) -> bytes:
    """Render the NetGet icon: near-black indigo background with cyan-to-green downward arrow onto tray."""
    pixels = bytearray(size * size * 4)
    # Colors
    bg_r, bg_g, bg_b = 0x0A, 0x0E, 0x1A  # Near-black indigo (#0A0E1A)
    
    # Arrow and tray geometry normalized 0..1
    cx = size / 2.0
    cy = size / 2.0
    scale = size / 108.0

    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4
            # Background
            pixels[idx] = bg_r
            pixels[idx + 1] = bg_g
            pixels[idx + 2] = bg_b
            pixels[idx + 3] = 255

            nx = x / scale
            ny = y / scale

            # Gradient from cyan (#00E5FF, 0, 229, 255) to green (#00E676, 0, 230, 118)
            t = (ny - 20) / 68.0
            t = max(0.0, min(1.0, t))
            fg_r = 0
            fg_g = int(229 + (230 - 229) * t)
            fg_b = int(255 + (118 - 255) * t)

            # Draw Shaft: x in [48, 60], y in [24, 56]
            in_shaft = (48 <= nx <= 60) and (24 <= ny <= 56)
            
            # Draw Arrow Head: triangle pointing down from y=56 to y=72, x between 36 and 72
            # ny in [56, 72], width shrinks as ny increases
            in_head = False
            if 56 <= ny <= 72:
                half_w = (72 - ny) * 1.125
                if (54 - half_w) <= nx <= (54 + half_w):
                    in_head = True

            # Draw Tray: horizontal bar at bottom with turned-up ends
            # bar: x in [32, 76], y in [78, 86]
            # left ear: x in [32, 40], y in [68, 86]
            # right ear: x in [68, 76], y in [68, 86]
            in_tray_base = (32 <= nx <= 76) and (78 <= ny <= 86)
            in_tray_left = (32 <= nx <= 40) and (68 <= ny <= 86)
            in_tray_right = (68 <= nx <= 76) and (68 <= ny <= 86)
            in_tray = in_tray_base or in_tray_left or in_tray_right

            if in_shaft or in_head or in_tray:
                pixels[idx] = fg_r
                pixels[idx + 1] = fg_g
                pixels[idx + 2] = fg_b
                pixels[idx + 3] = 255

    return bytes(pixels)

def main():
    base_res = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')
    drawable_dir = os.path.join(base_res, 'drawable')
    drawable_v26_dir = os.path.join(base_res, 'drawable-v26')
    os.makedirs(drawable_dir, exist_ok=True)
    os.makedirs(drawable_v26_dir, exist_ok=True)

    # 1. Background Vector XML (Near-black indigo)
    bg_xml = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#0A0E1A"
        android:pathData="M0,0h108v108h-108z"/>
</vector>
"""
    with open(os.path.join(drawable_dir, 'ic_launcher_background.xml'), 'w') as f:
        f.write(bg_xml)

    # 2. Foreground Vector XML (Cyan-to-green downward arrow landing on tray)
    fg_xml = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <!-- Arrow Shaft & Head -->
    <path
        android:pathData="M48,24 h12 v32 h12 L54,72 L36,56 h12 Z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:startX="54"
                android:startY="24"
                android:endX="54"
                android:endY="72"
                android:type="linear">
                <item android:offset="0.0" android:color="#00E5FF"/>
                <item android:offset="1.0" android:color="#00E676"/>
            </gradient>
        </aapt:attr>
    </path>
    <!-- Landing Tray -->
    <path
        android:pathData="M32,68 h8 v10 h28 v-10 h8 v18 h-44 Z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:startX="54"
                android:startY="68"
                android:endX="54"
                android:endY="86"
                android:type="linear">
                <item android:offset="0.0" android:color="#00E5FF"/>
                <item android:offset="1.0" android:color="#00E676"/>
            </gradient>
        </aapt:attr>
    </path>
</vector>
"""
    with open(os.path.join(drawable_dir, 'ic_launcher_foreground.xml'), 'w') as f:
        f.write(fg_xml)

    # 3. Monochrome layer for Android 13+ themed icons
    mono_xml = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M48,24 h12 v32 h12 L54,72 L36,56 h12 Z M32,68 h8 v10 h28 v-10 h8 v18 h-44 Z"/>
</vector>
"""
    with open(os.path.join(drawable_dir, 'ic_launcher_monochrome.xml'), 'w') as f:
        f.write(mono_xml)

    # 4. Status Bar Download Icon (White-only monochrome)
    stat_xml = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M11,4 h2 v8 h3 L12,16 L8,12 h3 Z M6,16 h2 v2 h8 v-2 h2 v4 h-12 Z"/>
</vector>
"""
    with open(os.path.join(drawable_dir, 'ic_stat_download.xml'), 'w') as f:
        f.write(stat_xml)

    # 5. Adaptive Icon Definition XML (mipmap-anydpi-v26 / drawable-v26)
    mipmap_v26_dir = os.path.join(base_res, 'mipmap-anydpi-v26')
    os.makedirs(mipmap_v26_dir, exist_ok=True)
    adaptive_xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
"""
    with open(os.path.join(mipmap_v26_dir, 'ic_launcher.xml'), 'w') as f:
        f.write(adaptive_xml)

    # 6. Legacy Mipmap PNG Fallbacks (mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192)
    sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    for folder, px in sizes.items():
        p = os.path.join(base_res, folder, 'ic_launcher.png')
        bm = render_icon_bitmap(px)
        write_png(p, px, px, bm)
        print(f"Rendered legacy PNG {folder}: {px}x{px}")

    # 7. 512x512 Store PNG under tool/
    store_png = os.path.join(os.path.dirname(__file__), 'store_icon_512.png')
    bm512 = render_icon_bitmap(512)
    write_png(store_png, 512, 512, bm512)
    print(f"Rendered 512x512 store icon: {store_png}")

if __name__ == '__main__':
    main()
