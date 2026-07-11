#include "BleScanner.h"
#include "DetectionCache.h"
#include "FlockClassifier.h"
#include "SerialProtocol.h"
#include "WifiScanner.h"
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <string.h>
#include <stdlib.h>

static QueueHandle_t observationQueue = nullptr;
static RuntimeConfig runtimeConfig;
static WifiScanner wifiScanner;
static BleScanner bleScanner;
static FlockClassifier classifier;
static DetectionCache detectionCache;
static SerialProtocol serialProtocol;

static ScannerMode scannerMode = ScannerMode::Dual;
static ScannerMode lastActiveMode = ScannerMode::Dual;
static ScanPhase scanPhase = ScanPhase::Idle;
static uint32_t phaseStartedMs = 0;
static uint32_t lastStatusMs = 0;

static uint32_t lastLowMemoryWarningMs = 0;

#ifdef LED_BUILTIN
static bool onboardLedState = false;
static uint32_t lastOnboardLedToggleMs = 0;

static void setOnboardLed(bool enabled) {
    onboardLedState = enabled;
    digitalWrite(LED_BUILTIN, enabled ? HIGH : LOW);
}

static void blinkOnboardLedBlocking(uint8_t count, uint16_t onMs, uint16_t offMs) {
    for (uint8_t index = 0; index < count; ++index) {
        setOnboardLed(true);
        delay(onMs);
        setOnboardLed(false);
        delay(offMs);
    }
}

static void updateOnboardLed(uint32_t nowMs) {
    const uint32_t intervalMs = scannerMode == ScannerMode::Stopped ? 1000U : 250U;
    if (nowMs - lastOnboardLedToggleMs < intervalMs) {
        return;
    }

    lastOnboardLedToggleMs = nowMs;
    setOnboardLed(!onboardLedState);
}
#endif

static bool equalsCommand(const char* command, const char* expected) {
    return strcmp(command, expected) == 0;
}

static bool startsWith(const char* command, const char* prefix) {
    return strncmp(command, prefix, strlen(prefix)) == 0;
}

static void stopRadios() {
    wifiScanner.stop();
    bleScanner.stop();
    scanPhase = ScanPhase::Idle;
}

static void startWifiPhase(uint32_t nowMs) {
    bleScanner.stop();
    if (!wifiScanner.running() && !wifiScanner.start()) {
        serialProtocol.emitError("wifi_scanner", "START_FAILED", "Unable to enter Wi-Fi promiscuous mode", nowMs);
    }
    scanPhase = ScanPhase::Wifi;
    phaseStartedMs = nowMs;
}

static void startBlePhase(uint32_t nowMs) {
    wifiScanner.stop();
    if (!bleScanner.startWindow(runtimeConfig.bleWindowMs)) {
        serialProtocol.emitError("ble_scanner", "START_FAILED", "Unable to start passive BLE scan window", nowMs);
    }
    scanPhase = ScanPhase::Ble;
    phaseStartedMs = nowMs;
}

static void applyScannerMode(uint32_t nowMs) {
    stopRadios();
    switch (scannerMode) {
    case ScannerMode::Dual:
    case ScannerMode::WifiOnly:
        startWifiPhase(nowMs);
        break;
    case ScannerMode::BleOnly:
        startBlePhase(nowMs);
        break;
    case ScannerMode::Stopped:
    default:
        scanPhase = ScanPhase::Idle;
        break;
    }
}

static ScannerRuntimeStats makeStats() {
    ScannerRuntimeStats stats;
    stats.mode = scannerMode;
    stats.phase = scanPhase;
    stats.wifiChannel = wifiScanner.currentChannel();
    stats.wifiFramesSeen = wifiScanner.framesSeen();
    stats.bleAdvertisementsSeen = bleScanner.advertisementsSeen();
    stats.queueDepth = observationQueue ? uxQueueMessagesWaiting(observationQueue) : 0;
    const uint32_t wifiHigh = wifiScanner.queueHighWatermark();
    const uint32_t bleHigh = bleScanner.queueHighWatermark();
    stats.queueHighWatermark = wifiHigh > bleHigh ? wifiHigh : bleHigh;
    stats.droppedObservations = wifiScanner.droppedObservations() + bleScanner.droppedObservations();
    stats.trackedDevices = detectionCache.trackedCount();
    stats.matchingDevices = detectionCache.matchingCount();
    return stats;
}

static void handleScheduler(uint32_t nowMs) {
    wifiScanner.loop(nowMs);
    bleScanner.loop(nowMs);

    switch (scannerMode) {
    case ScannerMode::Dual:
        if (scanPhase == ScanPhase::Idle) {
            startWifiPhase(nowMs);
        } else if (scanPhase == ScanPhase::Wifi && nowMs - phaseStartedMs >= runtimeConfig.wifiWindowMs) {
            startBlePhase(nowMs);
        } else if (scanPhase == ScanPhase::Ble && nowMs - phaseStartedMs >= runtimeConfig.bleWindowMs) {
            startWifiPhase(nowMs);
        }
        break;
    case ScannerMode::WifiOnly:
        if (scanPhase != ScanPhase::Wifi) {
            startWifiPhase(nowMs);
        }
        break;
    case ScannerMode::BleOnly:
        if (scanPhase != ScanPhase::Ble || !bleScanner.running()) {
            startBlePhase(nowMs);
        }
        break;
    case ScannerMode::Stopped:
    default:
        if (scanPhase != ScanPhase::Idle) {
            stopRadios();
        }
        break;
    }
}

