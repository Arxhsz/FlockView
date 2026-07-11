import XCTest
@testable import FlockView

final class ScannerBehaviorTests: XCTestCase {
    @MainActor
    func testCameraExpirationRetainsSessionMetadata() async throws {
        let settings = AppSettings()
        settings.activeDetectionTimeout = 15
        let viewModel = ScannerViewModel(transport: MockScannerTransport(settings: settings), settings: settings)
        let camera = CameraDetection.makeMockDetections().first!
        viewModel.cameras = [camera]

        let cameraID = camera.id

        viewModel.toggleMarked(cameraID: cameraID)
        viewModel.saveNote(cameraID: cameraID, note: "keep me")

        if let index = viewModel.cameras.firstIndex(where: { $0.id == cameraID }) {
            viewModel.cameras[index].lastSeen = Date().addingTimeInterval(-20)
        }

        viewModel.performExpiryCheck()

        XCTAssertNil(viewModel.cameras.first(where: { $0.id == cameraID }))
        XCTAssertEqual(viewModel.exportCameras.first(where: { $0.id == cameraID })?.note, "keep me")
        XCTAssertEqual(viewModel.exportCameras.first(where: { $0.id == cameraID })?.marked, true)
    }

    @MainActor
    func testMarkedCameraUsesSharedModelState() {
        let settings = AppSettings()
        let viewModel = ScannerViewModel(transport: MockScannerTransport(settings: settings), settings: settings)
        let camera = CameraDetection.makeMockDetections().first!
        viewModel.cameras = [camera]
        viewModel.toggleMarked(cameraID: camera.id)

        XCTAssertTrue(viewModel.cameras.first?.marked == true)
        XCTAssertTrue(viewModel.visibleCameras.first?.marked == true)
    }

    @MainActor
    func testNoteSaveUpdatesRowState() {
        let settings = AppSettings()
        let viewModel = ScannerViewModel(transport: MockScannerTransport(settings: settings), settings: settings)
        let camera = CameraDetection.makeMockDetections().first!
        viewModel.cameras = [camera]

        viewModel.saveNote(cameraID: camera.id, note: "Field observation")

        XCTAssertEqual(viewModel.visibleCameras.first?.note, "Field observation")
        XCTAssertFalse(viewModel.visibleCameras.first?.note.isEmpty ?? true)
    }

    func testHigherPriorityCommandJumpsAheadInBacklog() async {
        let queue = ScannerCommandQueue()
        var order: [String] = []
        let lock = NSLock()

        let blockTask = Task {
            _ = try? await queue.perform(.start, timeoutNanoseconds: 400_000_000) {
                lock.lock()
                order.append("START")
                lock.unlock()
            }
        }

        try? await Task.sleep(nanoseconds: 15_000_000)

        let pingTask = Task {
            _ = try? await queue.perform(.ping, timeoutNanoseconds: 400_000_000) {
                lock.lock()
                order.append("PING")
                lock.unlock()
            }
        }

        let stopTask = Task {
            _ = try? await queue.perform(.stop, timeoutNanoseconds: 400_000_000) {
                lock.lock()
                order.append("STOP")
                lock.unlock()
            }
        }

        await blockTask.value
        await pingTask.value
        await stopTask.value
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(order.first, "START")
        XCTAssertEqual(order.dropFirst().first, "STOP")
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

    func testCommandResponsesIncludeNewlines() {
        XCTAssertTrue(ScannerCommand.start.serialString.hasSuffix("\n"))
        XCTAssertTrue(ScannerCommand.stop.serialString.hasSuffix("\n"))
        XCTAssertEqual(ScannerCommand.start.serialString, "START\n")
        XCTAssertEqual(ScannerCommand.stop.serialString, "STOP\n")
    }

    func testCancelAllClearsPendingCommands() async {
        let queue = ScannerCommandQueue()
        let task = Task {
            try await queue.perform(.start, timeoutNanoseconds: 500_000_000) {}
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        await queue.cancelAll()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch ScannerTransportError.connectionLost {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCameraAggregationPreservesNoteAndMarkedState() throws {
        var camera = CameraDetection.makeMockDetections(now: Date(timeIntervalSince1970: 1_000)).first!
        camera.note = "watch northbound lane"
        camera.marked = true
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
            rawEvent: #"{"schema_version":1,"event":"detection","vendor":"Flock Safety","device_type":"camera","protocol":"wifi","device_id":"wifi:98:3b:16:7a:2c:1d","mac_address":"98:3B:16:7A:2C:1D","rssi":-66,"confidence":88,"confidence_label":"CONFIRMED","detection_methods":["known_wifi_oui"],"observation_count":200,"uptime_ms":12000}"#
        )

        camera.applyObservation(observation, at: timestamp)

        XCTAssertEqual(camera.note, "watch northbound lane")
        XCTAssertTrue(camera.marked)
    }
}
