#include "FlockClassifier.h"
#include "FlockOuiDatabase.h"
#include "FlockSignatures.h"
#include "ScannerConfig.h"
#include <Arduino.h>
#include <string.h>

#include <stdio.h>

// Pretty log for high-confidence matches (UART, human-readable)
static void classifierPrettyLogMatch(
    const ScannerObservation& observation,
    const ClassificationResult& result
) {
    if (!FLOCKVIEW_PRETTY_LOGS_ENABLED || FLOCKVIEW_LOG_LEVEL < 2) {
        return;
    }
    if (!result.matched || result.confidence < 40) {
        return;
    }

    char message[192];
    snprintf(
        message,
        sizeof(message),
        "%s %02X:%02X:%02X:%02X:%02X:%02X confidence=%u%% level=%s signals=%u",
        observation.protocol == ProtocolType::Ble ? "BLE" : "Wi-Fi",
        observation.address[0],
        observation.address[1],
        observation.address[2],
        observation.address[3],
        observation.address[4],
        observation.address[5],
        static_cast<unsigned int>(result.confidence),
        result.confidenceLabel ? result.confidenceLabel : "UNKNOWN",
        static_cast<unsigned int>(result.methodCount)
    );
    message[sizeof(message) - 1] = '\0';

    Serial.print("# [MATCH] ");
    Serial.println(message);
}

ClassificationResult FlockClassifier::classify(const ScannerObservation& observation) const {
    ClassificationResult result;
    result.vendor = "Flock Safety";
    result.deviceType = observation.protocol == ProtocolType::Ble ? "camera_accessory" : "camera";

    if (observation.protocol == ProtocolType::Wifi) {
        const bool wifiOui = FlockOuiDatabase::matches(observation.address);
        applyOuiEvidence(observation.address, false, result);

        if (observation.ssidPresent && observation.ssid[0] != '\0') {
            if (isFlockSsidFormat(observation.ssid)) {
                addMethod(result, DetectionMethod::WifiSsidFormat, 70);
            } else if (matchesWifiSsidPattern(observation.ssid)) {
                addMethod(result, DetectionMethod::WifiSsidPattern, 45);
            }
        }

        if (wifiOui &&
            observation.wifiSubtype == WifiFrameSubtype::ProbeRequest &&
            observation.wildcardSsid) {
            addMethod(result, DetectionMethod::WifiWildcardProbe, 35);
        }
    } else {
        applyOuiEvidence(observation.address, true, result);
        if (matchesBleNamePattern(observation.bleName)) {
            addMethod(result, DetectionMethod::BleNamePattern, 45);
        }
        if (observation.hasManufacturerId && matchesBleManufacturerId(observation.manufacturerId)) {
            addMethod(result, DetectionMethod::BleManufacturerId, 60);
        }
        for (uint8_t i = 0; i < observation.serviceUuidCount; ++i) {
            if (matchesBleServiceUuid(observation.serviceUuids[i])) {
                addMethod(result, DetectionMethod::BleServiceUuid, 70);
                break;
            }
        }
        if (isStaticBleAddressLabel(observation.addressType) && result.methodCount > 0) {
            addMethod(result, DetectionMethod::BleStaticAddress, 10);
        }
    }

    if (result.methodCount >= 2) {
        addMethod(result, DetectionMethod::MultipleSignals, 20);
    }

    result.matched = result.methodCount > 0;
    result.confidenceLabel = labelForConfidence(result.confidence);
    classifierPrettyLogMatch(observation, result);
    return result;
}

bool FlockClassifier::matchesWifiOui(const uint8_t mac[6]) const {
    return FlockOuiDatabase::matches(mac);
}

bool FlockClassifier::matchesBleOui(const uint8_t mac[6]) const {
    return FlockOuiDatabase::matches(mac);
}

bool FlockClassifier::matchesWifiSsidPattern(const char* ssid) const {
    if (!ssid || ssid[0] == '\0') {
        return false;
    }
    for (size_t i = 0; i < FLOCK_WIFI_SSID_PATTERN_COUNT; ++i) {
        if (containsCaseInsensitive(ssid, FLOCK_WIFI_SSID_PATTERNS[i].value)) {
            return true;
        }
    }
    return false;
}

bool FlockClassifier::matchesBleNamePattern(const char* name) const {
    if (!name || name[0] == '\0') {
        return false;
    }
    for (size_t i = 0; i < FLOCK_BLE_NAME_PATTERN_COUNT; ++i) {
        if (containsCaseInsensitive(name, FLOCK_BLE_NAME_PATTERNS[i].value)) {
            return true;
        }
    }
    return false;
}

bool FlockClassifier::matchesBleManufacturerId(uint16_t manufacturerId) const {
    return manufacturerId == FLOCK_BLE_MANUFACTURER_ID;
}

bool FlockClassifier::matchesBleServiceUuid(const char* uuid) const {
    if (!uuid || uuid[0] == '\0') {
        return false;
    }
#if defined(FLOCK_ENABLE_SERVICE_UUID_SIGNATURES)
    for (size_t i = 0; i < FLOCK_BLE_SERVICE_UUID_COUNT; ++i) {
        if (equalsCaseInsensitive(uuid, FLOCK_BLE_SERVICE_UUIDS[i])) {
            return true;
        }
    }
#else
    (void)uuid;
#endif
    return false;
}

