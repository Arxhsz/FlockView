#include <unity.h>
#include "DetectionCache.h"
#include "FlockClassifier.h"
#include "RssiTracker.h"
#include <string.h>

void test_rssi_smoothing_and_average() {
    RssiTracker tracker(0.35f);
    RssiState state;
    tracker.update(state, -70);
    tracker.update(state, -60);
    TEST_ASSERT_TRUE(state.initialized);
    TEST_ASSERT_EQUAL_INT8(-60, state.currentRssi);
    TEST_ASSERT_EQUAL_INT8(-60, state.peakRssi);
    TEST_ASSERT_EQUAL_INT8(-70, state.minimumRssi);
    TEST_ASSERT_FLOAT_WITHIN(0.05f, -66.5f, state.smoothedRssi);
    TEST_ASSERT_FLOAT_WITHIN(0.05f, -65.0f, state.averageRssi);
    TEST_ASSERT_EQUAL(RssiTrend::Rising, state.trend);
}

void test_rssi_trend_falling() {
    RssiTracker tracker(0.5f);
    RssiState state;
    tracker.update(state, -50);
    tracker.update(state, -70);
    TEST_ASSERT_EQUAL(RssiTrend::Falling, state.trend);
}

void test_proximity_thresholds() {
    RssiTracker tracker;
    TEST_ASSERT_EQUAL(Proximity::Close, tracker.proximityFor(-59, -59, -74));
    TEST_ASSERT_EQUAL(Proximity::Medium, tracker.proximityFor(-60, -59, -74));
    TEST_ASSERT_EQUAL(Proximity::Medium, tracker.proximityFor(-74, -59, -74));
    TEST_ASSERT_EQUAL(Proximity::Far, tracker.proximityFor(-75, -59, -74));
}

static ScannerObservation matchingObservation(int8_t rssi) {
    ScannerObservation observation;
    observation.protocol = ProtocolType::Wifi;
    observation.address[0] = 0x70;
    observation.address[1] = 0xc9;
    observation.address[2] = 0x4e;
    observation.address[3] = 0xaa;
    observation.address[4] = 0xbb;
    observation.address[5] = 0xcc;
    observation.wifiSubtype = WifiFrameSubtype::ProbeRequest;
    observation.ssidPresent = true;
    observation.wildcardSsid = true;
    observation.rssi = rssi;
    observation.channel = 6;
    observation.frequencyMHz = 2437;
    return observation;
}

void test_duplicate_suppression_cooldown_and_rssi_change() {
    RuntimeConfig config;
    DetectionCache cache;
    FlockClassifier classifier;

    ScannerObservation first = matchingObservation(-60);
    ClassificationResult firstResult = classifier.classify(first);
    bool shouldEmit = false;
    DeviceRecord* record = cache.update(first, firstResult, config, 1000, &shouldEmit);
    TEST_ASSERT_NOT_NULL(record);
    TEST_ASSERT_TRUE(shouldEmit);
    TEST_ASSERT_EQUAL_UINT32(1, record->rssi.observationCount);

    ScannerObservation second = matchingObservation(-61);
    ClassificationResult secondResult = classifier.classify(second);
    record = cache.update(second, secondResult, config, 2000, &shouldEmit);
    TEST_ASSERT_NOT_NULL(record);
    TEST_ASSERT_FALSE(shouldEmit);
    TEST_ASSERT_EQUAL_UINT32(2, record->rssi.observationCount);

    ScannerObservation third = matchingObservation(-55);
    ClassificationResult thirdResult = classifier.classify(third);
    record = cache.update(third, thirdResult, config, 2500, &shouldEmit);
    TEST_ASSERT_NOT_NULL(record);
    TEST_ASSERT_TRUE(shouldEmit);
    TEST_ASSERT_EQUAL_UINT32(3, record->rssi.observationCount);
}

void test_duplicate_suppression_emits_on_proximity_change() {
    RuntimeConfig config;
    DetectionCache cache;
    FlockClassifier classifier;

    ScannerObservation first = matchingObservation(-76);
    ClassificationResult firstResult = classifier.classify(first);
    bool shouldEmit = false;
    DeviceRecord* record = cache.update(first, firstResult, config, 1000, &shouldEmit);
    TEST_ASSERT_NOT_NULL(record);
    TEST_ASSERT_TRUE(shouldEmit);
    TEST_ASSERT_EQUAL(Proximity::Far, record->proximity);

    ScannerObservation second = matchingObservation(-70);
    ClassificationResult secondResult = classifier.classify(second);
    record = cache.update(second, secondResult, config, 1200, &shouldEmit);
    TEST_ASSERT_NOT_NULL(record);
    TEST_ASSERT_TRUE(shouldEmit);
    TEST_ASSERT_EQUAL(Proximity::Medium, record->proximity);
}

void setup() {
    UNITY_BEGIN();
    RUN_TEST(test_rssi_smoothing_and_average);
    RUN_TEST(test_rssi_trend_falling);
    RUN_TEST(test_proximity_thresholds);
    RUN_TEST(test_duplicate_suppression_cooldown_and_rssi_change);
    RUN_TEST(test_duplicate_suppression_emits_on_proximity_change);
    UNITY_END();
}

void loop() {}

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;
    setup();
    return 0;
}
