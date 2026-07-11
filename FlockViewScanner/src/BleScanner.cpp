#include "BleScanner.h"
#include "ScannerConfig.h"

#ifndef UNIT_TEST

#include <string.h>
#include <stdio.h>

static uint32_t lastBleDropLogMs = 0;
static uint32_t lastBleDropCount = 0;

static void blePrettyLog(const char* level, const char* message) {
    if (!FLOCKVIEW_PRETTY_LOGS_ENABLED) {
        return;
    }
    Serial.print("# [");
    Serial.print(level);
    Serial.print("] ");
    Serial.println(message);
}

static void blePrettyLogf(const char* level, const char* format, uint32_t value) {
    if (!FLOCKVIEW_PRETTY_LOGS_ENABLED) {
        return;
    }
    char message[96];
    snprintf(message, sizeof(message), format, static_cast<unsigned long>(value));
    message[sizeof(message) - 1] = '\0';
    blePrettyLog(level, message);
}

FlockBleAdvertisedDeviceCallbacks::FlockBleAdvertisedDeviceCallbacks(BleScanner* owner)
    : _owner(owner) {}

void FlockBleAdvertisedDeviceCallbacks::onResult(NimBLEAdvertisedDevice* advertisedDevice) {
    if (_owner && advertisedDevice) {
        _owner->handleAdvertisedDevice(advertisedDevice);
    }
}

BleScanner::BleScanner()
    : _queue(nullptr),
      _scan(nullptr),
      _callbacks(this),
      _begun(false),
      _running(false),
      _windowEndMs(0),
      _advertisementsSeen(0),
      _droppedObservations(0),
      _queueHighWatermark(0) {}

bool BleScanner::begin(QueueHandle_t observationQueue) {
    _queue = observationQueue;
    blePrettyLog("BLE ", "Initializing NimBLE passive scanner");
    NimBLEDevice::init("");
    NimBLEDevice::setPower(ESP_PWR_LVL_N0);
    _scan = NimBLEDevice::getScan();
    if (!_scan) {
        return false;
    }
    _scan->setAdvertisedDeviceCallbacks(&_callbacks, true);
    _scan->setActiveScan(false);
    _scan->setInterval(160);
    _scan->setWindow(96);
    _scan->setDuplicateFilter(false);
    if (FLOCKVIEW_LOG_LEVEL >= 2) {
        blePrettyLog("BLE ", "Passive scan interval 100 ms, window 60 ms");
    }
    _begun = true;
    blePrettyLog("BLE ", "Passive scanner ready");
    return true;
}

bool BleScanner::startWindow(uint32_t windowMs) {
    if (!_begun || !_scan) {
        return false;
    }
    if (_running) {
        return true;
    }
    blePrettyLogf("BLE ", "Starting passive scan window: %lu ms", windowMs);
    _scan->clearResults();
    const uint32_t durationSeconds = (windowMs + 999U) / 1000U;
    _running = _scan->start(durationSeconds == 0 ? 1 : durationSeconds, nullptr, false);
    _windowEndMs = millis() + windowMs;
    if (_running) {
        blePrettyLog("BLE ", "Passive capture active");
    } else {
        blePrettyLog("WARN", "Unable to start BLE scan window");
    }
    return _running;
}

void BleScanner::stop() {
    if (!_scan) {
        return;
    }
    if (_running) {
        _scan->stop();
    }
    _scan->clearResults();
    _running = false;
    blePrettyLog("BLE ", "Passive capture stopped");
}

void BleScanner::loop(uint32_t nowMs) {
    if (_running && static_cast<int32_t>(nowMs - _windowEndMs) >= 0) {
        stop();
    }
    if (_droppedObservations != lastBleDropCount && nowMs - lastBleDropLogMs >= 5000) {
        blePrettyLogf("WARN", "BLE queue drops: %lu", _droppedObservations);
        lastBleDropCount = _droppedObservations;
        lastBleDropLogMs = nowMs;
    }
}

