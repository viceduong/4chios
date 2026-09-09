import Foundation

/// A global, priority-aware gate that enforces 4chan's **1 request/second** rule.
///
/// Every network call goes through one instance. Requests are serialized with a
/// minimum spacing and served highest-priority-first, so a user-initiated tap
/// never queues behind background prefetching.
public actor ChanRateLimiter {
    public enum Priority: Int, Sendable, Comparable {
        case background = 0
        case prefetch = 1
        case threadPoll = 2
        case userInitiated = 3

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private let minimumInterval: TimeInterval
    private var nextSlot = Date.distantPast
    private var waiting: [(priority: Priority, sequence: UInt64, continuation: CheckedContinuation<Void, Never>)] = []
    private var sequence: UInt64 = 0
    private var isDraining = false

    public init(minimumInterval: TimeInterval = 1.0) {
        self.minimumInterval = minimumInterval
    }

    /// Suspends until it is this request's turn.
    public func acquire(_ priority: Priority = .userInitiated) async {
        await withCheckedContinuation { continuation in
            sequence += 1
            waiting.append((priority, sequence, continuation))
            drain()
        }
    }

    private func drain() {
        guard !isDraining, !waiting.isEmpty else { return }

        waiting.sort { lhs, rhs in
            lhs.priority == rhs.priority ? lhs.sequence < rhs.sequence : lhs.priority > rhs.priority
        }
        let next = waiting.removeFirst()
        isDraining = true

        let now = Date()
        let delay = max(0, nextSlot.timeIntervalSince(now))
        nextSlot = max(now, nextSlot).addingTimeInterval(minimumInterval)

        Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            next.continuation.resume()
            await self.finish()
        }
    }

    private func finish() {
        isDraining = false
        drain()
    }
}
