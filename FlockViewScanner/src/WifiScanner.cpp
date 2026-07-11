#include "WifiScanner.h"

#ifndef UNIT_TEST

#include "FlockClassifier.h"
#include "ScannerConfig.h"
#include <WiFi.h>
#include <string.h>
#include <stdio.h>

struct __attribute__((packed)) WifiMacHeader {
    uint16_t frameControl;
    uint16_t duration;
    uint8_t addr1[6];
    uint8_t addr2[6];
    uint8_t addr3[6];
    uint16_t sequenceControl;
};

static constexpr uint8_t WIFI_CHANNELS[] = {1, 6, 11, 2, 3, 4, 5, 7, 8, 9, 10};
static constexpr size_t WIFI_CHANNEL_COUNT = sizeof(WIFI_CHANNELS) / sizeof(WIFI_CHANNELS[0]);

static uint32_t lastWifiDropLogMs = 0;
static uint32_t lastWifiDropCount = 0;

static void wifiPrettyLog(const char* level, const char* message) {
    if (!FLOCKVIEW_PRETTY_LOGS_ENABLED) {
        return;
    }
    Serial.print("# [");
    Serial.print(level);
    Serial.print("] ");
    Serial.println(message);
}

static void wifiPrettyLogf(const char* level, const char* format, uint32_t value) {
    if (!FLOCKVIEW_PRETTY_LOGS_ENABLED) {
        return;
    }
    char message[96];
    snprintf(message, sizeof(message), format, static_cast<unsigned long>(value));
    message[sizeof(message) - 1] = '\0';
    wifiPrettyLog(level, message);
}

WifiScanner* WifiScanner::_instance = nullptr;

WifiScanner::WifiScanner()
    : _queue(nullptr),
      _begun(false),
      _running(false),
      _dwellMs(DEFAULT_WIFI_DWELL_MS),
      _lastHopMs(0),
      _channelIndex(0),
      _currentChannel(1),
      _framesSeen(0),
      _droppedObservations(0),
      _queueHighWatermark(0) {}

bool WifiScanner::begin(QueueHandle_t observationQueue) {
    _queue = observationQueue;
    _instance = this;

    wifiPrettyLog("WIFI", "Configuring station mode");
    WiFi.mode(WIFI_STA);
    WiFi.disconnect(true, true);

    wifi_init_config_t initConfig = WIFI_INIT_CONFIG_DEFAULT();
    esp_err_t err = esp_wifi_init(&initConfig);
    if (err != ESP_OK && err != ESP_ERR_WIFI_INIT_STATE) {
        return false;
    }

    esp_wifi_set_storage(WIFI_STORAGE_RAM);
    esp_wifi_set_mode(WIFI_MODE_STA);
    esp_wifi_start();

    wifi_promiscuous_filter_t filter = {};
    filter.filter_mask = WIFI_PROMIS_FILTER_MASK_MGMT;
    esp_wifi_set_promiscuous_filter(&filter);
    esp_wifi_set_promiscuous_rx_cb(&WifiScanner::promiscuousCallback);
    esp_wifi_set_channel(_currentChannel, WIFI_SECOND_CHAN_NONE);

    _begun = true;
    wifiPrettyLogf("WIFI", "Promiscuous scanner ready on channel %lu", _currentChannel);
    return true;
}

bool WifiScanner::start() {
    if (!_begun) {
        return false;
    }
    esp_wifi_set_channel(_currentChannel, WIFI_SECOND_CHAN_NONE);
    if (esp_wifi_set_promiscuous(true) != ESP_OK) {
        return false;
    }
    _running = true;
    _lastHopMs = millis();
    wifiPrettyLogf("WIFI", "Passive capture started on channel %lu", _currentChannel);
    return true;
}

void WifiScanner::stop() {
    if (!_begun) {
        return;
    }
    esp_wifi_set_promiscuous(false);
    _running = false;
    wifiPrettyLog("WIFI", "Passive capture stopped");
}

void WifiScanner::loop(uint32_t nowMs) {
    if (!_running) {
        return;
    }
    if (nowMs - _lastHopMs >= _dwellMs) {
        hopChannel();
        _lastHopMs = nowMs;
    }
    if (_droppedObservations != lastWifiDropCount && nowMs - lastWifiDropLogMs >= 5000) {
        wifiPrettyLogf("WARN", "Wi-Fi queue drops: %lu", _droppedObservations);
        lastWifiDropCount = _droppedObservations;
        lastWifiDropLogMs = nowMs;
    }
}

void WifiScanner::setDwellMs(uint32_t dwellMs) {
    _dwellMs = dwellMs < 50 ? 50 : dwellMs;
    wifiPrettyLogf("WIFI", "Channel dwell set to %lu ms", _dwellMs);
}

