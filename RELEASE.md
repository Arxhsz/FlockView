# FlockView v1.0.0

FlockView v1.0.0 is the official first release of the native macOS scanner console and ESP32 firmware project.

## Included

- Native SwiftUI macOS app.
- Passive ESP32-WROOM-32 scanner firmware in `FlockViewScanner/`.
- Web flasher for ESP32 firmware at `https://arxhsz.github.io/FlockView/`.
- Direct firmware binary at `docs/firmware/flockview-scanner-v1.0.0.bin`.
- Hardware Mode for the ESP32 scanner firmware.
- Mac Scanner mode using CoreWLAN and CoreBluetooth.
- Test Mode with local synthetic detections for demos and validation.
- Serial handshake validation before the app shows a hardware scanner as connected.
- Camera detection dashboard with proximity, confidence, notes, exports, diagnostics, and notifications.
- Multi-signal vendor and signature matching with confidence scoring.
- Local JSON and CSV export.
- README screenshots captured from the actual running app in Test Mode.
- PNG app logo copied from the app asset catalog.

## Passive Scanning Model

FlockView passively observes wireless advertisements and scanner observations. It does not connect to, interfere with, impersonate, jam, or modify detected devices.

Vendor identification may use public/static OUI data, advertised names, manufacturer identifiers, service UUIDs, signal behavior, and repeated observations. Randomized or private addresses can limit identification accuracy, and a vendor match alone does not guarantee that a device is a Flock Safety camera.

## Installer

Download `FlockView-macOS.dmg`, open it, then drag `FlockView.app` into `Applications`.

The ZIP asset is included as a plain app bundle archive for users who prefer a direct download.

## Firmware

Flash the ESP32 scanner from the browser at:

```text
https://arxhsz.github.io/FlockView/
```

The firmware application binary is included in the repository at:

```text
docs/firmware/flockview-scanner-v1.0.0.bin
```

## Build The Installer Locally

```bash
chmod +x scripts/package_release.sh
./scripts/package_release.sh
```

The script creates:

```text
build/release/FlockView-macOS.dmg
build/release/FlockView-macOS.zip
```

## Note

This local build is signed for local development. For broad public distribution outside GitHub source builds, sign and notarize the app with an Apple Developer account.
