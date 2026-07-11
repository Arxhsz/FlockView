#include "SerialProtocol.h"

#ifndef UNIT_TEST

#include "ScannerConfig.h"
#include <ArduinoJson.h>
#include <cstdarg>
#include <cstdio>

void SerialProtocol::begin(uint32_t baud) {
    Serial.begin(baud);
}

bool SerialProtocol::readCommand(char* out, size_t outSize) {
    if (!out || outSize == 0) {
        return false;
    }

    while (Serial.available() > 0) {
        const char c = static_cast<char>(Serial.read());
        if (c == '\r') {
            continue;
        }
        if (c == '\n') {
            _commandBuffer[_commandLength] = '\0';
            strncpy(out, _commandBuffer, outSize - 1);
            out[outSize - 1] = '\0';
            _commandLength = 0;
            _commandBuffer[0] = '\0';
            return out[0] != '\0';
        }
        if (_commandLength < sizeof(_commandBuffer) - 1) {
            _commandBuffer[_commandLength++] = c;
        } else {
            _commandLength = 0;
            _commandBuffer[0] = '\0';
        }
    }
    return false;
}

const char* SerialProtocol::logLevelLabel(SerialLogLevel level) {
    switch (level) {
        case SerialLogLevel::Boot:
            return "BOOT";
        case SerialLogLevel::Info:
            return "INFO";
        case SerialLogLevel::Success:
            return " OK ";
        case SerialLogLevel::Scan:
            return "SCAN";
        case SerialLogLevel::Command:
            return "CMD ";
        case SerialLogLevel::Mode:
            return "MODE";
        case SerialLogLevel::Match:
            return "MATCH";
        case SerialLogLevel::Warning:
            return "WARN";
        case SerialLogLevel::Error:
            return "ERR ";
        case SerialLogLevel::Ready:
            return "READY";
        default:
            return "INFO";
    }
}

void SerialProtocol::log(SerialLogLevel level, const char* message) {
    Serial.print("# [");
    Serial.print(logLevelLabel(level));
    Serial.print("] ");
    Serial.println(message ? message : "");
}

void SerialProtocol::logf(SerialLogLevel level, const char* format, ...) {
    if (!format) {
        log(level, "");
        return;
    }

    char message[192];
    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof(message), format, args);
    va_end(args);
    message[sizeof(message) - 1] = '\0';
    log(level, message);
}

void SerialProtocol::logDivider() {
    Serial.println("#  ------------------------------------------------------------");
}

void SerialProtocol::printBootBanner() {
    Serial.println();
    Serial.println("# /$$$$$$$$ /$$                     /$$       /$$    /$$ /$$                        ");
    Serial.println("#| $$_____/| $$                    | $$      | $$   | $$|__/                        ");
    Serial.println("#| $$      | $$  /$$$$$$   /$$$$$$$| $$   /$$| $$   | $$ /$$  /$$$$$$  /$$  /$$  /$$");
    Serial.println("#| $$$$$   | $$ /$$__  $$ /$$_____/| $$  /$$/|  $$ / $$/| $$ /$$__  $$| $$ | $$ | $$ ");
    Serial.println("#| $$__/   | $$| $$  \\ $$| $$      | $$$$$$/  \\  $$ $$/ | $$| $$$$$$$$| $$ | $$ | $$ ");
    Serial.println("#| $$      | $$| $$  | $$| $$      | $$_  $$   \\  $$$/  | $$| $$_____/| $$ | $$ | $$ ");
    Serial.println("#| $$      | $$|  $$$$$$/|  $$$$$$$| $$ \\  $$   \\  $/   | $$|  $$$$$$$|  $$$$$/$$$$/ ");
    Serial.println("#|__/      |__/ \\______/  \\_______/|__/  \\__/    \\_/    |__/ \\_______/ \\_____/\\___/  ");
    Serial.println("#");
    Serial.println("#  FlockView Scanner Firmware");
    Serial.println("#  Passive Wi-Fi + BLE Detection");
    logDivider();
}

void SerialProtocol::emitBoot(uint32_t uptimeMs) {
    JsonDocument doc;
    doc["schema_version"] = 1;
    doc["event"] = "boot";
    doc["firmware"] = FLOCKVIEW_FIRMWARE_NAME;
    doc["firmware_version"] = FLOCKVIEW_FIRMWARE_VERSION;
    doc["board"] = FLOCKVIEW_BOARD_NAME;
    doc["passive_only"] = true;
    JsonArray bands = doc["wifi_bands"].to<JsonArray>();
    bands.add("2.4GHz");
    doc["ble_supported"] = true;
    doc["uptime_ms"] = uptimeMs;
    serializeJson(doc, Serial);
    Serial.println();
}

