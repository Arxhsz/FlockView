import Foundation
import Combine

enum TestDetectionEmissionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case single = "Single Camera"
    case multiple = "Multiple Cameras"

    var id: String { rawValue }
}

struct PersistedAppSettings: Codable {
    var scannerSource: ScannerSource = .hardware
    var autoReconnect: Bool = true
    var developerRecordedMode: Bool = false
    var matteTransparency: Double = 0.68
    var backgroundBlur: Double = 24
    var reduceMotion: Bool = false
    var compactCameraRows: Bool = true
    var closeThreshold: Int = -59
    var mediumThreshold: Int = -74
    var farThreshold: Int = -75
    var mockUpdateSpeed: Double = 3
    var pauseSimulation: Bool = false
    var activeDetectionTimeout: Double = 30
    var cameraDetectionNotifications: Bool = true
    var notificationSoundEnabled: Bool = true
    var detectionSoundEnabled: Bool = true
    var testDetectionInterval: Double = 10
    var testDetectionEmissionMode: TestDetectionEmissionMode = .single
    var testBatchCameraCount: Int = 3

    enum CodingKeys: String, CodingKey {
        case scannerSource
        case autoReconnect
        case developerRecordedMode
        case matteTransparency
        case backgroundBlur
        case reduceMotion
        case compactCameraRows
        case closeThreshold
        case mediumThreshold
        case farThreshold
        case mockUpdateSpeed
        case pauseSimulation
        case activeDetectionTimeout
        case cameraDetectionNotifications
        case notificationSoundEnabled
        case detectionSoundEnabled
        case testDetectionInterval
        case testDetectionEmissionMode
        case testBatchCameraCount
    }

    init() {}

