#include "ScannerTypes.h"
#include <stdio.h>
#include <string.h>

const char* scannerModeToString(ScannerMode mode) {
    switch (mode) {
    case ScannerMode::Dual: return "dual";
    case ScannerMode::WifiOnly: return "wifi";
    case ScannerMode::BleOnly: return "ble";
    case ScannerMode::Stopped: return "stopped";
    default: return "unknown";
    }
}

const char* scanPhaseToString(ScanPhase phase) {
    switch (phase) {
    case ScanPhase::Idle: return "idle";
    case ScanPhase::Wifi: return "wifi";
    case ScanPhase::Ble: return "ble";
    default: return "unknown";
    }
}

const char* protocolToString(ProtocolType protocol) {
    return protocol == ProtocolType::Wifi ? "wifi" : "ble";
}

const char* wifiSubtypeToString(WifiFrameSubtype subtype) {
    switch (subtype) {
    case WifiFrameSubtype::AssociationRequest: return "association_request";
    case WifiFrameSubtype::ReassociationRequest: return "reassociation_request";
    case WifiFrameSubtype::ProbeRequest: return "probe_request";
    case WifiFrameSubtype::ProbeResponse: return "probe_response";
    case WifiFrameSubtype::Beacon: return "beacon";
    case WifiFrameSubtype::Authentication: return "authentication";
    case WifiFrameSubtype::Action: return "action";
    case WifiFrameSubtype::Unknown:
    default: return "unknown";
    }
}

const char* rssiTrendToString(RssiTrend trend) {
    switch (trend) {
    case RssiTrend::Rising: return "rising";
    case RssiTrend::Falling: return "falling";
    case RssiTrend::Stable:
    default: return "stable";
    }
}

const char* proximityToString(Proximity proximity) {
    switch (proximity) {
    case Proximity::Close: return "close";
    case Proximity::Medium: return "medium";
    case Proximity::Far:
    default: return "far";
    }
}

const char* detectionMethodToString(DetectionMethod method) {
    switch (method) {
    case DetectionMethod::KnownWifiOui: return "known_wifi_oui";
    case DetectionMethod::KnownBleOui: return "known_ble_oui";
    case DetectionMethod::WifiSsidPattern: return "wifi_ssid_pattern";
    case DetectionMethod::WifiSsidFormat: return "wifi_ssid_format";
    case DetectionMethod::WifiWildcardProbe: return "wifi_wildcard_probe";
    case DetectionMethod::BleNamePattern: return "ble_name_pattern";
    case DetectionMethod::BleManufacturerId: return "ble_manufacturer_id";
    case DetectionMethod::BleServiceUuid: return "ble_service_uuid";
    case DetectionMethod::BleStaticAddress: return "ble_static_address";
    case DetectionMethod::MultipleSignals: return "multiple_signals";
    default: return "unknown";
    }
}

uint16_t wifiFrequencyForChannel(uint8_t channel) {
    if (channel == 14) {
        return 2484;
    }
    if (channel >= 1 && channel <= 13) {
        return static_cast<uint16_t>(2407 + (channel * 5));
    }
    return 0;
}

void formatMac(const uint8_t mac[6], char* out, size_t outSize) {
    if (!out || outSize == 0) {
        return;
    }
    snprintf(out, outSize, "%02X:%02X:%02X:%02X:%02X:%02X",
        mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

static int hexValue(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

bool parseMacString(const char* text, uint8_t out[6]) {
    if (!text || !out) {
        return false;
    }
    size_t index = 0;
    for (size_t i = 0; i < 6; ++i) {
        const int high = hexValue(text[index++]);
        const int low = hexValue(text[index++]);
        if (high < 0 || low < 0) {
            return false;
        }
        out[i] = static_cast<uint8_t>((high << 4) | low);
        if (i < 5) {
            if (text[index] != ':') {
                return false;
            }
            index += 1;
        }
    }
    return text[index] == '\0';
}

bool macIsZero(const uint8_t mac[6]) {
    for (size_t i = 0; i < 6; ++i) {
        if (mac[i] != 0) {
            return false;
        }
    }
    return true;
}

bool macIsMulticast(const uint8_t mac[6]) {
    return (mac[0] & 0x01) != 0;
}

bool macIsLocallyAdministered(const uint8_t mac[6]) {
    return (mac[0] & 0x02) != 0;
}

bool macEquals(const uint8_t a[6], const uint8_t b[6]) {
    return memcmp(a, b, 6) == 0;
}
