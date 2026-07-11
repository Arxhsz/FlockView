# FlockView BLE Start Screen

This is a starter Flipper Zero external app for the FlockView BLE native app.

It does **not** include BLE scanning yet. This version only builds the boot/start flow:

1. ASCII-style FlockView logo generated from the provided ASCII wordmark
2. `by Arxhsz` splash screen
3. `v1.0` screen with loading bar
4. Placeholder dashboard screen

## Folder contents

```text
flockview_ble_start/
├── application.fam
├── flockview_ble_start.c
├── flockview_ascii_logo.h
├── assets/
│   ├── flockview_ascii_logo_source.txt
│   ├── flockview_ascii_logo_112x28.png
│   └── flockview_icon.png
└── tools/
    └── render_logo.py
```

## How to build with uFBT

Install uFBT:

```bash
python3 -m pip install --upgrade ufbt
```

Build the `.fap` file:

```bash
cd flockview_ble_start
ufbt
```

If your Flipper is plugged in and uFBT can see it, build and launch directly:

```bash
ufbt launch
```

If you want to copy it manually, after building, look in the `dist/` folder for the generated `.fap` file and copy it to your Flipper SD card under something like:

```text
/ext/apps/Tools/
```

Then open it from the Flipper app browser.

## How to edit the boot screen text

In `flockview_ble_start.c`, edit:

```c
#define FLOCKVIEW_APP_VERSION "v1.0"
#define FLOCKVIEW_APP_AUTHOR "by Arxhsz"
```

## How to edit the ASCII logo

Edit this file:

```text
assets/flockview_ascii_logo_source.txt
```

Then regenerate the bitmap header:

```bash
python3 tools/render_logo.py
```

Then rebuild:

```bash
ufbt
```

## Notes

The Flipper screen is monochrome. The orange color comes from the real Flipper backlight, so the app draws black pixels and the physical display supplies the orange look.

The full ASCII banner is too wide to draw as normal live text on a 128×64 screen, so this project converts the ASCII wordmark into a 1-bit bitmap and draws it with `canvas_draw_xbm()`.
