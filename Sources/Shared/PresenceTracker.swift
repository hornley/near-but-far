import Foundation

struct PresenceTracker {
    static let gracePeriod: TimeInterval = 60
    static let weakSignalThreshold: Int16 = -70

    private(set) var isArmed = false
    private(set) var lossStartedAt: ContinuousClock.Instant?
    private var didReportWouldLock = false

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

        if rssi <= Self.weakSignalThreshold {
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