    init(
        scannerSource: ScannerSource,
        autoReconnect: Bool,
        developerRecordedMode: Bool,
        matteTransparency: Double,
        backgroundBlur: Double,
        reduceMotion: Bool,
        compactCameraRows: Bool,
        closeThreshold: Int,
        mediumThreshold: Int,
        farThreshold: Int,
        mockUpdateSpeed: Double,
        pauseSimulation: Bool,
        activeDetectionTimeout: Double,
        cameraDetectionNotifications: Bool,
        notificationSoundEnabled: Bool,
        detectionSoundEnabled: Bool,
        testDetectionInterval: Double,
        testDetectionEmissionMode: TestDetectionEmissionMode,
        testBatchCameraCount: Int
    ) {
        self.scannerSource = scannerSource
        self.autoReconnect = autoReconnect
        self.developerRecordedMode = developerRecordedMode
        self.matteTransparency = matteTransparency
        self.backgroundBlur = backgroundBlur
        self.reduceMotion = reduceMotion
        self.compactCameraRows = compactCameraRows
        self.closeThreshold = closeThreshold
        self.mediumThreshold = mediumThreshold
        self.farThreshold = farThreshold
        self.mockUpdateSpeed = mockUpdateSpeed
        self.pauseSimulation = pauseSimulation
        self.activeDetectionTimeout = activeDetectionTimeout
        self.cameraDetectionNotifications = cameraDetectionNotifications
        self.notificationSoundEnabled = notificationSoundEnabled
        self.detectionSoundEnabled = detectionSoundEnabled
        self.testDetectionInterval = testDetectionInterval
        self.testDetectionEmissionMode = testDetectionEmissionMode
        self.testBatchCameraCount = testBatchCameraCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scannerSource = try container.decodeIfPresent(ScannerSource.self, forKey: .scannerSource) ?? .hardware
        autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        developerRecordedMode = try container.decodeIfPresent(Bool.self, forKey: .developerRecordedMode) ?? false
        matteTransparency = try container.decodeIfPresent(Double.self, forKey: .matteTransparency) ?? 0.68
        backgroundBlur = try container.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 24
        reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        compactCameraRows = try container.decodeIfPresent(Bool.self, forKey: .compactCameraRows) ?? true
        closeThreshold = try container.decodeIfPresent(Int.self, forKey: .closeThreshold) ?? -59
        mediumThreshold = try container.decodeIfPresent(Int.self, forKey: .mediumThreshold) ?? -74
        farThreshold = try container.decodeIfPresent(Int.self, forKey: .farThreshold) ?? -75
        mockUpdateSpeed = try container.decodeIfPresent(Double.self, forKey: .mockUpdateSpeed) ?? 3
        pauseSimulation = try container.decodeIfPresent(Bool.self, forKey: .pauseSimulation) ?? false
        activeDetectionTimeout = try container.decodeIfPresent(Double.self, forKey: .activeDetectionTimeout) ?? 30
        cameraDetectionNotifications = try container.decodeIfPresent(Bool.self, forKey: .cameraDetectionNotifications) ?? true
        notificationSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationSoundEnabled) ?? true
        detectionSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .detectionSoundEnabled) ?? true
        testDetectionInterval = try container.decodeIfPresent(Double.self, forKey: .testDetectionInterval) ?? 10
        testDetectionEmissionMode = try container.decodeIfPresent(TestDetectionEmissionMode.self, forKey: .testDetectionEmissionMode) ?? .single
        testBatchCameraCount = try container.decodeIfPresent(Int.self, forKey: .testBatchCameraCount) ?? 3
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaultsKey = "FlockView.AppSettings.v3"

    @Published var matteTransparency: Double { didSet { save() } }
    @Published var scannerSource: ScannerSource { didSet { save() } }
    @Published var autoReconnect: Bool { didSet { save() } }
    @Published var developerRecordedMode: Bool { didSet { save() } }
    @Published var backgroundBlur: Double { didSet { save() } }
    @Published var reduceMotion: Bool { didSet { save() } }
    @Published var compactCameraRows: Bool { didSet { save() } }
    @Published var closeThreshold: Int { didSet { save() } }
    @Published var mediumThreshold: Int { didSet { save() } }
    @Published var farThreshold: Int { didSet { save() } }
    @Published var mockUpdateSpeed: Double { didSet { save() } }
    @Published var pauseSimulation: Bool { didSet { save() } }
    @Published var activeDetectionTimeout: Double { didSet { save() } }
    @Published var testDetectionInterval: Double { didSet { save() } }
    @Published var testDetectionEmissionMode: TestDetectionEmissionMode { didSet { save() } }
    @Published var testBatchCameraCount: Int { didSet { save() } }
    @Published var notificationSoundEnabled: Bool { didSet { save() } }
    @Published var detectionSoundEnabled: Bool { didSet { save() } }
    @Published var cameraDetectionNotifications: Bool {
        didSet {
            save()
            NotificationService.shared.requestAuthorizationIfNeeded(enabled: cameraDetectionNotifications)
        }
    }

    init() {
        let persisted = Self.loadSettings(key: defaultsKey) ?? PersistedAppSettings()
        scannerSource = persisted.scannerSource == .test ? .hardware : persisted.scannerSource
        autoReconnect = persisted.autoReconnect
        developerRecordedMode = persisted.developerRecordedMode
        matteTransparency = persisted.matteTransparency
        backgroundBlur = persisted.backgroundBlur
        reduceMotion = persisted.reduceMotion
        compactCameraRows = persisted.compactCameraRows
        closeThreshold = persisted.closeThreshold
        mediumThreshold = persisted.mediumThreshold
        farThreshold = persisted.farThreshold
        mockUpdateSpeed = persisted.mockUpdateSpeed
        pauseSimulation = persisted.pauseSimulation
        activeDetectionTimeout = persisted.activeDetectionTimeout == 15 ? 30 : persisted.activeDetectionTimeout
        cameraDetectionNotifications = persisted.cameraDetectionNotifications
        notificationSoundEnabled = persisted.notificationSoundEnabled
        detectionSoundEnabled = persisted.detectionSoundEnabled
        testDetectionInterval = max(3, min(60, persisted.testDetectionInterval))
        testDetectionEmissionMode = persisted.testDetectionEmissionMode
        testBatchCameraCount = max(2, min(8, persisted.testBatchCameraCount))
    }

    func resetAppearance() {
        matteTransparency = 0.68
        backgroundBlur = 24
        reduceMotion = false
        compactCameraRows = true
    }

    func resetThresholds() {
        closeThreshold = -59
        mediumThreshold = -74
        farThreshold = -75
    }

    private func save() {
        let persisted = PersistedAppSettings(
            scannerSource: scannerSource == .test ? .hardware : scannerSource,
            autoReconnect: autoReconnect,
            developerRecordedMode: developerRecordedMode,
            matteTransparency: matteTransparency,
            backgroundBlur: backgroundBlur,
            reduceMotion: reduceMotion,
            compactCameraRows: compactCameraRows,
            closeThreshold: closeThreshold,
            mediumThreshold: mediumThreshold,
            farThreshold: farThreshold,
            mockUpdateSpeed: mockUpdateSpeed,
            pauseSimulation: pauseSimulation,
            activeDetectionTimeout: activeDetectionTimeout,
            cameraDetectionNotifications: cameraDetectionNotifications,
            notificationSoundEnabled: notificationSoundEnabled,
            detectionSoundEnabled: detectionSoundEnabled,
            testDetectionInterval: testDetectionInterval,
            testDetectionEmissionMode: testDetectionEmissionMode,
            testBatchCameraCount: testBatchCameraCount
        )

        guard let data = try? JSONEncoder().encode(persisted) else {
            return
        }

        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func loadSettings(key: String) -> PersistedAppSettings? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(PersistedAppSettings.self, from: data)
    }
}
