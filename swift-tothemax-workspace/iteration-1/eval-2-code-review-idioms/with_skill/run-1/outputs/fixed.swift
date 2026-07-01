import Foundation

/// Persists opaque blobs by key.
///
/// `save` is throwing so implementations (file system, keychain, …) can report
/// failures instead of swallowing them.
protocol Storage {
    func save(_ data: Data, forKey key: String) throws
    func load(forKey key: String) -> Data?
}

/// Manages the user's settings, persisting them via a `Storage` backend.
///
/// Main-actor–isolated: `onChange` is a UI-facing callback, so all state and
/// notifications stay on the main actor (the modern replacement for the
/// original `DispatchQueue.main.async` hop).
@MainActor
final class SettingsManager<Store: Storage> {
    /// Typed, `Codable` model instead of a stringly-typed `[String: String]`
    /// dictionary — `age` stays an `Int` end to end.
    private struct Settings: Codable {
        var name: String
        var age: Int
    }

    private let settingsKey = "settings"
    private let storage: Store

    /// Called after settings are successfully saved.
    var onChange: (() -> Void)?

    init(storage: Store) {
        self.storage = storage
    }

    /// Saves the given settings, then notifies the observer.
    ///
    /// Both values are required — the original took optionals and immediately
    /// force-unwrapped them, which crashed on `nil` input.
    func update(name: String, age: Int) throws {
        let settings = Settings(name: name, age: age)
        let data = try JSONEncoder().encode(settings)
        try storage.save(data, forKey: settingsKey)
        onChange?()
    }

    /// Returns the stored age, or `nil` if no settings have been saved yet.
    ///
    /// - Throws: A decoding error if stored data exists but is corrupt, so
    ///   callers can distinguish "never saved" (`nil`) from "damaged data"
    ///   instead of receiving a `-1` sentinel.
    func age() throws -> Int? {
        guard let data = storage.load(forKey: settingsKey) else { return nil }
        return try JSONDecoder().decode(Settings.self, from: data).age
    }
}