uint32_t BleScanner::advertisementsSeen() const {
    return _advertisementsSeen;
}

uint32_t BleScanner::droppedObservations() const {
    return _droppedObservations;
}

uint32_t BleScanner::queueHighWatermark() const {
    return _queueHighWatermark;
}

bool BleScanner::running() const {
    return _running;
}

void BleScanner::handleAdvertisedDevice(NimBLEAdvertisedDevice* advertisedDevice) {
    if (!_running || !advertisedDevice) {
        return;
    }

    _advertisementsSeen += 1;

    ScannerObservation observation;
    observation.protocol = ProtocolType::Ble;
    observation.seenMs = millis();
    observation.rssi = static_cast<int8_t>(advertisedDevice->getRSSI());
    copyAddress(advertisedDevice->getAddress(), observation.address);

    const uint8_t addressType = advertisedDevice->getAddressType();
    switch (addressType) {
    case BLE_ADDR_PUBLIC:
        strncpy(observation.addressType, "public", sizeof(observation.addressType) - 1);
        break;
    case BLE_ADDR_RANDOM:
        strncpy(observation.addressType, "random", sizeof(observation.addressType) - 1);
        break;
    case BLE_ADDR_PUBLIC_ID:
        strncpy(observation.addressType, "public_id", sizeof(observation.addressType) - 1);
        break;
    case BLE_ADDR_RANDOM_ID:
        strncpy(observation.addressType, "random_id", sizeof(observation.addressType) - 1);
        break;
    default:
        strncpy(observation.addressType, "unknown", sizeof(observation.addressType) - 1);
        break;
    }

    observation.connectable = advertisedDevice->isConnectable();
    observation.advertisementType = static_cast<uint8_t>(advertisedDevice->getAdvType());

    if (advertisedDevice->haveName()) {
        const std::string name = advertisedDevice->getName();
        strncpy(observation.bleName, name.c_str(), sizeof(observation.bleName) - 1);
    }

    if (advertisedDevice->haveTXPower()) {
        observation.hasTxPower = true;
        observation.txPower = static_cast<int8_t>(advertisedDevice->getTXPower());
    }

    if (advertisedDevice->haveManufacturerData()) {
        const std::string manufacturerData = advertisedDevice->getManufacturerData();
        if (manufacturerData.length() >= 2) {
            observation.hasManufacturerId = true;
            observation.manufacturerId =
                static_cast<uint16_t>(static_cast<uint8_t>(manufacturerData[0])) |
                (static_cast<uint16_t>(static_cast<uint8_t>(manufacturerData[1])) << 8);
        }
    }

    const int serviceCount = advertisedDevice->getServiceUUIDCount();
    for (int i = 0; i < serviceCount && observation.serviceUuidCount < MAX_SERVICE_UUIDS; ++i) {
        const std::string uuid = advertisedDevice->getServiceUUID(i).toString();
        strncpy(
            observation.serviceUuids[observation.serviceUuidCount],
            uuid.c_str(),
            MAX_SERVICE_UUID_LENGTH);
        observation.serviceUuids[observation.serviceUuidCount][MAX_SERVICE_UUID_LENGTH] = '\0';
        observation.serviceUuidCount += 1;
    }

    enqueueObservation(observation);
}

bool BleScanner::enqueueObservation(const ScannerObservation& observation) {
    if (!_queue) {
        _droppedObservations += 1;
        return false;
    }
    if (xQueueSend(_queue, &observation, 0) != pdTRUE) {
        _droppedObservations += 1;
        return false;
    }
    const UBaseType_t depth = uxQueueMessagesWaiting(_queue);
    if (depth > _queueHighWatermark) {
        _queueHighWatermark = depth;
    }
    return true;
}

void BleScanner::copyAddress(const NimBLEAddress& address, uint8_t out[6]) {
    const std::string text = address.toString();
    if (!parseMacString(text.c_str(), out)) {
        memset(out, 0, 6);
    }
}

#endif
