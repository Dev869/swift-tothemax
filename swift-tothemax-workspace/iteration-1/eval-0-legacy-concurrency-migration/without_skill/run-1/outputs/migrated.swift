import Foundation

/// An image-data loader with an in-memory cache, migrated to Swift Concurrency.
///
/// The original class protected its cache with a concurrent DispatchQueue and
/// barrier writes. As an `actor`, all access to `cache` is serialized by the
/// actor's isolation, so the queue (and the data race it guarded against) is
/// gone entirely, and the class compiles cleanly in Swift 6 language mode.
actor ImageLoader {
    static let shared = ImageLoader()

    private var cache: [URL: Data] = [:]

    private init() {}

    /// Loads image data for `url`, returning cached data when available.
    ///
    /// Preserves the original behavior: check cache first, otherwise fetch
    /// from the network, store the result in the cache, and return it.
    func load(_ url: URL) async throws -> Data {
        if let cached = cache[url] {
            return cached
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // Suspension point above: the actor was not held during the network
        // request, so another caller may have populated the cache meanwhile.
        // Writing unconditionally matches the original barrier-write behavior.
        cache[url] = data
        return data
    }

    /// Completion-handler shim matching the legacy call sites.
    ///
    /// The original always invoked `completion` on the main queue; this
    /// preserves that contract by requiring a `@MainActor` closure, which the
    /// runtime hops to the main actor before calling.
    nonisolated func load(
        _ url: URL,
        completion: @escaping @MainActor (Result<Data, Error>) -> Void
    ) {
        Task {
            do {
                let data = try await self.load(url)
                await completion(.success(data))
            } catch {
                await completion(.failure(error))
            }
        }
    }
}
