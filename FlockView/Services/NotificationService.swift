import AppKit
import Darwin
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var pendingDetections: [PendingDetection] = []
    private var batchTask: Task<Void, Never>?
    private var pendingNotificationSoundEnabled = true
    private var lastDetectionSoundDate: Date?
    private var detectionSound: NSSound?
    private static let customSoundBaseName = "FlockViewDetectionV3"
    private static let customSoundFileName = "\(customSoundBaseName).wav"
    private let batchDelay: TimeInterval = 1
    private let detectionSoundCooldown: TimeInterval = 1
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    private override init() {
        super.init()
        center.delegate = self
        NSUserNotificationCenter.default.delegate = self
    }

    func requestAuthorizationIfNeeded(enabled: Bool) {
        guard enabled, !Self.isRunningTests else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            if await currentAuthorizationStatus() == .notDetermined {
                _ = await requestAuthorizationFromUser()
            }
        }
    }

    func notificationPermissionStatusText() async -> String {
        switch await currentAuthorizationStatus() {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Requested"
        case .provisional:
            return "Provisional"
        @unknown default:
            return "Unknown"
        }
    }

    func requestAuthorizationFromUser() async -> String {
        guard !Self.isRunningTests else {
            return "Skipped During Tests"
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        let currentStatus = await currentAuthorizationStatus()
        switch currentStatus {
        case .authorized, .provisional:
            return await notificationPermissionStatusText()
        case .denied:
            return "Denied"
        case .notDetermined:
            let result = await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error {
                        continuation.resume(returning: "Request Failed: \(error.localizedDescription)")
                    } else {
                        continuation.resume(returning: granted ? "Authorized" : "Denied")
                    }
                }
            }
            return result
        @unknown default:
            return "Unknown"
        }
    }

    func sendTestNotification(settings: AppSettings) async -> String {
        guard !Self.isRunningTests else {
            return "Skipped During Tests"
        }

        guard settings.cameraDetectionNotifications else {
            return "Notification toggle is off"
        }

        let status = await currentAuthorizationStatus()
        if status == .notDetermined {
            _ = await requestAuthorizationFromUser()
        }

        let updatedStatus = await currentAuthorizationStatus()
        guard updatedStatus == .authorized || updatedStatus == .provisional else {
            return updatedStatus == .denied ? "Notifications denied in macOS" : "Notifications are not enabled"
        }

        var camera = CameraDetection.makeSimulatedDetection(number: Int(Date().timeIntervalSince1970) % 500)
        camera.name = "FlockView Test Camera"
        camera.lastSeen = Date()
        camera.rssi = -54
        return await sendSingleDetection(
            PendingDetection(camera: camera, proximity: .close),
            soundEnabled: settings.notificationSoundEnabled,
            foregroundAllowed: true
        )
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func notifyNewCamera(_ camera: CameraDetection, settings: AppSettings) {
        guard !Self.isRunningTests else {
            return
        }

        let proximity = camera.proximity(
            closeThreshold: settings.closeThreshold,
            mediumThreshold: settings.mediumThreshold,
            farThreshold: settings.farThreshold
        )

        let appIsActive = NSApplication.shared.isActive
        playDetectionSoundIfNeeded(enabled: settings.detectionSoundEnabled && appIsActive)

        guard settings.cameraDetectionNotifications else {
            return
        }

        guard !appIsActive else {
            pendingDetections.removeAll()
            batchTask?.cancel()
            batchTask = nil
            return
        }

        requestAuthorizationIfNeeded(enabled: true)

        pendingDetections.append(PendingDetection(camera: camera, proximity: proximity))
        pendingNotificationSoundEnabled = settings.notificationSoundEnabled

        scheduleFlush(after: batchDelay)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.content.userInfo["foreground_allowed"] as? Bool == true {
            return [.banner, .list, .sound]
        }
        return []
    }

    private func flushPendingDetections() async {
        batchTask = nil

        guard !NSApplication.shared.isActive else {
            pendingDetections.removeAll()
            return
        }

        let detections = pendingDetections
        pendingDetections.removeAll()

        guard !detections.isEmpty else {
            return
        }

        if detections.count == 1, let detection = detections.first {
            _ = await sendSingleDetection(
                detection,
                soundEnabled: pendingNotificationSoundEnabled,
                foregroundAllowed: false
            )
        } else {
            _ = await sendMultipleDetections(detections, soundEnabled: pendingNotificationSoundEnabled)
        }
    }

    private func scheduleFlush(after seconds: TimeInterval) {
        guard batchTask == nil else {
            return
        }

        let delay = max(0.1, seconds)
        batchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.flushPendingDetections()
        }
    }

    private func playDetectionSoundIfNeeded(enabled: Bool) {
        guard enabled else {
            return
        }

        if let lastDetectionSoundDate,
           Date().timeIntervalSince(lastDetectionSoundDate) < detectionSoundCooldown {
            return
        }

        lastDetectionSoundDate = Date()
        if detectionSound == nil, let url = ensureCustomSoundFile() {
            detectionSound = NSSound(contentsOf: url, byReference: true)
        }
        let sound = detectionSound ?? NSSound(named: NSSound.Name("Ping"))
        sound?.stop()
        sound?.currentTime = 0
        sound?.play()
    }

    private func sendSingleDetection(
        _ detection: PendingDetection,
        soundEnabled: Bool,
        foregroundAllowed: Bool
    ) async -> String {
        let camera = detection.camera
        let content = UNMutableNotificationContent()
        content.title = camera.name
        content.subtitle = "\(camera.type.rawValue) • \(detection.proximity.rawValue)"
        content.body = "Detected at \(timeFormatter.string(from: camera.lastSeen)) • \(camera.protocolType.rawValue) • \(camera.rssi) dBm"
        content.sound = soundEnabled ? customNotificationSound() : nil
        content.threadIdentifier = "flockview-camera-detections"
        content.categoryIdentifier = "camera-detection"
        content.userInfo = [
            "device_id": camera.deviceID,
            "mac_address": camera.macAddress,
            "proximity": detection.proximity.rawValue,
            "foreground_allowed": foregroundAllowed
        ]

        if let attachment = makeProximityAttachment(for: detection.proximity) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: "camera-\(camera.id.uuidString)-\(Int(camera.lastSeen.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        return await add(request, fallback: LegacyNotificationPayload(
            title: content.title,
            subtitle: content.subtitle,
            body: content.body,
            soundEnabled: soundEnabled
        ))
    }

    private func sendMultipleDetections(_ detections: [PendingDetection], soundEnabled: Bool) async -> String {
        let strongest = strongestProximity(in: detections)
        let names = detections
            .prefix(3)
            .map { $0.camera.name }
            .joined(separator: ", ")
        let closeCount = detections.filter { $0.proximity == .close }.count
        let mediumCount = detections.filter { $0.proximity == .medium }.count
        let farCount = detections.filter { $0.proximity == .far }.count

        let content = UNMutableNotificationContent()
        content.title = "Multiple camera detections"
        content.subtitle = "\(detections.count) cameras • strongest \(strongest.rawValue)"
        content.body = "Detected at \(timeFormatter.string(from: Date())) • \(names)\(detections.count > 3 ? ", and \(detections.count - 3) more" : "") • Close \(closeCount), Medium \(mediumCount), Far \(farCount)"
        content.sound = soundEnabled ? customNotificationSound() : nil
        content.threadIdentifier = "flockview-camera-detections"
        content.categoryIdentifier = "camera-detection"
        content.userInfo = [
            "detection_count": detections.count,
            "proximity": strongest.rawValue
        ]

        if let attachment = makeProximityAttachment(for: strongest) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: "camera-batch-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        return await add(request, fallback: LegacyNotificationPayload(
            title: content.title,
            subtitle: content.subtitle,
            body: content.body,
            soundEnabled: soundEnabled
        ))
    }

    private func add(_ request: UNNotificationRequest, fallback: LegacyNotificationPayload) async -> String {
        let result = await withCheckedContinuation { continuation in
            center.add(request) { error in
                if let error {
                    continuation.resume(returning: "Notification failed: \(error.localizedDescription)")
                } else {
                    continuation.resume(returning: "Notification sent")
                }
            }
        }

        if result == "Notification sent" {
            return result
        }

        deliverLegacyNotification(fallback)
        return "\(result). Sent legacy fallback."
    }

    private func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func deliverLegacyNotification(_ payload: LegacyNotificationPayload) {
        let notification = NSUserNotification()
        notification.title = payload.title
        notification.subtitle = payload.subtitle
        notification.informativeText = payload.body
        _ = ensureCustomSoundFile()
        notification.soundName = payload.soundEnabled ? Self.customSoundBaseName : nil
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func customNotificationSound() -> UNNotificationSound {
        _ = ensureCustomSoundFile()
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: Self.customSoundFileName))
    }

    private func ensureCustomSoundFile() -> URL? {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
        let url = directory.appendingPathComponent(Self.customSoundFileName)

        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.detectionSoundWAVData().write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func strongestProximity(in detections: [PendingDetection]) -> ProximityLevel {
        if detections.contains(where: { $0.proximity == .close }) {
            return .close
        }
        if detections.contains(where: { $0.proximity == .medium }) {
            return .medium
        }
        return .far
    }

    private func makeProximityAttachment(for proximity: ProximityLevel) -> UNNotificationAttachment? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlockViewNotificationBadges", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("proximity-\(proximity.rawValue.lowercased()).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard let data = Self.badgePNGData(for: proximity) else {
                return nil
            }
            try? data.write(to: url, options: .atomic)
        }

        return try? UNNotificationAttachment(identifier: "proximity-\(proximity.rawValue.lowercased())", url: url)
    }

    private static func badgePNGData(for proximity: ProximityLevel) -> Data? {
        let size = NSSize(width: 360, height: 180)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        NSColor(calibratedWhite: 0.02, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28).fill()

        NSColor.white.withAlphaComponent(0.10).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 26, yRadius: 26)
        border.lineWidth = 2
        border.stroke()

        let color: NSColor
        let activeBars: Int
        switch proximity {
        case .close:
            color = NSColor(calibratedRed: 0.41, green: 0.87, blue: 0.31, alpha: 1)
            activeBars = 3
        case .medium:
            color = NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.16, alpha: 1)
            activeBars = 2
        case .far:
            color = NSColor(calibratedRed: 1.0, green: 0.29, blue: 0.26, alpha: 1)
            activeBars = 1
        }

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: color
        ]
        let label = proximity.rawValue as NSString
        label.draw(at: NSPoint(x: 34, y: 112), withAttributes: labelAttributes)

        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 19, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.70)
        ]
        ("Signal proximity" as NSString).draw(at: NSPoint(x: 36, y: 82), withAttributes: captionAttributes)

        let baseX: CGFloat = 224
        let baseY: CGFloat = 48
        let barWidth: CGFloat = 34
        let spacing: CGFloat = 15
        let heights: [CGFloat] = [58, 82, 110]

        for index in 0..<3 {
            let barRect = NSRect(
                x: baseX + CGFloat(index) * (barWidth + spacing),
                y: baseY,
                width: barWidth,
                height: heights[index]
            )
            let path = NSBezierPath(roundedRect: barRect, xRadius: 8, yRadius: 8)
            (index < activeBars ? color : NSColor.white.withAlphaComponent(0.18)).setFill()
            path.fill()
        }

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func detectionSoundWAVData() -> Data {
        let sampleRate = 44_100
        let duration = 0.9
        let sampleCount = Int(Double(sampleRate) * duration)
        let dataSize = sampleCount * MemoryLayout<Int16>.size
        var data = Data()

        data.append(contentsOf: "RIFF".utf8)
        appendUInt32LE(UInt32(36 + dataSize), to: &data)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendUInt32LE(16, to: &data)
        appendUInt16LE(1, to: &data)
        appendUInt16LE(1, to: &data)
        appendUInt32LE(UInt32(sampleRate), to: &data)
        appendUInt32LE(UInt32(sampleRate * MemoryLayout<Int16>.size), to: &data)
        appendUInt16LE(UInt16(MemoryLayout<Int16>.size), to: &data)
        appendUInt16LE(16, to: &data)
        data.append(contentsOf: "data".utf8)
        appendUInt32LE(UInt32(dataSize), to: &data)

        for index in 0..<sampleCount {
            let t = Double(index) / Double(sampleRate)
            let envelope = exp(-1.6 * t)
            let attack = min(1.0, t / 0.06)
            let body = sin(2 * Double.pi * 520.0 * t) * 0.24
            let harmonic = sin(2 * Double.pi * 780.0 * t) * 0.12
            let shimmer = sin(2 * Double.pi * 1040.0 * t) * 0.06 * (1.0 - (t / duration))
            let wave = (body + harmonic + shimmer) * attack * envelope
            let clamped = max(-0.7, min(0.7, wave))
            appendInt16LE(Int16(clamped * Double(Int16.max)), to: &data)
        }

        return data
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendInt16LE(_ value: Int16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

private struct PendingDetection {
    var camera: CameraDetection
    var proximity: ProximityLevel
}

private struct LegacyNotificationPayload {
    var title: String
    var subtitle: String
    var body: String
    var soundEnabled: Bool
}

extension NotificationService: NSUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        shouldPresent notification: NSUserNotification
    ) -> Bool {
        true
    }
}
