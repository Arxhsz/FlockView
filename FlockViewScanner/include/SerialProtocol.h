#pragma once

#ifndef UNIT_TEST

#include "DetectionCache.h"
#include "ScannerTypes.h"
#include <Arduino.h>

struct ScannerRuntimeStats {
    ScannerMode mode = ScannerMode::Stopped;
    ScanPhase phase = ScanPhase::Idle;
    uint8_t wifiChannel = 1;
    uint32_t wifiFramesSeen = 0;
    uint32_t bleAdvertisementsSeen = 0;
    uint32_t queueDepth = 0;
    uint32_t queueHighWatermark = 0;
    uint32_t droppedObservations = 0;
    size_t trackedDevices = 0;
    size_t matchingDevices = 0;
};

enum class SerialLogLevel : uint8_t {
    Boot,
    Info,
    Success,
    Scan,
    Command,
    Mode,
    Match,
    Warning,
    Error,
    Ready
};

class SerialProtocol {
public:
    void begin(uint32_t baud);
    bool readCommand(char* out, size_t outSize);

    void printBootBanner();
    void log(SerialLogLevel level, const char* message);
    void logf(SerialLogLevel level, const char* format, ...);
    void logDivider();

    void emitBoot(uint32_t uptimeMs);
    void emitDetection(
        const ScannerObservation& observation,
        const ClassificationResult& classification,
        const DeviceRecord& record,
        uint32_t uptimeMs);
    void emitStatus(const ScannerRuntimeStats& stats, uint32_t uptimeMs);
    void emitError(const char* component, const char* code, const char* message, uint32_t uptimeMs);
    void emitCommandResponse(const char* command, bool ok, const char* message, uint32_t uptimeMs);
    void emitDebug(const char* component, const char* message, uint32_t uptimeMs);

private:
    static const char* logLevelLabel(SerialLogLevel level);
    char _commandBuffer[96] = {0};
    size_t _commandLength = 0;
};

#endif
