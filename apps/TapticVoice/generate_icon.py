#!/usr/bin/env python3
"""
Generate professional macOS AppIcon for TapticVoice
"""

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUTPUT_DIR = Path(__file__).resolve().parent / "Assets" / "AppIcon.iconset"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
ICNS_PATH = Path(__file__).resolve().parent / "Assets" / "AppIcon.icns"

def draw_squircle_mask(size, radius):
    """Generate high-quality rounded squircle mask."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size, size], radius=radius, fill=255)
    return mask

def create_base_icon():
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    
    # 1. Base Squircle Shape
    padding = 64
    inner_size = size - 2 * padding
    radius = int(inner_size * 0.22)
    
    # Draw background gradient on a canvas
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    
    # Gradient from Deep Slate/Navy to Dark Obsidian
    for y in range(size):
        ratio = y / size
        r = int(14 + ratio * 8)
        g = int(18 + ratio * 6)
        b = int(32 + ratio * 14)
        bg_draw.line([(0, y), (size, y)], fill=(r, g, b, 255))
        
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    box = [padding, padding, size - padding, size - padding]
    mask_draw.rounded_rectangle(box, radius=radius, fill=255)
    
    # Trackpad Body
    trackpad = Image.composite(bg, Image.new("RGBA", (size, size), (0,0,0,0)), mask)
    draw = ImageDraw.Draw(trackpad)
    
    # 2. Outer Glass Bevel & Subtle Highlight
    draw.rounded_rectangle(box, radius=radius, outline=(255, 255, 255, 45), width=4)
    inner_box = [padding + 16, padding + 16, size - padding - 16, size - padding - 16]
    inner_radius = radius - 8
    draw.rounded_rectangle(inner_box, radius=inner_radius, outline=(255, 255, 255, 18), width=2)
    
    # 3. Concentric Acoustic Waves / Resonance Ripples
    cx, cy = size // 2, size // 2
    glow_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    
    radii = [90, 160, 230, 300, 360]
    colors = [
        (139, 92, 246, 210),  # Electric Purple
        (59, 130, 246, 180),  # Cyan / Blue
        (236, 72, 153, 140),  # Pink / Magenta
        (99, 102, 241, 100),  # Indigo
        (56, 189, 248, 60),   # Light Blue
    ]
    
    for r_val, color in zip(radii, colors):
        glow_draw.ellipse(
            [cx - r_val, cy - r_val, cx + r_val, cy + r_val],
            outline=color,
            width=6
        )
    
    # Add bloom / blur to ripples
    glow_blurred = glow_layer.filter(ImageFilter.GaussianBlur(8))
    trackpad = Image.alpha_composite(trackpad, glow_blurred)
    trackpad = Image.alpha_composite(trackpad, glow_layer)
    
    # 4. Neural Waveform Ribbons traversing across
    wave_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    wave_draw = ImageDraw.Draw(wave_layer)
    
    # Central Taptic Core Icon (Haptic Fingerprint / Motor Pulse)
    core_r = 50
    wave_draw.ellipse([cx - core_r, cy - core_r, cx + core_r, cy + core_r], fill=(255, 255, 255, 240))
    # Pulse rings
    wave_draw.ellipse([cx - core_r - 12, cy - core_r - 12, cx + core_r + 12, cy + core_r + 12], outline=(168, 85, 247, 255), width=5)
    
    # Dynamic speech wave lines
    points1 = []
    points2 = []
    for x in range(padding + 30, size - padding - 30, 8):
        progress = (x - (padding + 30)) / (size - 2 * padding - 60)
        envelope = math.sin(progress * math.pi) ** 1.5
        y1 = cy + math.sin(progress * 14) * 85 * envelope + math.cos(progress * 7) * 40 * envelope
        y2 = cy - math.sin(progress * 12 + 0.5) * 65 * envelope
        points1.append((x, y1))
        points2.append((x, y2))
        
    for i in range(len(points1) - 1):
        wave_draw.line([points1[i], points1[i+1]], fill=(56, 189, 248, 220), width=6)
    for i in range(len(points2) - 1):
        wave_draw.line([points2[i], points2[i+1]], fill=(236, 72, 153, 200), width=5)
        
    trackpad = Image.alpha_composite(trackpad, wave_layer)
    
    # 5. Drop Shadow for standard macOS app icon
    final_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    shadow_box = [padding, padding + 16, size - padding, size - padding + 16]
    s_draw.rounded_rectangle(shadow_box, radius=radius, fill=(0, 0, 0, 110))
    shadow_blurred = shadow.filter(ImageFilter.GaussianBlur(24))
    
    final_img = Image.alpha_composite(final_img, shadow_blurred)
    final_img = Image.alpha_composite(final_img, trackpad)
    
    return final_img

def generate_all_sizes(base_img):
    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    
    for filename, s in sizes:
        resized = base_img.resize((s, s), Image.Resampling.LANCZOS)
        resized.save(OUTPUT_DIR / filename, "PNG")
        print(f"Generated {filename} ({s}x{s})")

if __name__ == "__main__":
    print("Generating base 1024x1024 TapticVoice icon...")
    base = create_base_icon()
    base.save(OUTPUT_DIR.parent / "AppIcon_1024.png", "PNG")
    generate_all_sizes(base)
    print("All iconset images generated successfully.")
