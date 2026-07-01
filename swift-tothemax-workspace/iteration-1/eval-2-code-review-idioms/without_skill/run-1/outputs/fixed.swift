import Foundation

protocol Storage {
    func save(_ data: Data, key: String)
    func load(key: String) -> Data?
}

/// Strongly-typed settings model. Using Codable avoids stringly-typed
/// JSONSerialization dictionaries and preserves `age` as an Int.
struct Settings: Codable {
    var name: String?
    var age: Int?
}

final class SettingsManager {
    private static let settingsKey = "settings"

    private let storage: any Storage
    var onChange: (() -> Void)?

    init(storage: any Storage) {
        self.storage = storage
    }

    /// Partially updates settings: only the non-nil parameters are changed,
    /// and existing values are preserved instead of being overwritten.
    func update(name: String? = nil, age: Int? = nil) {
        var settings = loadSettings() ?? Settings()
        if let name { settings.name = name }
        if let age { settings.age = age }

        do {
            let data = try JSONEncoder().encode(settings)
            storage.save(data, key: Self.settingsKey)
            DispatchQueue.main.async { [weak self] in
                self?.onChange?()
            }
        } catch {
            // Encoding a Codable struct of String/Int should never fail;
            // surface it in debug builds instead of crashing in release.
            assertionFailure("Failed to encode settings: \(error)")
        }
    }

    /// Returns nil when no age has been stored (instead of a -1 sentinel).
    func getAge() -> Int? {
        loadSettings()?.age
    }

    func getName() -> String? {
        loadSettings()?.name
    }

    private func loadSettings() -> Settings? {
        guard let data = storage.load(key: Self.settingsKey) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }
}