uint32_t WifiScanner::dwellMs() const {
    return _dwellMs;
}

uint8_t WifiScanner::currentChannel() const {
    return _currentChannel;
}

uint32_t WifiScanner::framesSeen() const {
    return _framesSeen;
}

uint32_t WifiScanner::droppedObservations() const {
    return _droppedObservations;
}

uint32_t WifiScanner::queueHighWatermark() const {
    return _queueHighWatermark;
}

bool WifiScanner::running() const {
    return _running;
}

void WifiScanner::promiscuousCallback(void* buffer, wifi_promiscuous_pkt_type_t type) {
    if (_instance && buffer) {
        _instance->handlePacket(static_cast<const wifi_promiscuous_pkt_t*>(buffer), type);
    }
}

void WifiScanner::handlePacket(const wifi_promiscuous_pkt_t* packet, wifi_promiscuous_pkt_type_t type) {
    if (!_running || type != WIFI_PKT_MGMT || !packet) {
        return;
    }

    const uint16_t sigLen = packet->rx_ctrl.sig_len;
    if (sigLen < sizeof(WifiMacHeader)) {
        return;
    }

    const uint8_t* payload = packet->payload;
    const WifiMacHeader* header = reinterpret_cast<const WifiMacHeader*>(payload);
    const uint16_t frameControl = header->frameControl;
    const uint8_t frameType = static_cast<uint8_t>((frameControl >> 2) & 0x03);
    const uint8_t frameSubtype = static_cast<uint8_t>((frameControl >> 4) & 0x0f);
    if (frameType != 0) {
        return;
    }

    WifiFrameSubtype subtype = WifiFrameSubtype::Unknown;
    size_t ieOffset = sizeof(WifiMacHeader);
    switch (frameSubtype) {
    case 0:
        subtype = WifiFrameSubtype::AssociationRequest;
        ieOffset += 4;
        break;
    case 2:
        subtype = WifiFrameSubtype::ReassociationRequest;
        ieOffset += 10;
        break;
    case 4:
        subtype = WifiFrameSubtype::ProbeRequest;
        break;
    case 5:
        subtype = WifiFrameSubtype::ProbeResponse;
        ieOffset += 12;
        break;
    case 8:
        subtype = WifiFrameSubtype::Beacon;
        ieOffset += 12;
        break;
    case 11:
        subtype = WifiFrameSubtype::Authentication;
        ieOffset += 6;
        break;
    case 13:
        subtype = WifiFrameSubtype::Action;
        break;
    default:
        return;
    }

    _framesSeen += 1;

    ScannerObservation observation;
    observation.protocol = ProtocolType::Wifi;
    observation.seenMs = millis();
    observation.rssi = static_cast<int8_t>(packet->rx_ctrl.rssi);
    observation.channel = packet->rx_ctrl.channel >= WIFI_MIN_CHANNEL &&
            packet->rx_ctrl.channel <= WIFI_MAX_CHANNEL
        ? packet->rx_ctrl.channel
        : _currentChannel;
    observation.frequencyMHz = wifiFrequencyForChannel(observation.channel);
    observation.wifiSubtype = subtype;
    observation.sequenceNumber = static_cast<uint16_t>(header->sequenceControl >> 4);
    memcpy(observation.destination, header->addr1, sizeof(observation.destination));
    memcpy(observation.address, header->addr2, sizeof(observation.address));
    memcpy(observation.bssid, header->addr3, sizeof(observation.bssid));

    if (!macIsZero(observation.address) && !macIsMulticast(observation.address)) {
        if (ieOffset <= sigLen) {
            const uint8_t* ies = payload + ieOffset;
            const size_t ieLength = sigLen - ieOffset;
            if (!FlockClassifier::extractSsidFromInformationElements(
                    ies,
                    ieLength,
                    observation.ssid,
                    sizeof(observation.ssid),
                    &observation.ssidPresent,
                    &observation.wildcardSsid)) {
                observation.ssid[0] = '\0';
                observation.ssidPresent = false;
                observation.wildcardSsid = false;
            }
        }
        enqueueObservation(observation);
    }
}

void WifiScanner::hopChannel() {
    _channelIndex = static_cast<uint8_t>((_channelIndex + 1) % WIFI_CHANNEL_COUNT);
    _currentChannel = WIFI_CHANNELS[_channelIndex];
    esp_wifi_set_channel(_currentChannel, WIFI_SECOND_CHAN_NONE);
    if (FLOCKVIEW_LOG_LEVEL >= 2) {
        wifiPrettyLogf("WIFI", "Listening on channel %lu", _currentChannel);
    }
}

bool WifiScanner::enqueueObservation(const ScannerObservation& observation) {
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

#endif
