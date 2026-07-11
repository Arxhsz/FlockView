#include "DetectionCache.h"
#include <stdlib.h>
#include <string.h>

DetectionCache::DetectionCache() : _records{}, _rssiTracker(DEFAULT_RSSI_ALPHA) {}

void DetectionCache::clear() {
    memset(_records, 0, sizeof(_records));
}

DeviceRecord* DetectionCache::update(
    const ScannerObservation& observation,
    const ClassificationResult& classification,
    const RuntimeConfig& config,
    uint32_t nowMs,
    bool* shouldEmit) {
    if (shouldEmit) {
        *shouldEmit = false;
    }
    if (!classification.matched) {
        return nullptr;
    }

    _rssiTracker.setAlpha(config.rssiAlpha);
    DeviceRecord* record = findRecord(observation.protocol, observation.address);
    if (!record) {
        record = allocateRecord(observation.protocol, observation.address, nowMs);
    }
    if (!record) {
        return nullptr;
    }

    _rssiTracker.update(record->rssi, observation.rssi);
    record->lastSeenMs = nowMs;
    record->confidence = classification.confidence;
    strncpy(record->confidenceLabel, classification.confidenceLabel, sizeof(record->confidenceLabel) - 1);
    record->confidenceLabel[sizeof(record->confidenceLabel) - 1] = '\0';
    record->methodMask = classification.methodMask;
    record->proximity = _rssiTracker.proximityFor(
        observation.rssi,
        config.closeThreshold,
        config.mediumThreshold);

    const bool emit = shouldEmitRecord(
        *record,
        classification,
        observation.rssi,
        record->proximity,
        nowMs,
        config);
    record->markedForEmission = emit;
    if (emit) {
        record->lastEmissionMs = nowMs;
        record->lastEmittedRssi = observation.rssi;
        record->lastEmittedConfidence = classification.confidence;
        record->lastEmittedProximity = record->proximity;
    }
    if (shouldEmit) {
        *shouldEmit = emit;
    }
    return record;
}

size_t DetectionCache::trackedCount() const {
    size_t count = 0;
    for (const DeviceRecord& record : _records) {
        if (record.occupied) {
            count += 1;
        }
    }
    return count;
}

size_t DetectionCache::matchingCount() const {
    return trackedCount();
}

const DeviceRecord* DetectionCache::records() const {
    return _records;
}

DeviceRecord* DetectionCache::findRecord(ProtocolType protocol, const uint8_t address[6]) {
    for (DeviceRecord& record : _records) {
        if (record.occupied && record.protocol == protocol && macEquals(record.address, address)) {
            return &record;
        }
    }
    return nullptr;
}

DeviceRecord* DetectionCache::allocateRecord(ProtocolType protocol, const uint8_t address[6], uint32_t nowMs) {
    for (DeviceRecord& record : _records) {
        if (!record.occupied) {
            record = DeviceRecord{};
            record.occupied = true;
            record.protocol = protocol;
            memcpy(record.address, address, 6);
            record.firstSeenMs = nowMs;
            record.lastSeenMs = nowMs;
            record.proximity = Proximity::Far;
            record.lastEmittedProximity = Proximity::Far;
            return &record;
        }
    }
    return nullptr;
}

bool DetectionCache::shouldEmitRecord(
    const DeviceRecord& record,
    const ClassificationResult& classification,
    int8_t currentRssi,
    Proximity proximity,
    uint32_t nowMs,
    const RuntimeConfig& config) const {
    if (record.rssi.observationCount <= 1 || record.lastEmissionMs == 0) {
        return true;
    }
    if (classification.confidence != record.lastEmittedConfidence) {
        return true;
    }
    if (proximity != record.lastEmittedProximity) {
        return true;
    }
    if (abs(static_cast<int>(currentRssi) - static_cast<int>(record.lastEmittedRssi)) >= 5) {
        return true;
    }
    return (nowMs - record.lastEmissionMs) >= config.emitCooldownMs;
}