bool FlockClassifier::isFlockSsidFormat(const char* ssid) const {
    if (!ssid || !containsCaseInsensitive(ssid, "Flock-")) {
        return false;
    }

    const size_t length = strlen(ssid);
    for (size_t start = 0; start + 6 <= length; ++start) {
        if ((ssid[start] == 'F' || ssid[start] == 'f') &&
            (ssid[start + 1] == 'L' || ssid[start + 1] == 'l') &&
            (ssid[start + 2] == 'O' || ssid[start + 2] == 'o') &&
            (ssid[start + 3] == 'C' || ssid[start + 3] == 'c') &&
            (ssid[start + 4] == 'K' || ssid[start + 4] == 'k') &&
            ssid[start + 5] == '-') {
            size_t hexCount = 0;
            for (size_t i = start + 6; i < length && isHex(ssid[i]); ++i) {
                hexCount += 1;
            }
            return hexCount >= 4 && hexCount <= 8;
        }
    }
    return false;
}

bool FlockClassifier::isStaticBleAddressLabel(const char* addressType) const {
    return equalsCaseInsensitive(addressType, "public") ||
        equalsCaseInsensitive(addressType, "random_static") ||
        equalsCaseInsensitive(addressType, "static");
}

bool FlockClassifier::extractSsidFromInformationElements(
    const uint8_t* ies,
    size_t length,
    char* ssidOut,
    size_t ssidOutSize,
    bool* ssidPresent,
    bool* wildcardSsid) {
    if (ssidOut && ssidOutSize > 0) {
        ssidOut[0] = '\0';
    }
    if (ssidPresent) {
        *ssidPresent = false;
    }
    if (wildcardSsid) {
        *wildcardSsid = false;
    }
    if (!ies) {
        return false;
    }

    size_t offset = 0;
    while (offset + 2 <= length) {
        const uint8_t id = ies[offset];
        const uint8_t elementLength = ies[offset + 1];
        offset += 2;
        if (offset + elementLength > length) {
            return false;
        }

        if (id == 0) {
            if (ssidPresent) {
                *ssidPresent = true;
            }
            if (elementLength == 0) {
                if (wildcardSsid) {
                    *wildcardSsid = true;
                }
                return true;
            }
            if (ssidOut && ssidOutSize > 0) {
                const size_t copyLength =
                    elementLength < (ssidOutSize - 1) ? elementLength : (ssidOutSize - 1);
                memcpy(ssidOut, ies + offset, copyLength);
                ssidOut[copyLength] = '\0';
            }
            return true;
        }
        offset += elementLength;
    }
    return true;
}

void FlockClassifier::applyOuiEvidence(
    const uint8_t mac[6],
    bool isBle,
    ClassificationResult& result
) const {
    const FlockOuiDatabase::MatchResult ouiMatch = FlockOuiDatabase::match(mac);
    if (!ouiMatch.matched) {
        return;
    }

    const uint8_t score = FlockOuiDatabase::ouiOnlyConfidenceScore(mac);
    addMethod(
        result,
        isBle ? DetectionMethod::KnownBleOui : DetectionMethod::KnownWifiOui,
        score
    );
}

void FlockClassifier::addMethod(ClassificationResult& result, DetectionMethod method, uint8_t score) const {
    const uint32_t bit = 1UL << static_cast<uint8_t>(method);
    if ((result.methodMask & bit) != 0) {
        return;
    }
    if (result.methodCount < MAX_DETECTION_METHODS) {
        result.methods[result.methodCount] = method;
        result.methodCount += 1;
    }
    result.methodMask |= bit;
    const uint16_t next = static_cast<uint16_t>(result.confidence) + score;
    result.confidence = next > 100 ? 100 : static_cast<uint8_t>(next);
}

bool FlockClassifier::containsCaseInsensitive(const char* haystack, const char* needle) {
    if (!haystack || !needle || needle[0] == '\0') {
        return false;
    }
    const size_t needleLength = strlen(needle);
    for (const char* cursor = haystack; *cursor; ++cursor) {
        size_t i = 0;
        while (i < needleLength && cursor[i] &&
               ((cursor[i] >= 'A' && cursor[i] <= 'Z') ? cursor[i] + 32 : cursor[i]) ==
               ((needle[i] >= 'A' && needle[i] <= 'Z') ? needle[i] + 32 : needle[i])) {
            i += 1;
        }
        if (i == needleLength) {
            return true;
        }
    }
    return false;
}

bool FlockClassifier::equalsCaseInsensitive(const char* left, const char* right) {
    if (!left || !right) {
        return false;
    }
    while (*left && *right) {
        const char l = (*left >= 'A' && *left <= 'Z') ? static_cast<char>(*left + 32) : *left;
        const char r = (*right >= 'A' && *right <= 'Z') ? static_cast<char>(*right + 32) : *right;
        if (l != r) {
            return false;
        }
        ++left;
        ++right;
    }
    return *left == '\0' && *right == '\0';
}

bool FlockClassifier::isHex(char c) {
    return (c >= '0' && c <= '9') ||
        (c >= 'a' && c <= 'f') ||
        (c >= 'A' && c <= 'F');
}

const char* FlockClassifier::labelForConfidence(uint8_t confidence) {
    if (confidence >= 85) {
        return "CONFIRMED";
    }
    if (confidence >= 70) {
        return "HIGH";
    }
    if (confidence >= 40) {
        return "LIKELY";
    }
    return "POSSIBLE";
}
