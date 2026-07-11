#pragma once

#include <stddef.h>
#include <stdint.h>

static constexpr const char* FLOCKVIEW_FIRMWARE_NAME = "FlockViewScanner";
static constexpr const char* FLOCKVIEW_FIRMWARE_VERSION = "0.1.0";
static constexpr const char* FLOCKVIEW_BOARD_NAME = "esp32-wroom-32";
static constexpr uint32_t FLOCKVIEW_SERIAL_BAUD = 115200;
static constexpr bool FLOCKVIEW_PRETTY_LOGS_ENABLED = true;
static constexpr uint8_t FLOCKVIEW_LOG_LEVEL = 2;

static constexpr uint8_t WIFI_MIN_CHANNEL = 1;
static constexpr uint8_t WIFI_MAX_CHANNEL = 11;
static constexpr uint32_t DEFAULT_WIFI_DWELL_MS = 350;
static constexpr uint32_t DEFAULT_WIFI_WINDOW_MS = 4000;
static constexpr uint32_t DEFAULT_BLE_WINDOW_MS = 3000;
static constexpr uint32_t DEFAULT_STATUS_INTERVAL_MS = 5000;
static constexpr uint32_t DEFAULT_EMIT_COOLDOWN_MS = 5000;
static constexpr int8_t DEFAULT_RSSI_MIN = -95;

static constexpr int8_t DEFAULT_CLOSE_THRESHOLD_DBM = -59;
static constexpr int8_t DEFAULT_MEDIUM_THRESHOLD_DBM = -74;
static constexpr float DEFAULT_RSSI_ALPHA = 0.35f;

static constexpr size_t SCANNER_OBSERVATION_QUEUE_LENGTH = 48;
static constexpr size_t MAX_TRACKED_DEVICES = 128;
static constexpr size_t MAX_DETECTION_METHODS = 12;
static constexpr size_t MAX_SSID_LENGTH = 32;
static constexpr size_t MAX_BLE_NAME_LENGTH = 31;
static constexpr size_t MAX_SERVICE_UUIDS = 4;
static constexpr size_t MAX_SERVICE_UUID_LENGTH = 36;

struct RuntimeConfig {
    uint32_t wifiDwellMs = DEFAULT_WIFI_DWELL_MS;
    uint32_t wifiWindowMs = DEFAULT_WIFI_WINDOW_MS;
    uint32_t bleWindowMs = DEFAULT_BLE_WINDOW_MS;
    uint32_t emitCooldownMs = DEFAULT_EMIT_COOLDOWN_MS;
    int8_t rssiMin = DEFAULT_RSSI_MIN;
    int8_t closeThreshold = DEFAULT_CLOSE_THRESHOLD_DBM;
    int8_t mediumThreshold = DEFAULT_MEDIUM_THRESHOLD_DBM;
    float rssiAlpha = DEFAULT_RSSI_ALPHA;
    bool debugEnabled = false;
    bool pauseSimulation = false;
};
