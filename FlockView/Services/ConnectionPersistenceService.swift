import Foundation

final class ConnectionPersistenceService {
    private let defaults = UserDefaults.standard
    private let deviceKey = "FlockView.LastSerialDevice"

    func save(device: SerialDevice) {
        if let data = try? JSONEncoder().encode(device) {
            defaults.set(data, forKey: deviceKey)
        }
    }

    func loadDevice() -> SerialDevice? {
        guard let data = defaults.data(forKey: deviceKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SerialDevice.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: deviceKey)
    }
}
