import Foundation

struct PresenceTracker {
    static let gracePeriod: TimeInterval = 60

    var threshold: SignalThreshold

    private(set) var isArmed = false
    private(set) var lossStartedAt: ContinuousClock.Instant?
    private var didReportWouldLock = false

    init(threshold: SignalThreshold = .default) {
        self.threshold = threshold
    }

    mutating func acknowledge(at time: ContinuousClock.Instant) {
        isArmed = true
        lossStartedAt = nil
        didReportWouldLock = false
    }

    mutating func missedChallenge(at time: ContinuousClock.Instant) {
        guard isArmed, lossStartedAt == nil else { return }
        lossStartedAt = time
    }

    mutating func observeRSSI(_ rssi: Int16?, at time: ContinuousClock.Instant) {
        isArmed = true
        guard let rssi else { return }

        if rssi <= threshold.rawValue {
            missedChallenge(at: time)
        } else {
            acknowledge(at: time)
        }
    }

    mutating func takeWouldLock(at time: ContinuousClock.Instant) -> Bool {
        guard
            !didReportWouldLock,
            let lossStartedAt,
            lossStartedAt.duration(to: time) >= .seconds(Self.gracePeriod)
        else { return false }

        didReportWouldLock = true
        return true
    }

    func secondsRemaining(at time: ContinuousClock.Instant) -> Int? {
        guard let lossStartedAt else { return nil }
        let elapsed = lossStartedAt.duration(to: time).components
        let elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        return max(0, Int(ceil(Self.gracePeriod - elapsedSeconds)))
    }
}

struct SignalThreshold: Equatable {
    static let `default` = SignalThreshold(validated: -70)
    static let allowedRange: ClosedRange<Int16> = -90 ... -50

    let rawValue: Int16

    init?(validating value: Int16) {
        guard Self.allowedRange.contains(value) else { return nil }
        self.init(validated: value)
    }

    private init(validated value: Int16) {
        rawValue = value
    }
}
