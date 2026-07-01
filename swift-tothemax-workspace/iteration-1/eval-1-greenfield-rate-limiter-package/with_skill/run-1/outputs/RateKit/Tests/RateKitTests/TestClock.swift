import Synchronization

/// A manually advanced clock for deterministic tests.
///
/// Time only moves when the test calls ``advance(by:)``; sleepers whose
/// deadlines are reached resume in deadline order. Sleeping tasks that are
/// cancelled resume immediately with `CancellationError`.
final class TestClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration = .zero

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        var deadline: Instant
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant()
        var nextID = 0
        var sleepers: [Int: Sleeper] = [:]
        /// IDs cancelled before their sleeper was registered.
        var cancelledBeforeRegistration: Set<Int> = []
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    /// The number of tasks currently suspended in `sleep`.
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = state.withLock { state in
            state.nextID += 1
            return state.nextID
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enum Registration { case resume, cancel, wait }
                let registration = state.withLock { state -> Registration in
                    if state.cancelledBeforeRegistration.remove(id) != nil {
                        return .cancel
                    }
                    if deadline <= state.now {
                        return .resume
                    }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return .wait
                }
                switch registration {
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                case .wait: break
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                if let sleeper = state.sleepers.removeValue(forKey: id) {
                    return sleeper
                }
                state.cancelledBeforeRegistration.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward, resuming (in deadline order) every sleeper whose
    /// deadline has been reached.
    func advance(by duration: Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let dueIDs = state.sleepers.filter { $0.value.deadline <= state.now }.keys
            var due: [Sleeper] = []
            for id in dueIDs {
                if let sleeper = state.sleepers.removeValue(forKey: id) {
                    due.append(sleeper)
                }
            }
            return due.sorted { $0.deadline < $1.deadline }
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }
}
