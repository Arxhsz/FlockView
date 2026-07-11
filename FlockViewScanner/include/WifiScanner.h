#pragma once

#ifndef UNIT_TEST

#include "ScannerTypes.h"
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <esp_wifi.h>

class WifiScanner {
public:
    WifiScanner();

    bool begin(QueueHandle_t observationQueue);
    bool start();
    void stop();
    void loop(uint32_t nowMs);

    void setDwellMs(uint32_t dwellMs);
    uint32_t dwellMs() const;
    uint8_t currentChannel() const;
    uint32_t framesSeen() const;
    uint32_t droppedObservations() const;
    uint32_t queueHighWatermark() const;
    bool running() const;

private:
    static WifiScanner* _instance;
    QueueHandle_t _queue;
    bool _begun;
    bool _running;
    uint32_t _dwellMs;
    uint32_t _lastHopMs;
    uint8_t _channelIndex;
    uint8_t _currentChannel;
    volatile uint32_t _framesSeen;
    volatile uint32_t _droppedObservations;
    volatile uint32_t _queueHighWatermark;

    static void promiscuousCallback(void* buffer, wifi_promiscuous_pkt_type_t type);
    void handlePacket(const wifi_promiscuous_pkt_t* packet, wifi_promiscuous_pkt_type_t type);
    void hopChannel();
    bool enqueueObservation(const ScannerObservation& observation);
};

#endif
