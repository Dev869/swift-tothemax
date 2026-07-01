/// A token-bucket rate limiter that is safe to use from many concurrent tasks.
///
/// The bucket starts with a configurable number of tokens and continuously
/// replenishes them at a fixed rate (`refill` tokens every `interval`), never
/// exceeding `capacity`. Each successful call to ``acquire()`` or
/// ``tryAcquire()`` consumes one token.
///
/// When no token is available, ``acquire()`` *reserves* the next token to be
/// generated and suspends until it is due, so waiters are admitted in
/// first-come, first-served order. A cancelled waiter returns its reservation
/// to the bucket.
///
/// The clock is injectable, which makes the limiter deterministic to test;
/// production code can use the convenience initializer, which uses
/// `ContinuousClock`.
///
/// ```swift
/// let limiter = TokenBucket(capacity: 10, refill: 10, interval: .seconds(1))
///
/// func fetch(_ url: URL) async throws -> Data {
///     try await limiter.acquire()
///     return try await download(url)
/// }
/// ```
public actor TokenBucket<ClockType: Clock<Duration>> {
    /// The maximum number of tokens the bucket can hold.
    public let capacity: Int

    private let refillAmount: Int
    private let refillInterval: Duration
    private let clock: ClockType

    /// The current token balance.
    ///
    /// May be fractional (partial refill) or negative (tokens reserved by
    /// suspended waiters that have not yet been generated).
    private var available: Double
    private var lastRefill: ClockType.Instant

    /// Creates a token bucket driven by the given clock.
    ///
    /// - Parameters:
    ///   - capacity: The maximum number of tokens the bucket can hold.
    ///     Must be greater than zero.
    ///   - refill: The number of tokens added per `interval`.
    ///     Must be greater than zero.
    ///   - interval: How often `refill` tokens are added. Replenishment is
    ///     continuous, so tokens accrue smoothly across the interval.
    ///     Must be greater than zero.
    ///   - clock: The clock used to measure elapsed time and to wait for
    ///     replenishment.
    ///   - initiallyAvailable: The number of tokens available at creation.
    ///     Must be in `0...capacity`. Defaults to `capacity` (a full bucket).
    public init(
        capacity: Int,
        refill: Int,
        interval: Duration,
        clock: ClockType,
        initiallyAvailable: Int? = nil
    ) {
        precondition(capacity > 0, "capacity must be greater than zero")
        precondition(refill > 0, "refill must be greater than zero")
        precondition(interval > .zero, "interval must be greater than zero")
        let initial = initiallyAvailable ?? capacity
        precondition(
            (0...capacity).contains(initial),
            "initiallyAvailable must be in 0...capacity"
        )

        self.capacity = capacity
        self.refillAmount = refill
        self.refillInterval = interval
        self.clock = clock
        self.available = Double(initial)
        self.lastRefill = clock.now
    }

    /// Waits until a token is available, then consumes it.
    ///
    /// If a token is available the call returns immediately. Otherwise it
    /// reserves the next token to be generated and suspends until that token
    /// is due; waiters are served in arrival order.
    ///
    /// Cancellation is respected at every suspension point: if the task is
    /// cancelled while waiting, the reservation is returned to the bucket and
    /// `CancellationError` is thrown.
    public func acquire() async throws {
        try Task.checkCancellation()
        refill()
        available -= 1
        if available >= 0 { return }

        // The balance is negative: `-available` tokens are owed to waiters
        // ahead of us plus ourselves. Sleep until our token has been earned.
        let tokensOwed = -available
        let wait = Duration.seconds(
            tokensOwed / Double(refillAmount) * refillInterval.rk_seconds
        )
        do {
            try await clock.sleep(for: wait)
        } catch {
            // Return our reservation so the token is not lost.
            refill()
            available = min(available + 1, Double(capacity))
            throw error
        }
    }

    /// Consumes a token if one is available right now, without waiting.
    ///
    /// - Returns: `true` if a token was consumed; `false` if the bucket is
    ///   empty or all replenished tokens are reserved by suspended waiters.
    public func tryAcquire() -> Bool {
        refill()
        guard available >= 1 else { return false }
        available -= 1
        return true
    }

    /// Credits tokens earned since the last refill, capped at `capacity`.
    private func refill() {
        let now = clock.now
        let elapsed = lastRefill.duration(to: now)
        guard elapsed > .zero else { return }
        lastRefill = now
        let earned = elapsed.rk_seconds / refillInterval.rk_seconds * Double(refillAmount)
        available = min(available + earned, Double(capacity))
    }
}

extension TokenBucket where ClockType == ContinuousClock {
    /// Creates a token bucket driven by the continuous (wall-time) clock.
    ///
    /// - Parameters:
    ///   - capacity: The maximum number of tokens the bucket can hold.
    ///     Must be greater than zero.
    ///   - refill: The number of tokens added per `interval`.
    ///     Must be greater than zero.
    ///   - interval: How often `refill` tokens are added.
    ///     Must be greater than zero.
    ///   - initiallyAvailable: The number of tokens available at creation.
    ///     Must be in `0...capacity`. Defaults to `capacity` (a full bucket).
    public init(
        capacity: Int,
        refill: Int,
        interval: Duration,
        initiallyAvailable: Int? = nil
    ) {
        self.init(
            capacity: capacity,
            refill: refill,
            interval: interval,
            clock: ContinuousClock(),
            initiallyAvailable: initiallyAvailable
        )
    }
}

extension Duration {
    /// This duration expressed in (fractional) seconds.
    fileprivate var rk_seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