static void processObservation(const ScannerObservation& observation, uint32_t nowMs) {
    if (observation.rssi < runtimeConfig.rssiMin) {
        return;
    }

    const ClassificationResult result = classifier.classify(observation);
    if (!result.matched) {
        return;
    }

    bool shouldEmit = false;
    DeviceRecord* record = detectionCache.update(observation, result, runtimeConfig, nowMs, &shouldEmit);
    if (record && shouldEmit) {
        serialProtocol.emitDetection(observation, result, *record, nowMs);
    }
}

static void drainObservationQueue(uint32_t nowMs) {
    if (!observationQueue) {
        return;
    }
    ScannerObservation observation;
    uint8_t processed = 0;
    while (processed < 32 && xQueueReceive(observationQueue, &observation, 0) == pdTRUE) {
        processObservation(observation, nowMs);
        processed += 1;
    }
}

static void handleCommand(const char* command, uint32_t nowMs) {
    if (equalsCommand(command, "PING")) {
        serialProtocol.emitCommandResponse("PING", true, "pong", nowMs);
        return;
    }
    if (equalsCommand(command, "STATUS")) {
        serialProtocol.emitStatus(makeStats(), nowMs);
        serialProtocol.emitCommandResponse("STATUS", true, "status emitted", nowMs);
        return;
    }
    if (equalsCommand(command, "START")) {
        if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
            serialProtocol.log(SerialLogLevel::Command, "START received");
        }
        if (scannerMode == ScannerMode::Stopped) {
            scannerMode = lastActiveMode == ScannerMode::Stopped ? ScannerMode::Dual : lastActiveMode;
        }

        applyScannerMode(nowMs);

        serialProtocol.emitCommandResponse("START", true, "scanner started", nowMs);
        serialProtocol.emitStatus(makeStats(), nowMs);
        if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
            serialProtocol.log(SerialLogLevel::Scan, "Scanner started");
        }
        return;
    }
    if (equalsCommand(command, "STOP")) {
        if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
            serialProtocol.log(SerialLogLevel::Command, "STOP received");
        }
        if (scannerMode != ScannerMode::Stopped) {
            lastActiveMode = scannerMode;
        }

        scannerMode = ScannerMode::Stopped;
        stopRadios();

        if (observationQueue) {
            xQueueReset(observationQueue);
        }

        serialProtocol.emitCommandResponse("STOP", true, "scanner stopped", nowMs);
        serialProtocol.emitStatus(makeStats(), nowMs);
        if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
            serialProtocol.log(SerialLogLevel::Scan, "Scanner stopped");
        }
        return;
    }
    if (equalsCommand(command, "MODE DUAL")) {
        if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
            serialProtocol.log(SerialLogLevel::Mode, "Dual mode selected");
        }
        scannerMode = ScannerMode::Dual;
        lastActiveMode = scannerMode;
        applyScannerMode(nowMs);
        serialProtocol.emitCommandResponse("MODE DUAL", true, "mode set to dual", nowMs);
        return;
    }
    if (equalsCommand(command, "MODE WIFI")) {
        if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
            serialProtocol.log(SerialLogLevel::Mode, "Wi-Fi-only mode selected");
        }
        scannerMode = ScannerMode::WifiOnly;
        lastActiveMode = scannerMode;
        applyScannerMode(nowMs);
        serialProtocol.emitCommandResponse("MODE WIFI", true, "mode set to wifi", nowMs);
        return;
    }
    if (equalsCommand(command, "MODE BLE")) {
        if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
            serialProtocol.log(SerialLogLevel::Mode, "BLE-only mode selected");
        }
        scannerMode = ScannerMode::BleOnly;
        lastActiveMode = scannerMode;
        applyScannerMode(nowMs);
        serialProtocol.emitCommandResponse("MODE BLE", true, "mode set to ble", nowMs);
        return;
    }
    if (equalsCommand(command, "CLEAR")) {
        if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
            serialProtocol.log(SerialLogLevel::Command, "Clearing current detection session");
        }
        detectionCache.clear();
        if (observationQueue) {
            xQueueReset(observationQueue);
        }
        serialProtocol.emitCommandResponse("CLEAR", true, "current session cleared", nowMs);
        return;
    }
    if (startsWith(command, "SET WIFI DWELL ")) {
        const long value = atol(command + strlen("SET WIFI DWELL "));
        if (value >= 50 && value <= 10000) {
            runtimeConfig.wifiDwellMs = static_cast<uint32_t>(value);
            wifiScanner.setDwellMs(runtimeConfig.wifiDwellMs);
            serialProtocol.emitCommandResponse("SET WIFI DWELL", true, "wifi dwell updated", nowMs);
        } else {
            serialProtocol.emitCommandResponse("SET WIFI DWELL", false, "value must be 50..10000 ms", nowMs);
        }
        return;
    }
    if (startsWith(command, "SET BLE WINDOW ")) {
        const long value = atol(command + strlen("SET BLE WINDOW "));
        if (value >= 500 && value <= 30000) {
            runtimeConfig.bleWindowMs = static_cast<uint32_t>(value);
            serialProtocol.emitCommandResponse("SET BLE WINDOW", true, "ble window updated", nowMs);
        } else {
            serialProtocol.emitCommandResponse("SET BLE WINDOW", false, "value must be 500..30000 ms", nowMs);
        }
        return;
    }
    if (startsWith(command, "SET RSSI MIN ")) {
        const long value = atol(command + strlen("SET RSSI MIN "));
        if (value >= -127 && value <= 0) {
            runtimeConfig.rssiMin = static_cast<int8_t>(value);
            serialProtocol.emitCommandResponse("SET RSSI MIN", true, "minimum RSSI updated", nowMs);
        } else {
            serialProtocol.emitCommandResponse("SET RSSI MIN", false, "value must be -127..0 dBm", nowMs);
        }
        return;
    }
    if (equalsCommand(command, "SET DEBUG ON")) {
        runtimeConfig.debugEnabled = true;
        serialProtocol.emitCommandResponse("SET DEBUG ON", true, "debug enabled", nowMs);
        return;
    }
    if (equalsCommand(command, "SET DEBUG OFF")) {
        runtimeConfig.debugEnabled = false;
        serialProtocol.emitCommandResponse("SET DEBUG OFF", true, "debug disabled", nowMs);
        return;
    }

    serialProtocol.emitCommandResponse(command, false, "unknown command", nowMs);
}

