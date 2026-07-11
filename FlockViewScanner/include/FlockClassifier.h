#pragma once

#include "ScannerTypes.h"

class FlockClassifier {
public:
    ClassificationResult classify(const ScannerObservation& observation) const;

    bool matchesWifiOui(const uint8_t mac[6]) const;
    bool matchesBleOui(const uint8_t mac[6]) const;
    bool matchesWifiSsidPattern(const char* ssid) const;
    bool matchesBleNamePattern(const char* name) const;
    bool matchesBleManufacturerId(uint16_t manufacturerId) const;
    bool matchesBleServiceUuid(const char* uuid) const;
    bool isFlockSsidFormat(const char* ssid) const;
    bool isStaticBleAddressLabel(const char* addressType) const;

    static bool extractSsidFromInformationElements(
        const uint8_t* ies,
        size_t length,
        char* ssidOut,
        size_t ssidOutSize,
        bool* ssidPresent,
        bool* wildcardSsid);

private:
    void applyOuiEvidence(
        const uint8_t mac[6],
        bool isBle,
        ClassificationResult& result
    ) const;
    void addMethod(ClassificationResult& result, DetectionMethod method, uint8_t score) const;
    static bool containsCaseInsensitive(const char* haystack, const char* needle);
    static bool equalsCaseInsensitive(const char* left, const char* right);
    static bool isHex(char c);
    static const char* labelForConfidence(uint8_t confidence);
};
