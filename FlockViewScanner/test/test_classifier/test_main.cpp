#include <unity.h>
#include "DetectionCache.h"
#include "FlockClassifier.h"
#include <string.h>

static FlockClassifier classifier;

static ScannerObservation wifiObservationWithMac(uint8_t a, uint8_t b, uint8_t c) {
    ScannerObservation observation;
    observation.protocol = ProtocolType::Wifi;
    observation.address[0] = a;
    observation.address[1] = b;
    observation.address[2] = c;
    observation.address[3] = 0x12;
    observation.address[4] = 0x34;
    observation.address[5] = 0x56;
    observation.rssi = -61;
    observation.channel = 6;
    observation.frequencyMHz = 2437;
    return observation;
}

static ScannerObservation bleObservationWithMac(uint8_t a, uint8_t b, uint8_t c) {
    ScannerObservation observation;
    observation.protocol = ProtocolType::Ble;
    observation.address[0] = a;
    observation.address[1] = b;
    observation.address[2] = c;
    observation.address[3] = 0x44;
    observation.address[4] = 0x55;
    observation.address[5] = 0x66;
    observation.rssi = -54;
    strncpy(observation.addressType, "public", sizeof(observation.addressType) - 1);
    return observation;
}

static bool hasMethod(const ClassificationResult& result, DetectionMethod method) {
    for (size_t i = 0; i < result.methodCount; ++i) {
        if (result.methods[i] == method) {
            return true;
        }
    }
    return false;
}

void test_known_wifi_oui_is_possible_only() {
    ScannerObservation observation = wifiObservationWithMac(0x70, 0xc9, 0x4e);
    const ClassificationResult result = classifier.classify(observation);
    TEST_ASSERT_TRUE(result.matched);
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::KnownWifiOui));
    TEST_ASSERT_EQUAL_UINT8(25, result.confidence);
    TEST_ASSERT_EQUAL_STRING("POSSIBLE", result.confidenceLabel);
}

void test_generic_espressif_oui_is_not_classified() {
    ScannerObservation observation = wifiObservationWithMac(0x10, 0x06, 0x1c);
    const ClassificationResult result = classifier.classify(observation);
    TEST_ASSERT_FALSE(result.matched);
}

void test_ssid_pattern_match() {
    ScannerObservation observation = wifiObservationWithMac(0x12, 0x34, 0x56);
    observation.ssidPresent = true;
    strncpy(observation.ssid, "city-flocksafety-service", sizeof(observation.ssid) - 1);
    const ClassificationResult result = classifier.classify(observation);
    TEST_ASSERT_TRUE(result.matched);
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::WifiSsidPattern));
    TEST_ASSERT_EQUAL_STRING("LIKELY", result.confidenceLabel);
}

void test_exact_ssid_format_scores_high() {
    ScannerObservation observation = wifiObservationWithMac(0x12, 0x34, 0x56);
    observation.ssidPresent = true;
    strncpy(observation.ssid, "Flock-1A2B", sizeof(observation.ssid) - 1);
    const ClassificationResult result = classifier.classify(observation);
    TEST_ASSERT_TRUE(result.matched);
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::WifiSsidFormat));
    TEST_ASSERT_EQUAL_UINT8(70, result.confidence);
    TEST_ASSERT_EQUAL_STRING("HIGH", result.confidenceLabel);
}

void test_wildcard_probe_plus_oui_scores_high_not_confirmed() {
    ScannerObservation observation = wifiObservationWithMac(0x82, 0x6b, 0xf2);
    observation.wifiSubtype = WifiFrameSubtype::ProbeRequest;
    observation.ssidPresent = true;
    observation.wildcardSsid = true;
    const ClassificationResult result = classifier.classify(observation);
    TEST_ASSERT_TRUE(result.matched);
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::KnownWifiOui));
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::WifiWildcardProbe));
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::MultipleSignals));
    TEST_ASSERT_EQUAL_UINT8(80, result.confidence);
    TEST_ASSERT_EQUAL_STRING("HIGH", result.confidenceLabel);
}

void test_ble_name_and_manufacturer_score_confirmed() {
    ScannerObservation observation = bleObservationWithMac(0x58, 0x8e, 0x81);
    strncpy(observation.bleName, "FS Ext Battery", sizeof(observation.bleName) - 1);
    observation.hasManufacturerId = true;
    observation.manufacturerId = 0x09C8;
    const ClassificationResult result = classifier.classify(observation);
    TEST_ASSERT_TRUE(result.matched);
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::KnownBleOui));
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::BleNamePattern));
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::BleManufacturerId));
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::BleStaticAddress));
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::MultipleSignals));
    TEST_ASSERT_EQUAL_STRING("CONFIRMED", result.confidenceLabel);
}

