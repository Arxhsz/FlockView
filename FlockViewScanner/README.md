# FlockViewScanner

FlockViewScanner is passive ESP32-WROOM-32 firmware for observing publicly broadcast BLE advertisements and 2.4 GHz Wi-Fi management-frame metadata associated with documented Flock Safety camera hardware signatures. It sends normalized newline-delimited JSON events over USB serial for the native macOS FlockView app.

This firmware never connects to, modifies, joins, transmits probes to, jams, injects packets at, deauthenticates, spoofs, replays, or captures credentials from detected devices.

## Hardware

- ESP32-WROOM-32 development board
- PlatformIO board target: `esp32dev`
- Arduino framework
- USB serial via the board's external USB-to-UART interface
- 2.4 GHz Wi-Fi only
- Bluetooth Low Energy advertisement scanning

ESP32-WROOM-32 does not support 5 GHz or 6 GHz Wi-Fi, so this firmware only hops 2.4 GHz channels 1 through 11.

## Passive-Only Behavior

The scanner listens for:

- Wi-Fi management frames in promiscuous mode
- BLE advertisement packets using NimBLE passive scanning

The scanner does not:

- Connect to Wi-Fi access points
- Connect to BLE devices
- Send active BLE scan requests
- Transmit probe requests
- Inject packets
- Jam or interfere
- Capture credentials
- Parse encrypted payload contents
- Modify detected devices

## Build, Upload, Monitor, Test

Install PlatformIO, then run:

```bash
pio run
pio run --target upload
pio device monitor
pio test -e native
```

Use `pio test -e native` for the classifier, cache, and RSSI tests that do not require radio hardware. A plain `pio test` uses PlatformIO's default environment behavior and may attempt embedded testing depending on your local setup.

## Project Architecture

```text
Wi-Fi management frames / BLE advertisements
                    |
         lightweight radio callback
                    |
           fixed-size FreeRTOS queue
                    |
            main-loop processing
                    |
        vendor classifier and scoring
                    |
        duplicate suppression and RSSI
                    |
          JSON Lines over USB serial
```

Important boundaries:

- `WifiScanner` does minimal frame parsing in the promiscuous callback and never prints, blocks, or allocates there.
- `BleScanner` uses NimBLE passive scanning with `setActiveScan(false)`.
- `FlockClassifier` contains scoring logic and depends on signatures isolated in `FlockSignatures.h`.
- `DetectionCache` tracks up to 128 matching devices with fixed-size records.
- `RssiTracker` smooths RSSI using an exponential moving average.
- `SerialProtocol` emits one valid JSON object per line.

## Scanner Scheduling

The ESP32-WROOM-32 shares its 2.4 GHz radio system between Wi-Fi and BLE. Dual mode uses stable interleaving:

- Wi-Fi window: 4 seconds
- BLE window: 3 seconds
- Repeat

Wi-Fi-only and BLE-only modes are also supported.

## Serial Commands

Commands are newline-terminated ASCII. Every command returns JSON.

```text
PING
STATUS
START
STOP
MODE DUAL
MODE WIFI
MODE BLE
CLEAR
SET WIFI DWELL <milliseconds>
SET BLE WINDOW <milliseconds>
SET RSSI MIN <value>
SET DEBUG ON
SET DEBUG OFF
```

Default values:

- Wi-Fi dwell: `350 ms`
- BLE window: `3000 ms`
- Minimum RSSI: `-95 dBm`
- Duplicate cooldown: `5000 ms`

## JSON Lines

Every serial line is exactly one valid JSON object.

### Boot Event

```json
{"schema_version":1,"event":"boot","firmware":"FlockViewScanner","firmware_version":"0.1.0","board":"esp32-wroom-32","passive_only":true,"wifi_bands":["2.4GHz"],"ble_supported":true,"uptime_ms":0}
```

### Detection Event

Common fields:

- `schema_version`
- `event`
- `vendor`
- `device_type`
- `protocol`
- `device_id`
- `mac_address`
- `rssi`
- `smoothed_rssi`
- `peak_rssi`
- `average_rssi`
- `proximity`
- `rssi_trend`
- `confidence`
- `confidence_label`
- `detection_methods`
- `observation_count`
- `first_seen_ms`
- `last_seen_ms`
- `uptime_ms`

Wi-Fi detections add:

