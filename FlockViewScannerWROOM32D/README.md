# flock-spoof ESP32 Port

This repository now mirrors the upstream `0xD34D/flock-spoof` project and has been ported for ESP32 using the ESP-IDF framework.

## Project Structure

- `CMakeLists.txt` — ESP-IDF project root
- `main/` — spoofing application source files
- `sdkconfig.defaults` — ESP-IDF default configuration
- `platformio.ini` — PlatformIO build wrapper for `esp32dev` using `espidf`

## Build and Upload

Install PlatformIO and ESP-IDF, then run:

```bash
cd FlockViewScannerWROOM32D
pio run -e esp32dev
pio run -e esp32dev --target upload
pio device monitor -e esp32dev
```

Alternatively, with ESP-IDF installed:

```bash
idf.py set-target esp32
idf.py build
idf.py -p /dev/ttyUSB0 flash monitor
```

## Notes

The original scanner implementation in `src/` is no longer part of the active ESP-IDF spoofing build. The active port now uses `main/` source files matching the upstream `flock-spoof` repo.
