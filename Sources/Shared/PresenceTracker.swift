import Foundation

struct PresenceTracker {
    var threshold: SignalThreshold

    private(set) var isArmed = false
    private(set) var lossStartedAt: ContinuousClock.Instant?
    private var configuredDuration: CountdownDuration
    private var activeCountdownDuration: CountdownDuration? = nil
    private var didReportWouldLock = false

    init(threshold: SignalThreshold = .default,
         duration: CountdownDuration = .defaultDuration) {
        self.threshold = threshold
        self.configuredDuration = duration
    }

    mutating func setConfiguredDuration(_ duration: CountdownDuration) {
        configuredDuration = duration
    }

    mutating func acknowledge(at time: ContinuousClock.Instant) {
        isArmed = true
        lossStartedAt = nil
        activeCountdownDuration = nil
        didReportWouldLock = false
    }

    mutating func missedChallenge(at time: ContinuousClock.Instant) {
        guard isArmed, lossStartedAt == nil else { return }
        lossStartedAt = time
        activeCountdownDuration = configuredDuration
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
            let activeCountdownDuration,
            lossStartedAt.duration(to: time) >= .seconds(activeCountdownDuration.seconds)
        else { return false }

        didReportWouldLock = true
        return true
    }

    func secondsRemaining(at time: ContinuousClock.Instant) -> Int? {
        guard let lossStartedAt, let activeCountdownDuration else { return nil }
        let elapsed = lossStartedAt.duration(to: time).components
        let elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        return max(0, Int(ceil(Double(activeCountdownDuration.seconds) - elapsedSeconds)))
    }
}

struct CountdownDuration: Equatable {
    static let defaultDuration = CountdownDuration(validatedSeconds: 60)
    static let allowedRange: ClosedRange<Int> = 15 ... 180

    let seconds: Int

    init?(validating seconds: Int) {
        guard Self.allowedRange.contains(seconds), (seconds - 15).isMultiple(of: 5) else { return nil }
        self.init(validatedSeconds: seconds)
    }

    private init(validatedSeconds: Int) {
        self.seconds = validatedSeconds
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