- `destination_mac`
- `bssid`
- `ssid`
- `frame_subtype`
- `channel`
- `frequency_mhz`
- `sequence_number`

BLE detections add:

- `address_type`
- `name`
- `manufacturer_id`
- `service_uuids`
- `tx_power`
- `connectable`
- `advertisement_type`

### Scanner Status Event

Status is emitted every 5 seconds and in response to `STATUS`.

```json
{"schema_version":1,"event":"scanner_status","state":"scanning","mode":"dual","phase":"wifi","wifi_channel":6,"wifi_frames_seen":15420,"ble_advertisements_seen":942,"queue_depth":3,"queue_high_watermark":18,"dropped_observations":0,"tracked_devices":16,"matching_devices":3,"free_heap":161240,"uptime_ms":184392}
```

### Error Event

```json
{"schema_version":1,"event":"error","component":"wifi_scanner","code":"QUEUE_FULL","message":"Wi-Fi observation queue overflow","uptime_ms":184392}
```

## Confidence Model

The classifier uses only publicly broadcast metadata documented in the referenced public projects.

- Known OUI only: low confidence, `POSSIBLE`
- Generic name pattern only: low-to-medium confidence, usually `LIKELY`
- Exact documented `Flock-XXXX` SSID format: `HIGH`
- Documented manufacturer ID `0x09C8`: `LIKELY`
- BLE name plus manufacturer ID: can become `CONFIRMED`
- Known OUI plus wildcard probe request: `HIGH`
- Multiple independent methods receive a confidence bonus

OUI-only detections are not proof. Generic component-vendor OUIs can appear in unrelated equipment, so detections should be verified independently.

## RSSI and Proximity

RSSI is a proximity indicator, not an exact distance.

Default thresholds:

- Close: `-59 dBm` or stronger
- Medium: `-60` through `-74 dBm`
- Far: `-75 dBm` or weaker

The firmware tracks:

- Current RSSI
- Smoothed RSSI using `smoothed = alpha * newest + (1 - alpha) * previous`
- Average RSSI
- Peak RSSI
- Minimum RSSI
- Trend: `rising`, `stable`, or `falling`

## Duplicate Suppression

The scanner does not emit every observed packet. It emits:

- Immediately for a new matching device
- When confidence changes
- When proximity changes
- When RSSI changes by at least 5 dBm
- Otherwise at most once every 5 seconds per device

Internal observation counts continue updating while output is suppressed.

## Mac App Compatibility

The future SwiftUI Mac app can:

- Read one JSON object per serial line
- Group cards by `device_id`
- Update proximity and signal bars
- Display current, average, and peak RSSI
- Track first-seen and last-seen times
- Show confidence methods
- Export JSON and CSV

Field names are intentionally stable for app-side parsing.

## Known Limitations

- ESP32-WROOM-32 supports only 2.4 GHz Wi-Fi.
- BLE and Wi-Fi are interleaved in dual mode for stability.
- The firmware observes metadata only and does not validate physical installation ownership.
- RSSI does not map to exact distance.
- OUI-only detections are not proof.
- BLE service UUID matching is implemented but ships with no Flock-specific UUID signatures because the referenced UUID datasets are for non-camera Raven/SoundThinking devices.

## Reference Concepts

The implementation uses passive scanning concepts and documented metadata signatures from:

- [colonelpanichacks/flock-you](https://github.com/colonelpanichacks/flock-you)
- [ESP32Marauder Flock-Sniff wiki](https://github.com/justcallmekoko/ESP32Marauder/wiki/Flock-Sniff)
- [GainSec/Flock-Safety-Trap-Shooter-Sniffer-Alarm](https://github.com/GainSec/Flock-Safety-Trap-Shooter-Sniffer-Alarm)
- [NSM-Barii/flock-back](https://github.com/NSM-Barii/flock-back)
- [zmattmanz/flock-detection](https://github.com/zmattmanz/flock-detection)
- [rbarriaultjr/flock-detection](https://github.com/rbarriaultjr/flock-detection)
- [ReconGrunt/FlipDeFlock](https://github.com/ReconGrunt/FlipDeFlock)

Code in this project is original and excludes unrelated functionality such as active Wi-Fi attacks, jamming, packet injection, deauthentication, ALPR evasion, active network exploitation, external dashboards, GPS logging, OLED UI, or cloud/database integrations.
