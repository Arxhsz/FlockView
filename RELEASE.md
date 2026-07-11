# FlockView Release

## FlockView macOS Preview Release

This release packages the native macOS FlockView app with the included ESP32 scanner firmware source and release tooling.

### Included

- Native SwiftUI macOS app.
- Passive ESP32-WROOM-32 scanner firmware in `FlockViewScanner/`.
- ESP-IDF WROOM-32D firmware variant in `FlockViewScannerWROOM32D/`.
- Hardware, Mac Scanner, Test, and Recorded Playback sources.
- Serial handshake validation before the app shows a scanner as connected.
- Camera detection dashboard with proximity, confidence, notes, exports, diagnostics, and notifications.
- Local JSON and CSV export.
- README screenshots captured from the actual app.
- PNG app logo copied from the app asset catalog.

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

This is a local development distribution. If you share the app outside your Mac, sign and notarize the release build with your Apple Developer account before broad distribution.
