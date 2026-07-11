#!/usr/bin/env python3
from pathlib import Path
from PIL import Image

SOURCE = Path(__file__).resolve().parents[1] / "assets" / "flockview_ascii_logo_source.txt"
TARGET_W, TARGET_H = 112, 28

raw = SOURCE.read_text()
lines = raw.splitlines()
while lines and lines[0].strip() == "":
    lines.pop(0)
while lines and lines[-1].strip() == "":
    lines.pop()

rows = len(lines)
cols = max(len(l) for l in lines)
cell = 1
pw = cols * cell
ph = rows * cell
ox = (TARGET_W - pw) // 2
oy = (TARGET_H - ph) // 2

best_img = Image.new("L", (TARGET_W, TARGET_H), 255)
for gy, line in enumerate(lines):
    for gx in range(cols):
        ch = line[gx] if gx < len(line) else " "
        if ch != " ":
            px = ox + gx * cell
            py = oy + gy * cell
            if 0 <= px < TARGET_W and 0 <= py < TARGET_H:
                best_img.putpixel((px, py), 0)

print(f"Sample pixels from best_img at row oy={oy}:")
for x in range(10, 25):
    print(f"  ({x},{oy}) = {best_img.getpixel((x, oy))}")

mono = best_img.point(lambda p: 255 if p < 128 else 0)

print(f"Sample pixels from mono at row oy={oy}:")
for x in range(10, 25):
    print(f"  ({x},{oy}) = {mono.getpixel((x, oy))}")

mono_arr = list(mono.getdata())
print(f"Total pixels: {len(mono_arr)}")
print(f"Foreground (255): {sum(1 for v in mono_arr if v == 255)}")
print(f"Background (0):   {sum(1 for v in mono_arr if v == 0)}")

# Check XBM encoding for first non-zero row
for y in range(TARGET_H):
    row_vals = [mono_arr[y * TARGET_W + x] for x in range(TARGET_W)]
    if any(v == 255 for v in row_vals):
        print(f"\nRow {y} has foreground pixels")
        bytes_per_row = (TARGET_W + 7) // 8
        for byte_index in range(bytes_per_row):
            b = 0
            for bit in range(8):
                x = byte_index * 8 + bit
                if x < TARGET_W and mono_arr[y * TARGET_W + x] == 255:
                    b |= (1 << bit)
            if b != 0:
                print(f"  byte[{byte_index}] = 0x{b:02X}")
        break
