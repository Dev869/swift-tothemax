# RateKit

A small Swift package providing a **token-bucket rate limiter** (`TokenBucketRateLimiter`) that is safe to use from many concurrent tasks.

## Features

- `func acquire() async throws` — suspends until a token is available, then consumes it.
- Respects task cancellation: a waiting (or already-cancelled) caller throws `CancellationError` promptly and never consumes a token.
- FIFO fairness — waiters are served in arrival order.
- Continuous refill at a configurable rate, with a configurable burst capacity.
- `tryAcquire()` for non-blocking attempts and `availableTokens` for observability.
- Implemented as an `actor` with `ContinuousClock`; builds under Swift 6 strict concurrency.

## Usage

```swift
import RateKit

// 5 permits/second steady state, bursts of up to 10.
let limiter = TokenBucketRateLimiter(capacity: 10, refillRate: 5)

func fetch() async throws {
    try await limiter.acquire()
    // ... perform the rate-limited work ...
}
```

Start with an empty bucket if you don't want an initial burst:

```swift
let limiter = TokenBucketRateLimiter(capacity: 10, refillRate: 5, initiallyFull: false)
```

## Requirements

- Swift 6.0+ toolchain
- macOS 13 / iOS 16 / tvOS 16 / watchOS 9 / visionOS 1 or later

## Testing

```sh
swift build
swift test
```