void test_ble_manufacturer_id_alone_is_likely() {
    ScannerObservation observation = bleObservationWithMac(0x12, 0x34, 0x56);
    observation.hasManufacturerId = true;
    observation.manufacturerId = 0x09C8;
    observation.addressType[0] = '\0';
    const ClassificationResult result = classifier.classify(observation);
    TEST_ASSERT_TRUE(result.matched);
    TEST_ASSERT_TRUE(hasMethod(result, DetectionMethod::BleManufacturerId));
    TEST_ASSERT_EQUAL_UINT8(60, result.confidence);
    TEST_ASSERT_EQUAL_STRING("LIKELY", result.confidenceLabel);
}

void test_no_flock_ble_service_uuid_is_invented() {
    TEST_ASSERT_FALSE(classifier.matchesBleServiceUuid("0000180a-0000-1000-8000-00805f9b34fb"));
}

void test_information_element_parser_extracts_ssid() {
    const uint8_t ies[] = {0x01, 0x01, 0x82, 0x00, 0x09, 'F', 'l', 'o', 'c', 'k', '-', '1', '2', 'A'};
    char ssid[33];
    bool present = false;
    bool wildcard = false;
    TEST_ASSERT_TRUE(FlockClassifier::extractSsidFromInformationElements(
        ies,
        sizeof(ies),
        ssid,
        sizeof(ssid),
        &present,
        &wildcard));
    TEST_ASSERT_TRUE(present);
    TEST_ASSERT_FALSE(wildcard);
    TEST_ASSERT_EQUAL_STRING("Flock-12A", ssid);
}

void test_information_element_parser_detects_wildcard_probe() {
    const uint8_t ies[] = {0x00, 0x00, 0x01, 0x01, 0x82};
    char ssid[33];
    bool present = false;
    bool wildcard = false;
    TEST_ASSERT_TRUE(FlockClassifier::extractSsidFromInformationElements(
        ies,
        sizeof(ies),
        ssid,
        sizeof(ssid),
        &present,
        &wildcard));
    TEST_ASSERT_TRUE(present);
    TEST_ASSERT_TRUE(wildcard);
    TEST_ASSERT_EQUAL_STRING("", ssid);
}

void test_malformed_information_element_is_rejected() {
    const uint8_t ies[] = {0x00, 0x04, 'F', 'l'};
    char ssid[33];
    bool present = false;
    bool wildcard = false;
    TEST_ASSERT_FALSE(FlockClassifier::extractSsidFromInformationElements(
        ies,
        sizeof(ies),
        ssid,
        sizeof(ssid),
        &present,
        &wildcard));
}

void test_short_invalid_frame_like_ie_buffer_is_safe() {
    const uint8_t ies[] = {0x00};
    char ssid[33];
    bool present = true;
    bool wildcard = true;
    TEST_ASSERT_TRUE(FlockClassifier::extractSsidFromInformationElements(
        ies,
        sizeof(ies),
        ssid,
        sizeof(ssid),
        &present,
        &wildcard));
    TEST_ASSERT_FALSE(present);
    TEST_ASSERT_FALSE(wildcard);
}

void setup() {
    UNITY_BEGIN();
    RUN_TEST(test_known_wifi_oui_is_possible_only);
    RUN_TEST(test_generic_espressif_oui_is_not_classified);
    RUN_TEST(test_ssid_pattern_match);
    RUN_TEST(test_exact_ssid_format_scores_high);
    RUN_TEST(test_wildcard_probe_plus_oui_scores_high_not_confirmed);
    RUN_TEST(test_ble_name_and_manufacturer_score_confirmed);
    RUN_TEST(test_ble_manufacturer_id_alone_is_likely);
    RUN_TEST(test_no_flock_ble_service_uuid_is_invented);
    RUN_TEST(test_information_element_parser_extracts_ssid);
    RUN_TEST(test_information_element_parser_detects_wildcard_probe);
    RUN_TEST(test_malformed_information_element_is_rejected);
    RUN_TEST(test_short_invalid_frame_like_ie_buffer_is_safe);
    UNITY_END();
}

void loop() {}

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;
    setup();
    return 0;
}
