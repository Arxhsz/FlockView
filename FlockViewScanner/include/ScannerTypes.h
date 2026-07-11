#pragma once

#include "ScannerConfig.h"
#include <stddef.h>
#include <stdint.h>

enum class ScannerMode : uint8_t {
    Dual,
    WifiOnly,
    BleOnly,
    Stopped
};

enum class ScanPhase : uint8_t {
    Idle,
    Wifi,
    Ble
};

enum class ProtocolType : uint8_t {
    Wifi,
    Ble
};

enum class WifiFrameSubtype : uint8_t {
    AssociationRequest = 0,
    ReassociationRequest = 2,
    ProbeRequest = 4,
    ProbeResponse = 5,
    Beacon = 8,
    Authentication = 11,
    Action = 13,
    Unknown = 255
};

enum class RssiTrend : uint8_t {
    Rising,
    Stable,
    Falling
};

enum class Proximity : uint8_t {
    Close,
    Medium,
    Far
};

enum class DetectionMethod : uint8_t {
    KnownWifiOui,
    KnownBleOui,
    WifiSsidPattern,
    WifiSsidFormat,
    WifiWildcardProbe,
    BleNamePattern,
    BleManufacturerId,
    BleServiceUuid,
    BleStaticAddress,
    MultipleSignals
};

struct ScannerObservation {
    ProtocolType protocol = ProtocolType::Wifi;
    uint32_t seenMs = 0;
    int8_t rssi = 0;
    uint8_t address[6] = {0};

    uint8_t destination[6] = {0};
    uint8_t bssid[6] = {0};
    uint8_t channel = 0;
    uint16_t frequencyMHz = 0;
    WifiFrameSubtype wifiSubtype = WifiFrameSubtype::Unknown;
    uint16_t sequenceNumber = 0;
    bool ssidPresent = false;
    bool wildcardSsid = false;
    char ssid[MAX_SSID_LENGTH + 1] = {0};

    char addressType[16] = {0};
    bool connectable = false;
    uint8_t advertisementType = 0;
    bool hasTxPower = false;
    int8_t txPower = 0;
    bool hasManufacturerId = false;
    uint16_t manufacturerId = 0;
    char bleName[MAX_BLE_NAME_LENGTH + 1] = {0};
    char serviceUuids[MAX_SERVICE_UUIDS][MAX_SERVICE_UUID_LENGTH + 1] = {};
    uint8_t serviceUuidCount = 0;
};

struct ClassificationResult {
    bool matched = false;
    uint8_t confidence = 0;
    const char* confidenceLabel = "POSSIBLE";
    const char* vendor = "Flock Safety";
    const char* deviceType = "camera";
    DetectionMethod methods[MAX_DETECTION_METHODS] = {};
    size_t methodCount = 0;
    uint32_t methodMask = 0;
};

struct RssiState {
    bool initialized = false;
    int8_t currentRssi = 0;
    int8_t peakRssi = -127;
    int8_t minimumRssi = 127;
    float smoothedRssi = 0.0f;
    float averageRssi = 0.0f;
    uint32_t observationCount = 0;
    RssiTrend trend = RssiTrend::Stable;
};

struct DeviceRecord {
    bool occupied = false;
    ProtocolType protocol = ProtocolType::Wifi;
    uint8_t address[6] = {0};
    RssiState rssi;
    uint32_t firstSeenMs = 0;
    uint32_t lastSeenMs = 0;
    uint8_t confidence = 0;
    char confidenceLabel[16] = {0};
    uint32_t methodMask = 0;
    Proximity proximity = Proximity::Far;
    uint32_t lastEmissionMs = 0;
    int8_t lastEmittedRssi = 0;
    uint8_t lastEmittedConfidence = 0;
    Proximity lastEmittedProximity = Proximity::Far;
    bool markedForEmission = false;
};

const char* scannerModeToString(ScannerMode mode);
const char* scanPhaseToString(ScanPhase phase);
const char* protocolToString(ProtocolType protocol);
const char* wifiSubtypeToString(WifiFrameSubtype subtype);
const char* rssiTrendToString(RssiTrend trend);
const char* proximityToString(Proximity proximity);
const char* detectionMethodToString(DetectionMethod method);
uint16_t wifiFrequencyForChannel(uint8_t channel);
void formatMac(const uint8_t mac[6], char* out, size_t outSize);
bool parseMacString(const char* text, uint8_t out[6]);
bool macIsZero(const uint8_t mac[6]);
bool macIsMulticast(const uint8_t mac[6]);
bool macIsLocallyAdministered(const uint8_t mac[6]);
bool macEquals(const uint8_t a[6], const uint8_t b[6]);
