# FlockView Phase 2 — Design

## Architecture

Single-file Flipper Zero external app using ViewPort + MessageQueue pattern (same as Phase 1).

### State

```c
typedef struct {
    Gui*              gui;
    ViewPort*         view_port;
    FuriMessageQueue* queue;
    FuriTimer*        timer;
    FuriMutex*        mutex;

    // Boot
    FlockViewScreen screen;
    uint32_t        elapsed_ms;
    uint8_t         progress;
    bool            running;

    // List navigation
    uint8_t  selected;       // currently highlighted device index
    uint8_t  list_offset;    // scroll offset for camera list
    uint8_t  best_idx;       // index of highest-confidence device (star)

    // Radar animation
    uint8_t  radar_angle;    // 0..35 (10° steps)

    // RSSI history for details graph
    int8_t   rssi_history[8];
    uint8_t  rssi_hist_idx;

    // Settings
    uint8_t  settings_selected;  // 0=ScanMode, 1=RssiFilter, 2=About
    uint8_t  scan_mode;          // 0=Normal, 1=Aggressive, 2=Stealth
    uint8_t  rssi_filter;        // 0=Off, 1=-70, 2=-80, 3=-90

    // Alert
    bool     show_alert;
    uint8_t  alert_device_idx;

    uint8_t  scan_tick;
} FlockViewApp;
```

### Screen Routing

Input handling dispatches based on `app->screen`:
- **Back** from any screen navigates up one level
- **Up/Down** scroll lists or move cursor
- **OK** confirms selection / drills into detail
- **Left** from Camera List → Settings

### Confidence Scoring (inline, mirrors FlockClassifier.cpp)

```c
static uint8_t flockview_score_device(const FlockViewBleDevice* dev) {
    uint8_t score = 0;
    // name pattern match: +45
    // manufacturer ID 0x09C8: +60
    // BLE OUI match: +15 (low confidence per FlockSignatures.h comment)
    // multi-signal bonus: +20 if score already > 0 and more than one signal
    // cap at 100
}
```

### Drawing Primitives Used
- `canvas_draw_frame` / `canvas_draw_box` — rectangles
- `canvas_draw_circle` — radar ring
- `canvas_draw_line` — dividers, crosshairs, sweep line, RSSI bars
- `canvas_draw_str` / `canvas_draw_str_aligned` — text
- `canvas_draw_xbm` — logo bitmap
- `canvas_set_color(ColorBlack/ColorWhite)` — for inversion

### RSSI Bar Height Mapping
Map RSSI -40..-100 dBm → bar height 16..0 px:
```c
height = (int8_t)(((rssi + 100) * 16) / 60);  // clamp 0..16
```

### Flipper Canvas Coordinates
- Screen: 128×64 pixels, (0,0) top-left
- FontPrimary: ~8px tall
- FontSecondary: ~6px tall
