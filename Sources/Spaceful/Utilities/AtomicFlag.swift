import Foundation

/// A minimal thread-safe boolean flag (one-way latch), used for scan cancellation.
///
/// Kept dependency-free on purpose: importing `swift-atomics` would be overkill for a
/// single set-once flag. `NSLock` is more than fast enough here since reads happen at
/// directory granularity, not per byte.
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }
}
