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
cell = max(1, min((TARGET_W - 4) // cols, (TARGET_H - 4) // rows))
pw = cols * cell
ph = rows * cell
ox = (TARGET_W - pw) // 2
oy = (TARGET_H - ph) // 2
print(f"rows={rows}, cols={cols}, cell={cell}, pw={pw}, ph={ph}, ox={ox}, oy={oy}")

best_img = Image.new("L", (TARGET_W, TARGET_H), 255)
count = 0
for gy, line in enumerate(lines):
    for gx in range(cols):
        ch = line[gx] if gx < len(line) else " "
        if ch != " ":
            for dy in range(cell):
                for dx in range(cell):
                    px = ox + gx * cell + dx
                    py = oy + gy * cell + dy
                    if 0 <= px < TARGET_W and 0 <= py < TARGET_H:
                        best_img.putpixel((px, py), 0)
                        count += 1

print(f"Pixels set: {count}")
mono = best_img.point(lambda p: 255 if p < 128 else 0)
mono_arr = list(mono.getdata())
nonzero = sum(1 for v in mono_arr if v == 255)
print(f"Foreground pixels in mono: {nonzero}")

# Print first row that has any pixels
for y in range(TARGET_H):
    row_data = [mono_arr[y * TARGET_W + x] for x in range(TARGET_W)]
    if any(v == 255 for v in row_data):
        bits = "".join("X" if v == 255 else "." for v in row_data)
        print(f"Row {y}: {bits}")
        break