void SerialProtocol::emitDetection(
    const ScannerObservation& observation,
    const ClassificationResult& classification,
    const DeviceRecord& record,
    uint32_t uptimeMs) {
    JsonDocument doc;
    char mac[18];
    char bssid[18];
    char destination[18];
    char deviceId[28];
    formatMac(observation.address, mac, sizeof(mac));
    formatMac(observation.bssid, bssid, sizeof(bssid));
    formatMac(observation.destination, destination, sizeof(destination));
    snprintf(deviceId, sizeof(deviceId), "%s:%s", protocolToString(observation.protocol), mac);

    doc["schema_version"] = 1;
    doc["event"] = "detection";
    doc["vendor"] = classification.vendor;
    doc["device_type"] = classification.deviceType;
    doc["protocol"] = protocolToString(observation.protocol);
    doc["device_id"] = deviceId;
    doc["mac_address"] = mac;

    if (observation.protocol == ProtocolType::Wifi) {
        doc["destination_mac"] = destination;
        doc["bssid"] = bssid;
        doc["ssid"] = observation.ssid;
        doc["frame_subtype"] = wifiSubtypeToString(observation.wifiSubtype);
        doc["channel"] = observation.channel;
        doc["frequency_mhz"] = observation.frequencyMHz;
        doc["sequence_number"] = observation.sequenceNumber;
    } else {
        doc["address_type"] = observation.addressType;
        doc["name"] = observation.bleName;
        if (observation.hasManufacturerId) {
            char manufacturer[8];
            snprintf(manufacturer, sizeof(manufacturer), "0x%04X", observation.manufacturerId);
            doc["manufacturer_id"] = manufacturer;
        } else {
            doc["manufacturer_id"] = nullptr;
        }
        JsonArray serviceUuids = doc["service_uuids"].to<JsonArray>();
        for (uint8_t i = 0; i < observation.serviceUuidCount; ++i) {
            serviceUuids.add(observation.serviceUuids[i]);
        }
        if (observation.hasTxPower) {
            doc["tx_power"] = observation.txPower;
        } else {
            doc["tx_power"] = nullptr;
        }
        doc["connectable"] = observation.connectable;
        doc["advertisement_type"] = observation.advertisementType;
    }

    doc["rssi"] = observation.rssi;
    doc["smoothed_rssi"] = record.rssi.smoothedRssi;
    doc["peak_rssi"] = record.rssi.peakRssi;
    doc["average_rssi"] = record.rssi.averageRssi;
    doc["proximity"] = proximityToString(record.proximity);
    doc["rssi_trend"] = rssiTrendToString(record.rssi.trend);
    doc["confidence"] = classification.confidence;
    doc["confidence_label"] = classification.confidenceLabel;

    JsonArray methods = doc["detection_methods"].to<JsonArray>();
    for (size_t i = 0; i < classification.methodCount; ++i) {
        methods.add(detectionMethodToString(classification.methods[i]));
    }

    doc["observation_count"] = record.rssi.observationCount;
    doc["first_seen_ms"] = record.firstSeenMs;
    doc["last_seen_ms"] = record.lastSeenMs;
    doc["uptime_ms"] = uptimeMs;

    serializeJson(doc, Serial);
    Serial.println();
}

void SerialProtocol::emitStatus(const ScannerRuntimeStats& stats, uint32_t uptimeMs) {
    JsonDocument doc;
    doc["schema_version"] = 1;
    doc["event"] = "scanner_status";
    doc["state"] = stats.mode == ScannerMode::Stopped ? "stopped" : "scanning";
    doc["mode"] = scannerModeToString(stats.mode);
    doc["phase"] = scanPhaseToString(stats.phase);
    doc["wifi_channel"] = stats.wifiChannel;
    doc["wifi_frames_seen"] = stats.wifiFramesSeen;
    doc["ble_advertisements_seen"] = stats.bleAdvertisementsSeen;
    doc["queue_depth"] = stats.queueDepth;
    doc["queue_high_watermark"] = stats.queueHighWatermark;
    doc["dropped_observations"] = stats.droppedObservations;
    doc["tracked_devices"] = stats.trackedDevices;
    doc["matching_devices"] = stats.matchingDevices;
    doc["free_heap"] = ESP.getFreeHeap();
    doc["uptime_ms"] = uptimeMs;
    serializeJson(doc, Serial);
    Serial.println();
}

void SerialProtocol::emitError(const char* component, const char* code, const char* message, uint32_t uptimeMs) {
    JsonDocument doc;
    doc["schema_version"] = 1;
    doc["event"] = "error";
    doc["component"] = component;
    doc["code"] = code;
    doc["message"] = message;
    doc["uptime_ms"] = uptimeMs;
    serializeJson(doc, Serial);
    Serial.println();
}

void SerialProtocol::emitCommandResponse(const char* command, bool ok, const char* message, uint32_t uptimeMs) {
    JsonDocument doc;
    doc["schema_version"] = 1;
    doc["event"] = "command_response";
    doc["command"] = command;
    doc["success"] = ok;
    doc["ok"] = ok;
    doc["message"] = message;
    doc["uptime_ms"] = uptimeMs;
    serializeJson(doc, Serial);
    Serial.println();
}

void SerialProtocol::emitDebug(const char* component, const char* message, uint32_t uptimeMs) {
    JsonDocument doc;
    doc["schema_version"] = 1;
    doc["event"] = "debug";
    doc["component"] = component;
    doc["message"] = message;
    doc["uptime_ms"] = uptimeMs;
    serializeJson(doc, Serial);
    Serial.println();
}

#endif
