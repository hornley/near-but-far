import Foundation

struct PresenceTracker {
    static let gracePeriod: TimeInterval = 60
    static let weakSignalThreshold: Int16 = -70

    private(set) var isArmed = false
    private(set) var lossStartedAt: Date?
    private var didReportWouldLock = false

    mutating func acknowledge(at time: Date) {
        isArmed = true
        lossStartedAt = nil
        didReportWouldLock = false
    }

    mutating func missedChallenge(at time: Date) {
        guard isArmed, lossStartedAt == nil else { return }
        lossStartedAt = time
    }

    mutating func observeRSSI(_ rssi: Int16?, at time: Date) {
        isArmed = true
        guard let rssi else { return }

        if rssi <= Self.weakSignalThreshold {
            missedChallenge(at: time)
        } else {
            acknowledge(at: time)
        }
    }

    mutating func takeWouldLock(at time: Date) -> Bool {
        guard
            !didReportWouldLock,
            let lossStartedAt,
            time.timeIntervalSince(lossStartedAt) >= Self.gracePeriod
        else { return false }

        didReportWouldLock = true
        return true
    }

    func secondsRemaining(at time: Date) -> Int? {
        guard let lossStartedAt else { return nil }
        return max(0, Int(ceil(Self.gracePeriod - time.timeIntervalSince(lossStartedAt))))
    }
}
