import XCTest
@testable import FlockView

final class ScannerIntegrationTests: XCTestCase {
    func testFragmentedLineAssembly() {
        let decoder = SerialLineDecoder(maximumLineLength: 128)

        XCTAssertEqual(decoder.append(Data(#"{"event":"ping""#.utf8)), [String]())
        XCTAssertEqual(decoder.append(Data(#"}"#.utf8)), [String]())
        XCTAssertEqual(decoder.append(Data("\n".utf8)), [#"{"event":"ping"}"#])
    }

    func testMultipleJSONLinesAndCRLFInOneChunk() {
        let decoder = SerialLineDecoder(maximumLineLength: 128)
        let lines = decoder.append(Data("one\r\ntwo\n\nthree\r\n".utf8))

        XCTAssertEqual(lines, ["one", "two", "three"])
    }

    func testOversizedLineRecovery() {
        let decoder = SerialLineDecoder(maximumLineLength: 4)

        XCTAssertEqual(decoder.append(Data("abcdef".utf8)), [String]())
        XCTAssertTrue(decoder.didDiscardOversizedLine)
        XCTAssertEqual(decoder.append(Data("\nok\n".utf8)), ["ok"])
    }

    func testBootEventDecoding() throws {
        let event = try ScannerEventDecoder().decode(line: Self.bootJSON)

        guard case .boot(let boot, _) = event else {
            return XCTFail("Expected boot event")
        }

        XCTAssertEqual(boot.firmware, "FlockViewScanner")
        XCTAssertEqual(boot.firmwareVersion, "0.1.0")
        XCTAssertTrue(boot.passiveOnly)
        XCTAssertEqual(boot.wifiBands, ["2.4GHz"])
    }

    func testDetectionEventSnakeCaseMapping() throws {
        let event = try ScannerEventDecoder().decode(line: Self.detectionJSON)

        guard case .detection(let observation) = event else {
            return XCTFail("Expected detection event")
        }

        XCTAssertEqual(observation.schemaVersion, 1)
        XCTAssertEqual(observation.protocolType, .wifi)
        XCTAssertEqual(observation.deviceID, "wifi:70:C9:4E:12:34:56")
        XCTAssertEqual(observation.frequencyMHz, 2437)
        XCTAssertEqual(observation.smoothedRSSI, -63.4)
        XCTAssertEqual(observation.confidenceLabel, .high)
        XCTAssertEqual(observation.detectionMethods, ["known_wifi_oui", "wifi_wildcard_probe", "multiple_signals"])
        XCTAssertTrue(observation.isSupportedDetection)
    }

    func testStatusEventDecoding() throws {
        let event = try ScannerEventDecoder().decode(line: Self.statusJSON)

        guard case .status(let status, _) = event else {
            return XCTFail("Expected status event")
        }

        XCTAssertEqual(status.state, "scanning")
        XCTAssertEqual(status.mode, .dual)
        XCTAssertEqual(status.phase, "wifi")
        XCTAssertEqual(status.wifiChannel, 6)
        XCTAssertEqual(status.droppedObservations, 2)
        XCTAssertEqual(status.bleScanState, .waiting)
    }

    func testCommandResponseUsesFirmwareOKField() throws {
        let event = try ScannerEventDecoder().decode(line: Self.commandResponseJSON)

        guard case .commandResponse(let response, _) = event else {
            return XCTFail("Expected command response")
        }

        XCTAssertEqual(response.command, "PING")
        XCTAssertTrue(response.ok)
    }

    func testUnknownEventDoesNotBecomeDetection() throws {
        let event = try ScannerEventDecoder().decode(line: #"{"schema_version":1,"event":"future_event","uptime_ms":42}"#)

        guard case .unknown = event else {
            return XCTFail("Expected unknown event")
        }
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try ScannerEventDecoder().decode(line: #"{"schema_version":1"#))
    }

    func testCameraAggregationPreservesNoteAndUpdatesRSSIHistory() throws {
        var camera = CameraDetection.makeMockDetections(now: Date(timeIntervalSince1970: 1_000)).first!
        camera.note = "watch northbound lane"
        let timestamp = Date(timeIntervalSince1970: 1_050)
        let observation = ScannerObservation(
            protocolType: .wifi,
            deviceID: "wifi:98:3b:16:7a:2c:1d",
            macAddress: "98:3B:16:7A:2C:1D",
            channel: 11,
            frequencyMHz: 2462,
            rssi: -66,
            smoothedRSSI: -64.5,
            peakRSSI: -45,
            averageRSSI: -60.2,
            rssiTrend: .falling,
            confidence: 88,
            confidenceLabel: .confirmed,
            detectionMethods: ["known_wifi_oui"],
            observationCount: 200,
            uptimeMilliseconds: 12_000,
            rawEvent: Self.detectionJSON
        )

        camera.applyObservation(observation, at: timestamp)

        XCTAssertEqual(camera.note, "watch northbound lane")
        XCTAssertEqual(camera.rssi, -66)
        XCTAssertEqual(camera.channel, 11)
        XCTAssertEqual(camera.frequencyMHz, 2462)
        XCTAssertEqual(camera.observationCount, 200)
        XCTAssertEqual(camera.confidenceLabel, .confirmed)
        XCTAssertEqual(camera.rssiHistory.last?.timestamp, timestamp)
    }

    func testSetCommandResponseKeysMatchFirmwareFamilies() {
        XCTAssertEqual(ScannerCommand.setWiFiDwell(milliseconds: 350).responseCommand, "SET WIFI DWELL")
        XCTAssertEqual(ScannerCommand.setBLEWindow(milliseconds: 3000).responseCommand, "SET BLE WINDOW")
        XCTAssertEqual(ScannerCommand.setMinimumRSSI(-95).responseCommand, "SET RSSI MIN")
    }

    func testCommandTimeout() async {
        let queue = ScannerCommandQueue()

        do {
            _ = try await queue.perform(.ping, timeoutNanoseconds: 1_000_000) {}
            XCTFail("Expected timeout")
        } catch ScannerTransportError.commandTimeout(let command) {
            XCTAssertEqual(command, "PING")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static let bootJSON = #"{"schema_version":1,"event":"boot","firmware":"FlockViewScanner","firmware_version":"0.1.0","board":"esp32-wroom-32","passive_only":true,"wifi_bands":["2.4GHz"],"ble_supported":true,"uptime_ms":0}"#

    private static let detectionJSON = #"{"schema_version":1,"event":"detection","vendor":"Flock Safety","device_type":"camera","protocol":"wifi","device_id":"wifi:70:C9:4E:12:34:56","mac_address":"70:C9:4E:12:34:56","bssid":"11:22:33:44:55:66","ssid":"","frame_subtype":"probe_request","channel":6,"frequency_mhz":2437,"rssi":-61,"smoothed_rssi":-63.4,"peak_rssi":-55,"average_rssi":-66.2,"proximity":"medium","rssi_trend":"rising","confidence":80,"confidence_label":"HIGH","detection_methods":["known_wifi_oui","wifi_wildcard_probe","multiple_signals"],"observation_count":14,"first_seen_ms":12420,"last_seen_ms":184392,"uptime_ms":184392}"#

    private static let statusJSON = #"{"schema_version":1,"event":"scanner_status","state":"scanning","mode":"dual","phase":"wifi","wifi_channel":6,"wifi_frames_seen":15420,"ble_advertisements_seen":942,"queue_depth":3,"queue_high_watermark":18,"dropped_observations":2,"tracked_devices":16,"matching_devices":3,"free_heap":161240,"uptime_ms":184392}"#

    private static let commandResponseJSON = #"{"schema_version":1,"event":"command_response","command":"PING","ok":true,"message":"pong","uptime_ms":184392}"#
}
