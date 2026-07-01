import Foundation

/// A token-bucket rate limiter that is safe to use from many concurrent tasks.
///
/// The bucket starts full with `capacity` tokens and refills continuously at
/// `refillRate` tokens per second, never exceeding `capacity`. Each call to
/// ``acquire()`` consumes exactly one token, suspending the caller until a
/// token becomes available. Waiters are served in FIFO order, and a suspended
/// `acquire()` responds promptly to task cancellation by throwing
/// `CancellationError` without consuming a token.
///
/// ```swift
/// let limiter = TokenBucketRateLimiter(capacity: 10, refillRate: 5) // 5 permits/sec, bursts of 10
///
/// func fetch() async throws {
///     try await limiter.acquire()
///     // ... perform the rate-limited work ...
/// }
/// ```
public actor TokenBucketRateLimiter {

    /// The maximum number of tokens the bucket can hold (the burst size).
    public let capacity: Double

    /// The steady-state refill rate, in tokens per second.
    public let refillRate: Double

    private let clock = ContinuousClock()

    /// Current token count. Only meaningful after `refill()` brings it up to date.
    private var tokens: Double

    /// The instant at which `tokens` was last brought up to date.
    private var lastRefill: ContinuousClock.Instant

    /// FIFO queue of suspended callers.
    private var waiters: [Waiter] = []

    /// IDs whose cancellation handler ran before the waiter was enqueued.
    /// Checked (and cleared) when the waiter would otherwise be added.
    private var preCancelledIDs: Set<UInt64> = []

    /// Monotonically increasing waiter ID source.
    private var nextWaiterID: UInt64 = 0

    /// The background task that resumes waiters as tokens refill.
    /// Non-nil exactly while there is (or was just) a non-empty waiter queue being drained.
    private var drainTask: Task<Void, Never>?

    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// Creates a token-bucket rate limiter.
    ///
    /// - Parameters:
    ///   - capacity: The maximum number of tokens the bucket holds (burst size). Must be >= 1.
    ///   - refillRate: Tokens added per second. Must be > 0.
    ///   - initiallyFull: Whether the bucket starts full (`true`, the default) or empty.
    public init(capacity: Double, refillRate: Double, initiallyFull: Bool = true) {
        precondition(capacity >= 1, "capacity must be at least 1")
        precondition(refillRate > 0 && refillRate.isFinite, "refillRate must be a positive, finite number")
        self.capacity = capacity
        self.refillRate = refillRate
        self.tokens = initiallyFull ? capacity : 0
        self.lastRefill = clock.now
    }

    // MARK: - Public API

    /// Waits until a token is available, then consumes it.
    ///
    /// Callers are served in FIFO order. If the task is cancelled while
    /// waiting (or was already cancelled on entry), this throws
    /// `CancellationError` and no token is consumed.
    public func acquire() async throws {
        try Task.checkCancellation()

        refill()

        // Fast path: a token is available and nobody is queued ahead of us.
        if waiters.isEmpty && tokens >= 1 {
            tokens -= 1
            return
        }

        // Slow path: enqueue and suspend until the drain loop hands us a token.
        let id = nextWaiterID
        nextWaiterID &+= 1

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.enqueue(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            // Runs synchronously on whatever context triggered cancellation;
            // hop onto the actor to remove (or pre-cancel) the waiter.
            Task { await self.cancelWaiter(id: id) }
        }
    }

    /// Consumes a token immediately if one is available.
    ///
    /// - Returns: `true` if a token was consumed, `false` if the bucket is
    ///   empty or other callers are already waiting in line.
    public func tryAcquire() -> Bool {
        refill()
        guard waiters.isEmpty, tokens >= 1 else { return false }
        tokens -= 1
        return true
    }

    /// The number of whole tokens currently available (after refilling).
    /// Intended for observability and tests; the value may be stale by the
    /// time the caller acts on it.
    public var availableTokens: Int {
        refill()
        return Int(tokens.rounded(.down))
    }

    // MARK: - Waiter management

    private func enqueue(_ waiter: Waiter) {
        // The cancellation handler may have already run for this ID
        // (cancellation raced with suspension). Fail immediately if so.
        if preCancelledIDs.remove(waiter.id) != nil {
            waiter.continuation.resume(throwing: CancellationError())
            return
        }
        waiters.append(waiter)
        ensureDraining()
    }

    private func cancelWaiter(id: UInt64) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(throwing: CancellationError())
        } else {
            // Continuation not registered yet — remember the cancellation so
            // `enqueue` can fail it, unless it was already resumed normally
            // (in which case acquire() has returned and this ID never enqueues again).
            preCancelledIDs.insert(id)
        }
    }

    // MARK: - Refill / drain

    /// Brings `tokens` up to date with the amount of time that has elapsed.
    private func refill() {
        let now = clock.now
        let elapsed = lastRefill.duration(to: now)
        lastRefill = now
        let elapsedSeconds =
            Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) * 1e-18
        guard elapsedSeconds > 0 else { return }
        tokens = min(capacity, tokens + elapsedSeconds * refillRate)
    }

    /// Starts the drain loop if it is not already running.
    private func ensureDraining() {
        guard drainTask == nil else { return }
        drainTask = Task { await self.drain() }
    }

    /// Resumes waiters in FIFO order as tokens become available, sleeping
    /// between refills. Exits when the queue is empty.
    private func drain() async {
        while !waiters.isEmpty {
            refill()

            while tokens >= 1, !waiters.isEmpty {
                tokens -= 1
                let waiter = waiters.removeFirst()
                waiter.continuation.resume()
            }

            guard !waiters.isEmpty else { break }

            // Sleep just long enough for the next whole token to accrue.
            let deficit = 1 - tokens
            let wait = Duration.seconds(deficit / refillRate)
            // This task is internal and never cancelled; if the sleep were to
            // fail we simply loop and re-check state.
            try? await clock.sleep(for: wait)
        }
        drainTask = nil
        // A waiter may have been enqueued after the empty check above but
        // before we cleared drainTask (actor reentrancy across the sleep is
        // not possible here because no suspension separates the check from
        // the assignment, but enqueue() also restarts the loop if needed).
        if !waiters.isEmpty {
            ensureDraining()
        }
    }
}