void setup() {
    serialProtocol.begin(FLOCKVIEW_SERIAL_BAUD);
#ifdef LED_BUILTIN
    pinMode(LED_BUILTIN, OUTPUT);
    setOnboardLed(false);
    blinkOnboardLedBlocking(3, 90, 90);
#endif
    delay(150);
    if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
        serialProtocol.printBootBanner();
        serialProtocol.log(SerialLogLevel::Boot, "Serial interface initialized");
    }
    serialProtocol.emitBoot(0);

    if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
        serialProtocol.log(SerialLogLevel::Boot, "Creating observation queue");
    }
    observationQueue = xQueueCreate(SCANNER_OBSERVATION_QUEUE_LENGTH, sizeof(ScannerObservation));
    if (!observationQueue) {
        serialProtocol.emitError("main", "QUEUE_CREATE_FAILED", "Unable to allocate observation queue", millis());
        scannerMode = ScannerMode::Stopped;
        return;
    }
    if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
        serialProtocol.log(SerialLogLevel::Success, "Observation queue ready");
        serialProtocol.log(SerialLogLevel::Boot, "Initializing Wi-Fi scanner");
    }

    if (!wifiScanner.begin(observationQueue)) {
        serialProtocol.emitError("wifi_scanner", "INIT_FAILED", "Wi-Fi scanner initialization failed", millis());
    }
    if (FLOCKVIEW_PRETTY_LOGS_ENABLED && wifiScanner.running()) {
        serialProtocol.log(SerialLogLevel::Success, "Wi-Fi scanner initialized");
    }
    wifiScanner.setDwellMs(runtimeConfig.wifiDwellMs);

    if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
        serialProtocol.log(SerialLogLevel::Boot, "Initializing BLE scanner");
    }
    if (!bleScanner.begin(observationQueue)) {
        serialProtocol.emitError("ble_scanner", "INIT_FAILED", "BLE scanner initialization failed", millis());
    }
    if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
        serialProtocol.log(SerialLogLevel::Success, "BLE scanner initialized");
    }

    applyScannerMode(millis());
    if (FLOCKVIEW_PRETTY_LOGS_ENABLED) {
        serialProtocol.log(SerialLogLevel::Scan, "Dual scanning active");
        serialProtocol.log(SerialLogLevel::Ready, "FlockView scanner is ready");
    }
}

void loop() {
#ifdef LED_BUILTIN
    updateOnboardLed(millis());
#endif
    const uint32_t nowMs = millis();

    char command[96];
    if (serialProtocol.readCommand(command, sizeof(command))) {
        handleCommand(command, nowMs);
    }

    handleScheduler(nowMs);
    drainObservationQueue(nowMs);

    if (nowMs - lastStatusMs >= DEFAULT_STATUS_INTERVAL_MS) {
        serialProtocol.emitStatus(makeStats(), nowMs);
        lastStatusMs = nowMs;
    }

    if (ESP.getFreeHeap() < 30000 && nowMs - lastLowMemoryWarningMs >= 30000) {
        serialProtocol.emitError("system", "LOW_MEMORY", "Free heap below 30000 bytes", nowMs);
        lastLowMemoryWarningMs = nowMs;
    }

    delay(5);
}
