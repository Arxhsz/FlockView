import XCTest
@testable import FlockView

final class NativeScannerClassifierTests: XCTestCase {
    func testWiFiOuiOnlyMatchStaysPossible() {
        let result = FlockDeviceClassifier().classifyWiFi(
            macAddress: "70:C9:4E:12:34:56",
            ssid: nil
        )

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.confidence, 20)
        XCTAssertEqual(result.confidenceLabel, .possible)
        XCTAssertEqual(result.detectionMethods, ["known_wifi_oui"])
    }

    func testWiFiOuiAndSSIDPatternPromoteToHighWithMultipleSignals() {
        let result = FlockDeviceClassifier().classifyWiFi(
            macAddress: "82:6B:F2:12:34:56",
            ssid: "FlockOS-Field"
        )

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.confidence, 95)
        XCTAssertEqual(result.confidenceLabel, .confirmed)
        XCTAssertEqual(result.detectionMethods, ["known_wifi_oui", "wifi_ssid_pattern", "multiple_signals"])
    }

    func testFlockSSIDFormatMatchesFirmwareRule() {
        let result = FlockDeviceClassifier().classifyWiFi(
            macAddress: "12:34:56:78:9A:BC",
            ssid: "Flock-1A2B"
        )

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.confidence, 70)
        XCTAssertEqual(result.confidenceLabel, .high)
        XCTAssertEqual(result.detectionMethods, ["wifi_ssid_format"])
    }

    func testBLEManufacturerAndNamePromoteToHighWithMultipleSignals() {
        let result = FlockDeviceClassifier().classifyBLE(
            displayAddress: "CB-12345678",
            name: "FS Ext Battery",
            manufacturerID: FlockDeviceClassifier.bleManufacturerID,
            serviceUUIDs: [],
            addressType: nil
        )

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.confidence, 100)
        XCTAssertEqual(result.confidenceLabel, .confirmed)
        XCTAssertEqual(result.detectionMethods, ["ble_name_pattern", "ble_manufacturer_id", "multiple_signals"])
    }

    func testSupplementalESP32OUIIsAvailableToNativeClassifier() {
        let result = FlockDeviceClassifier().classifyWiFi(
            macAddress: "B4:1E:52:AA:BB:CC",
            ssid: nil
        )

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.confidence, 35)
        XCTAssertEqual(result.detectionMethods, ["known_wifi_oui"])
    }
}
