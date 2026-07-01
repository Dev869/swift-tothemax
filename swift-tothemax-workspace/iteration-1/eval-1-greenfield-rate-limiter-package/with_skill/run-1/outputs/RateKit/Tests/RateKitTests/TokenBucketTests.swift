import RateKit
import Synchronization
import Testing

/// A thread-safe counter; `Mutex` itself is `~Copyable`, so it cannot be
/// captured directly by concurrently executing task-group closures.
private final class Counter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }
    func increment() { count.withLock { $0 += 1 } }
}

@Suite("TokenBucket", .timeLimit(.minutes(1)))
struct TokenBucketTests {

    // MARK: Immediate acquisition

    @Test func acquiresImmediatelyWhileTokensRemain() async throws {
        let clock = TestClock()
        let bucket = TokenBucket(capacity: 3, refill: 1, interval: .seconds(1), clock: clock)

        // The clock never advances, so these must complete without waiting.
        for _ in 0..<3 {
            try await bucket.acquire()
        }
        #expect(await bucket.tryAcquire() == false)
    }

    @Test func tryAcquireReflectsAvailability() async {
        let clock = TestClock()
        let bucket = TokenBucket(capacity: 2, refill: 1, interval: .seconds(1), clock: clock)

        #expect(await bucket.tryAcquire())
        #expect(await bucket.tryAcquire())
        #expect(await bucket.tryAcquire() == false)

        clock.advance(by: .seconds(1))
        #expect(await bucket.tryAcquire())
    }

    // MARK: Refill behavior

    @Test func refillNeverExceedsCapacity() async {
        let clock = TestClock()
        let bucket = TokenBucket(
            capacity: 2, refill: 1, interval: .seconds(1), clock: clock, initiallyAvailable: 0
        )

        clock.advance(by: .seconds(100))

        #expect(await bucket.tryAcquire())
        #expect(await bucket.tryAcquire())
        #expect(await bucket.tryAcquire() == false)
    }

    @Test func refillAccruesContinuously() async {
        let clock = TestClock()
        let bucket = TokenBucket(
            capacity: 4, refill: 4, interval: .seconds(1), clock: clock, initiallyAvailable: 0
        )

        // A quarter of the interval earns a quarter of the refill: 1 token.
        clock.advance(by: .milliseconds(250))
        #expect(await bucket.tryAcquire())
        #expect(await bucket.tryAcquire() == false)
    }

    // MARK: Waiting

    @Test func acquireWaitsUntilATokenIsRefilled() async throws {
        let clock = TestClock()
        let bucket = TokenBucket(
            capacity: 1, refill: 1, interval: .seconds(1), clock: clock, initiallyAvailable: 0
        )

        let waiter = Task { try await bucket.acquire() }
        while clock.sleeperCount == 0 { await Task.yield() }

        clock.advance(by: .seconds(1))
        try await waiter.value
    }

    @Test func concurrentAcquiresRespectCapacityAndRate() async throws {
        let clock = TestClock()
        let bucket = TokenBucket(capacity: 3, refill: 1, interval: .seconds(1), clock: clock)
        let admitted = Counter()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await bucket.acquire()
                    admitted.increment()
                }
            }

            // 3 tasks take the initial burst; the other 7 must queue.
            while clock.sleeperCount < 7 { await Task.yield() }
            #expect(admitted.value == 3)

            // 7 more tokens are earned over 7 intervals; everyone gets in.
            clock.advance(by: .seconds(7))
            try await group.waitForAll()
        }

        #expect(admitted.value == 10)
        #expect(await bucket.tryAcquire() == false)
    }

    // MARK: Cancellation

    @Test func cancellationWhileWaitingThrowsCancellationError() async {
        let clock = TestClock()
        let bucket = TokenBucket(
            capacity: 1, refill: 1, interval: .seconds(1), clock: clock, initiallyAvailable: 0
        )

        let waiter = Task { try await bucket.acquire() }
        while clock.sleeperCount == 0 { await Task.yield() }

        waiter.cancel()
        let result = await waiter.result
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test func cancellationBeforeWaitingThrowsCancellationError() async {
        let clock = TestClock()
        let bucket = TokenBucket(capacity: 1, refill: 1, interval: .seconds(1), clock: clock)

        let waiter = Task {
            try await Task.sleep(for: .seconds(1_000)) // parked until cancelled
            try await bucket.acquire()
        }
        waiter.cancel()

        let result = await waiter.result
        #expect(throws: CancellationError.self) { try result.get() }
        // The cancelled task never consumed the token.
        #expect(await bucket.tryAcquire())
    }

    @Test func cancelledWaiterReturnsItsReservation() async {
        let clock = TestClock()
        let bucket = TokenBucket(
            capacity: 1, refill: 1, interval: .seconds(1), clock: clock, initiallyAvailable: 0
        )

        let waiter = Task { try await bucket.acquire() }
        while clock.sleeperCount == 0 { await Task.yield() }
        waiter.cancel()
        _ = await waiter.result

        // The reservation was refunded, so the first refilled token is free
        // for the taking; a leaked reservation would leave the balance at 0.
        clock.advance(by: .seconds(1))
        #expect(await bucket.tryAcquire())
    }

    // MARK: Convenience initializer

    @Test func convenienceInitializerUsesContinuousClock() async throws {
        let bucket = TokenBucket(capacity: 1, refill: 1, interval: .seconds(1))
        try await bucket.acquire() // burst token: returns without waiting
        #expect(await bucket.tryAcquire() == false)
    }
}
