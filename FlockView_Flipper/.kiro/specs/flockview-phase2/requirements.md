# FlockView Phase 2 — Full Screen Implementation

## Overview
Replace the placeholder scanner screen in `flockview_ble_start.c` with a complete 9-screen UI implementing Flock Safety camera detection on the Flipper Zero. The boot sequence (author splash + loading bar) must remain intact.

## Requirements

### R1 — Sample Data
- 6 sample Flock camera devices must be defined (up from 4)
- Each device has: MAC address, BLE name, RSSI (dBm), confidence (%), OUI bytes, manufacturer ID flag
- At least 2 devices must have manufacturer ID 0x09C8 (FLOCK_BLE_MANUFACTURER_ID from FlockSignatures.h)
- At least 2 devices must match BLE name patterns: "FS Ext Battery", "Penguin", "Flock", "FlockCam", "FS-"
- Confidence scoring mirrors FlockClassifier.cpp: name_pattern=45pts, manufacturer_id=60pts, ble_oui=low score, multi_signal bonus=20pts, capped at 100

### R2 — Screen Navigation State Machine
The app must support these screens via a FlockViewScreen enum:
1. `FlockViewScreenAuthor` — boot splash with logo + "by Arxhsz"
2. `FlockViewScreenLoading` — boot loading bar
3. `FlockViewScreenRadar` — main camera list (no-camera state when list empty)
4. `FlockViewScreenCameraList` — scrollable list with RSSI bars, scrollbar, star marker for highest confidence
5. `FlockViewScreenNewAlert` — new camera detected alert overlay
6. `FlockViewScreenDetails` — selected camera details with mini RSSI graph (last 8 readings)
7. `FlockViewScreenSettings` — settings menu (3 items: Scan Mode, RSSI Filter, About)
8. `FlockViewScreenScanMode` — subscreen: Normal / Aggressive / Stealth
9. `FlockViewScreenRssiFilter` — subscreen: Off / -70dBm / -80dBm / -90dBm

### R3 — Radar Screen (no-camera state)
- Title "FlockView" top-left in FontPrimary
- Subtitle "BLE Camera Radar" in FontSecondary
- Center: radar circle (r=18) with crosshairs
- Animated sweep line rotating every tick (360°/36 ticks = 10° per tick)
- "No Flock devices detected" text centered below radar
- Footer: "OK:scan  Back:exit"

### R4 — Camera List Screen
- Header "FlockView" + device count badge (e.g. "6 found")
- Divider line at y=13
- Each row (height=10px): confidence bar (4px wide, height proportional to confidence), MAC address shortened (last 6 chars), BLE name truncated to 10 chars, RSSI value
- Scrollbar on right edge when list > 5 items
- Star character (*) prefix on row with highest confidence
- Selected row inverted (white-on-black)
- Footer: "OK:detail  ▲▼:scroll  ←:settings"

### R5 — New Camera Alert Screen
- Full-screen overlay
- "! NEW CAMERA !" header centered
- MAC address and name of detected camera
- Confidence percentage and label (POSSIBLE/LIKELY/HIGH/CONFIRMED per FlockClassifier thresholds: 40/70/85)
- RSSI value
- Footer: "OK:details  Back:list"

### R6 — Details Screen
- Header: device name (truncated) + confidence%
- MAC address row
- RSSI current value + mini bar graph of last 8 readings (each bar 3px wide, height scaled 0-16px for RSSI -40 to -100)
- Confidence label (CONFIRMED ≥85, HIGH ≥70, LIKELY ≥40, else POSSIBLE)
- OUI match indicator
- Manufacturer ID match indicator (shows "MFR:0x09C8" if matched)
- BLE name pattern match indicator
- Footer: "Back:list"

### R7 — Settings Menu
- Title "Settings"
- 3 menu items with selection cursor (▶):
  1. Scan Mode → (current value)
  2. RSSI Filter → (current value)
  3. About
- Selected item inverted
- Footer: "OK:select  Back:list"

### R8 — Scan Mode Subscreen
- Title "Scan Mode"
- 3 options: Normal, Aggressive, Stealth
- Selected option marked with ● (filled circle), others with ○
- Current selection highlighted
- Footer: "OK:set  Back:settings"

### R9 — RSSI Filter Subscreen
- Title "RSSI Filter"
- 4 options: Off, -70 dBm, -80 dBm, -90 dBm
- Same radio-button style as Scan Mode
- Footer: "OK:set  Back:settings"

### R10 — Boot Sequence (preserve)
- Author screen: logo + "by Arxhsz" for 1200ms
- Loading screen: logo + version + animated progress bar for 2200ms
- After boot: transitions to Radar screen (or Camera List if devices present)

### R11 — Build
- Must compile with `ufbt` from /Users/kanaan/Documents/FlockView/FlockView_Flipper/
- Single C file: flockview_ble_start.c
- Stack size 2KB (already set in application.fam)
- No new header files required (logo header already exists)
