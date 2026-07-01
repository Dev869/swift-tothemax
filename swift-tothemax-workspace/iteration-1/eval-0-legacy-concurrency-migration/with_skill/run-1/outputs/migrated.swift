import Foundation

/// Loads and caches raw image data, keyed by URL.
///
/// Migrated from a `DispatchQueue`-based class to an `actor` for Swift 6
/// language mode: the actor serializes all access to `cache` and `inFlight`,
/// so the compiler proves data-race safety instead of relying on barrier
/// flags being used correctly at every call site.
actor ImageLoader {
    static let shared = ImageLoader()

    /// Completed downloads.
    private var cache: [URL: Data] = [:]

    /// Downloads currently in progress, so concurrent requests for the same
    /// URL share one network call instead of racing to start duplicates.
    /// (Actors are reentrant: state must be revalidated across every `await`,
    /// which is exactly what this dictionary handles.)
    private var inFlight: [URL: Task<Data, any Error>] = [:]

    /// Returns the data for `url`, from cache if available.
    func load(_ url: URL) async throws -> Data {
        if let cached = cache[url] {
            return cached
        }

        if let existing = inFlight[url] {
            return try await existing.value
        }

        let task = Task {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }

        let data = try await task.value
        cache[url] = data
        return data
    }

    /// Compatibility shim for callers not yet migrated to async/await.
    /// The completion handler is invoked on the main actor, matching the
    /// original `DispatchQueue.main.async` delivery.
    @available(*, deprecated, message: "Use load(_:) async throws instead.")
    nonisolated func load(
        _ url: URL,
        completion: @escaping @MainActor @Sendable (Result<Data, any Error>) -> Void
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
