# FlockView Release

## FlockView v1.0

This release packages the native macOS FlockView app with the maintained ESP32 scanner firmware source and release tooling.

### Included

- Native SwiftUI macOS app.
- Passive ESP32-WROOM-32 scanner firmware in `FlockViewScanner/`.
- Hardware, Mac Scanner, Test, and Recorded Playback sources.
- Serial handshake validation before the app reports a scanner as connected.
- Camera-detection dashboard with proximity, confidence, notes, exports, diagnostics, and notifications.
- Local JSON and CSV export.
- Screenshots captured from the actual macOS application.
- Multi-signal vendor and signature matching with confidence scoring.

### Passive Scanning Model

FlockView passively observes wireless advertisements and scanner observations. It does not connect to, interfere with, impersonate, jam, or modify detected devices.

Vendor identification may use public/static OUI data, advertised names, manufacturer identifiers, service UUIDs, signal behavior, and repeated observations. Randomized or private addresses can limit identification accuracy, and a vendor match alone does not guarantee that a device is a Flock Safety camera.

### Installer

Build the release package locally:

```bash
chmod +x scripts/package_release.sh
./scripts/package_release.sh
```

The script creates:

```text
build/release/FlockView-macOS.dmg
build/release/FlockView-macOS.zip
```

To install from the DMG, open `FlockView-macOS.dmg` and drag `FlockView.app` into `Applications`.

### Notes

This is a local development distribution. Sign and notarize the release build with an Apple Developer account before broad distribution outside the developer's own Mac.
