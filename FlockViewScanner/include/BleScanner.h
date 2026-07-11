#pragma once

#ifndef UNIT_TEST

#include "ScannerTypes.h"
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

class BleScanner;

class FlockBleAdvertisedDeviceCallbacks : public NimBLEAdvertisedDeviceCallbacks {
public:
    explicit FlockBleAdvertisedDeviceCallbacks(BleScanner* owner);
    void onResult(NimBLEAdvertisedDevice* advertisedDevice) override;

private:
    BleScanner* _owner;
};

class BleScanner {
public:
    BleScanner();

    bool begin(QueueHandle_t observationQueue);
    bool startWindow(uint32_t windowMs);
    void stop();
    void loop(uint32_t nowMs);

    uint32_t advertisementsSeen() const;
    uint32_t droppedObservations() const;
    uint32_t queueHighWatermark() const;
    bool running() const;

    void handleAdvertisedDevice(NimBLEAdvertisedDevice* advertisedDevice);

private:
    friend class FlockBleAdvertisedDeviceCallbacks;

    QueueHandle_t _queue;
    NimBLEScan* _scan;
    FlockBleAdvertisedDeviceCallbacks _callbacks;
    bool _begun;
    bool _running;
    uint32_t _windowEndMs;
    volatile uint32_t _advertisementsSeen;
    volatile uint32_t _droppedObservations;
    volatile uint32_t _queueHighWatermark;

    bool enqueueObservation(const ScannerObservation& observation);
    static void copyAddress(const NimBLEAddress& address, uint8_t out[6]);
};

#endif
