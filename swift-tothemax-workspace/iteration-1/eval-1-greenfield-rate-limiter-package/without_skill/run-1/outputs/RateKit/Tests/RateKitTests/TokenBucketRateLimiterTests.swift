import Testing
@testable import RateKit

@Suite("TokenBucketRateLimiter")
struct TokenBucketRateLimiterTests {

    // MARK: - Basic behavior

    @Test("Burst up to capacity succeeds immediately")
    func burstUpToCapacity() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 5, refillRate: 1)
        let clock = ContinuousClock()
        let start = clock.now

        for _ in 0..<5 {
            try await limiter.acquire()
        }

        let elapsed = start.duration(to: clock.now)
        #expect(elapsed < .milliseconds(200), "burst acquisitions should not wait for refill")
    }

    @Test("Acquire waits for refill when bucket is empty")
    func waitsForRefill() async throws {
        // Empty bucket refilling at 20 tokens/sec: first token after ~50 ms.
        let limiter = TokenBucketRateLimiter(capacity: 1, refillRate: 20, initiallyFull: false)
        let clock = ContinuousClock()
        let start = clock.now

        try await limiter.acquire()

        let elapsed = start.duration(to: clock.now)
        #expect(elapsed >= .milliseconds(40), "acquire should have waited ~50 ms for a token")
    }

    @Test("Rate is enforced across sequential acquisitions")
    func enforcesRate() async throws {
        // capacity 1, 50 tokens/sec => each acquisition beyond the first waits ~20 ms.
        let limiter = TokenBucketRateLimiter(capacity: 1, refillRate: 50)
        let clock = ContinuousClock()
        let start = clock.now

        for _ in 0..<6 {
            try await limiter.acquire()
        }

        // 1 free (initial token) + 5 waits of ~20 ms => at least ~100 ms total.
        let elapsed = start.duration(to: clock.now)
        #expect(elapsed >= .milliseconds(90))
    }

    @Test("tryAcquire consumes available tokens and then fails")
    func tryAcquireBehavior() async {
        let limiter = TokenBucketRateLimiter(capacity: 2, refillRate: 0.5)
        #expect(await limiter.tryAcquire())
        #expect(await limiter.tryAcquire())
        #expect(await limiter.tryAcquire() == false)
    }

    @Test("Tokens never exceed capacity after idling")
    func capacityIsCeiling() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 3, refillRate: 1000)
        try await Task.sleep(for: .milliseconds(50)) // would accrue ~50 tokens uncapped
        #expect(await limiter.availableTokens <= 3)
    }

    // MARK: - Concurrency

    @Test("Many concurrent tasks all eventually acquire exactly once")
    func concurrentAcquisitions() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 10, refillRate: 500)
        let total = 60

        let successes = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<total {
                group.addTask {
                    try await limiter.acquire()
                    return 1
                }
            }
            var count = 0
            for try await value in group { count += value }
            return count
        }

        #expect(successes == total)
    }

    @Test("Concurrent load cannot acquire faster than the refill rate allows")
    func concurrentLoadRespectsRate() async throws {
        let capacity = 5.0
        let rate = 100.0
        let total = 30
        let limiter = TokenBucketRateLimiter(capacity: capacity, refillRate: rate)
        let clock = ContinuousClock()
        let start = clock.now

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<total {
                group.addTask { try await limiter.acquire() }
            }
            try await group.waitForAll()
        }

        // 30 tokens with 5 banked: 25 must accrue at 100/s => >= 250 ms.
        // Allow generous slack for timer coarseness.
        let elapsed = start.duration(to: clock.now)
        #expect(elapsed >= .milliseconds(200))
    }

    // MARK: - Cancellation

    @Test("Cancelling a waiting acquire throws CancellationError promptly")
    func cancellationWhileWaiting() async throws {
        // Effectively never refills within the test window.
        let limiter = TokenBucketRateLimiter(capacity: 1, refillRate: 0.001, initiallyFull: false)

        let task = Task {
            try await limiter.acquire()
        }

        try await Task.sleep(for: .milliseconds(50)) // let the task suspend in acquire()
        let clock = ContinuousClock()
        let cancelledAt = clock.now
        task.cancel()

        do {
            try await task.value
            Issue.record("acquire should have thrown after cancellation")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(cancelledAt.duration(to: clock.now) < .milliseconds(500),
                "cancellation should propagate promptly, not wait for a token")
    }

    @Test("Already-cancelled task fails without consuming a token")
    func preCancelledTask() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 1, refillRate: 0.001)

        let task = Task {
            try await Task.sleep(for: .seconds(10)) // parked until cancelled
            try await limiter.acquire()
        }
        task.cancel()

        do {
            try await task.value
            Issue.record("expected CancellationError")
        } catch {
            #expect(error is CancellationError)
        }

        // The single banked token must still be there.
        #expect(await limiter.tryAcquire())
    }

    @Test("Cancelled waiter does not consume a token; the next waiter gets it")
    func cancelledWaiterYieldsTokenToNext() async throws {
        // One token every 100 ms, starting empty.
        let limiter = TokenBucketRateLimiter(capacity: 1, refillRate: 10, initiallyFull: false)

        let doomed = Task { try await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(20)) // doomed is first in line
        let survivor = Task { try await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(20))

        doomed.cancel()
        do {
            try await doomed.value
            Issue.record("doomed task should have been cancelled")
        } catch {
            #expect(error is CancellationError)
        }

        // Survivor should still get the ~100 ms token.
        try await survivor.value
    }

    @Test("Cancelling some of many waiters leaves the rest working")
    func massCancellationUnderLoad() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 1, refillRate: 200)
        let total = 40

        let outcomes = await withTaskGroup(of: Bool.self) { group in
            for i in 0..<total {
                group.addTask {
                    do {
                        if i.isMultiple(of: 2) {
                            // Half the tasks cancel themselves mid-flight.
                            let inner = Task { try await limiter.acquire() }
                            try? await Task.sleep(for: .milliseconds(5))
                            inner.cancel()
                            try await inner.value
                        } else {
                            try await limiter.acquire()
                        }
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var results: [Bool] = []
            for await outcome in group { results.append(outcome) }
            return results
        }

        let succeeded = outcomes.filter { $0 }.count
        // All 20 non-cancelling tasks must succeed. Cancelling tasks may or
        // may not have acquired before the cancel landed; either is valid.
        #expect(succeeded >= total / 2)
        #expect(outcomes.count == total)

        // The limiter must remain fully functional afterwards.
        try await limiter.acquire()
    }
}
