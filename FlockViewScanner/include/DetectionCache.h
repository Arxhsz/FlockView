#pragma once

#include "RssiTracker.h"
#include "ScannerTypes.h"

class DetectionCache {
public:
    DetectionCache();

    void clear();
    DeviceRecord* update(
        const ScannerObservation& observation,
        const ClassificationResult& classification,
        const RuntimeConfig& config,
        uint32_t nowMs,
        bool* shouldEmit);

    size_t trackedCount() const;
    size_t matchingCount() const;
    const DeviceRecord* records() const;

private:
    DeviceRecord _records[MAX_TRACKED_DEVICES];
    RssiTracker _rssiTracker;

    DeviceRecord* findRecord(ProtocolType protocol, const uint8_t address[6]);
    DeviceRecord* allocateRecord(ProtocolType protocol, const uint8_t address[6], uint32_t nowMs);
    bool shouldEmitRecord(const DeviceRecord& record, const ClassificationResult& classification, int8_t currentRssi, Proximity proximity, uint32_t nowMs, const RuntimeConfig& config) const;
};
