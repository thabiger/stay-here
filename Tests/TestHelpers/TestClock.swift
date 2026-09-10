import Foundation

/// Deterministic clock for observation-cadence tests: advance manually between
/// observations. `provider` is safe to pass into `SpaceLabelStore(now:)`.
public final class TestClock {
    private(set) var now: Date
    public init(_ now: Date = Date(timeIntervalSince1970: 1_700_000_000)) { self.now = now }
    public func advance(by interval: TimeInterval) { now = now.addingTimeInterval(interval) }
    public var provider: () -> Date { { [weak self] in self?.now ?? Date() } }
}
