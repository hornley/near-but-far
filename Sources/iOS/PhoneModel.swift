import Combine
import Foundation

enum PhonePresenceState: Equatable {
    case waiting
    case nearby
    case weakSignalCountdown(Int)
    case connectionLostCountdown(Int)
    case wouldLock
    case unavailable
}

@MainActor
final class PhoneModel: ObservableObject {
    @Published private(set) var lastRSSI: Int?
    @Published private(set) var presenceState: PhonePresenceState = .waiting

    private enum LossReason: Equatable {
        case weakSignal
        case connectionLost
    }

    private var presenceTracker = PresenceTracker()
    private(set) var lastChallengeAt: ContinuousClock.Instant?
    private var lossReason: LossReason?
    private var bluetoothAvailable = true

    func setBluetoothAvailable(_ available: Bool) {
        bluetoothAvailable = available
        refreshPresence()
    }

    func didSubscribe(at now: ContinuousClock.Instant) {
        lastChallengeAt = now
        if !presenceTracker.isArmed {
            presenceTracker.acknowledge(at: now)
        }
        refreshPresence(at: now)
    }

    func didReceiveChallenge(at now: ContinuousClock.Instant) {
        lastChallengeAt = now
        refreshPresence(at: now)
    }

    func didDisconnect(at now: ContinuousClock.Instant) {
        presenceTracker.missedChallenge(at: now)
        if presenceTracker.lossStartedAt != nil {
            lossReason = .connectionLost
        }
        refreshPresence(at: now)
    }

    func didReadRSSI(_ rssi: Int16?, at now: ContinuousClock.Instant) {
        lastRSSI = rssi.map(Int.init)
        let wasCountingDown = presenceTracker.lossStartedAt != nil
        presenceTracker.observeRSSI(rssi, at: now)

        if let rssi {
            if rssi <= PresenceTracker.weakSignalThreshold {
                if !wasCountingDown { lossReason = .weakSignal }
            } else {
                lossReason = nil
            }
        }
        refreshPresence(at: now)
    }

    func refreshPresence(at now: ContinuousClock.Instant = ContinuousClock.now) {
        guard bluetoothAvailable else {
            presenceState = .unavailable
            return
        }

        if let lastChallengeAt,
           presenceTracker.isArmed,
           presenceTracker.lossStartedAt == nil,
           lastChallengeAt.duration(to: now) >= .seconds(10) {
            presenceTracker.missedChallenge(at: lastChallengeAt.advanced(by: .seconds(10)))
            lossReason = .connectionLost
        }

        presenceTracker.takeWouldLock(at: now)
        guard presenceTracker.isArmed else {
            presenceState = .waiting
            return
        }

        if let remaining = presenceTracker.secondsRemaining(at: now) {
            if remaining == 0 {
                presenceState = .wouldLock
            } else if lossReason == .weakSignal {
                presenceState = .weakSignalCountdown(remaining)
            } else {
                presenceState = .connectionLostCountdown(remaining)
            }
        } else {
            lossReason = nil
            presenceState = .nearby
        }
    }
}
