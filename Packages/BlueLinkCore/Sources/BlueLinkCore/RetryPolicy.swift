import Foundation

/// Bounded, backed-off retry budget.
///
/// The first attempt is followed by at most four retries (1/2/4/8 s by
/// default). Repeated notifications never refresh the budget; only a genuine
/// new wake cycle, a Bluetooth recovery, an effective configuration change or
/// an explicit user retry does.
public struct RetryPolicy: Equatable, Sendable {
    public var maximumAttempts: Int
    public var delays: [Duration]
    public var jitterFraction: Double
    /// Unexpected drops allowed inside `unexpectedDropWindow` before automatic
    /// reconnection stops. This caps a flapping link that reconnects instantly.
    public var maximumUnexpectedDrops: Int
    public var unexpectedDropWindow: Duration

    public init(
        maximumAttempts: Int = 5,
        delays: [Duration] = [
            .milliseconds(1_000),
            .milliseconds(2_000),
            .milliseconds(4_000),
            .milliseconds(8_000)
        ],
        jitterFraction: Double = 0.1,
        maximumUnexpectedDrops: Int = 3,
        unexpectedDropWindow: Duration = .seconds(60)
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.delays = delays
        self.jitterFraction = min(max(0, jitterFraction), 1)
        self.maximumUnexpectedDrops = max(1, maximumUnexpectedDrops)
        self.unexpectedDropWindow = unexpectedDropWindow
    }

    /// Delay before the next attempt. `completedAttempts` counts attempts that
    /// already failed. `randomUnit` is a deterministic [0, 1) value supplied by
    /// the caller so tests never sleep.
    public func delay(afterCompletedAttempts completedAttempts: Int, randomUnit: Double) -> Duration? {
        guard completedAttempts >= 1, completedAttempts < maximumAttempts else { return nil }
        let index = completedAttempts - 1
        let base = index < delays.count ? delays[index] : delays.last ?? .seconds(1)
        let jitter = base * jitterFraction * (min(max(randomUnit, 0), 0.999_999) * 2 - 1)
        let adjusted = base + jitter
        return adjusted < .zero ? .zero : adjusted
    }

    public var totalWindow: Duration {
        delays.prefix(max(0, maximumAttempts - 1)).reduce(.zero, +)
    }
}
