import Combine
import Foundation

enum PhonePresenceState: Equatable {
    case waiting
    case nearby
    case weakSignalCountdown(Int)
    case connectionLostCountdown(Int)
    case away
    case unavailable
}

struct PhonePresencePresentation {
    let state: PhonePresenceState

    var headline: String {
        switch state {
        case .waiting: "Waiting for Mac"
        case .nearby: "Nearby"
        case .weakSignalCountdown(let seconds): "Locks in \(seconds)s"
        case .connectionLostCountdown: "Signal lost"
        case .away: "Away"
        case .unavailable: "Unavailable"
        }
    }

    var detailsHeadline: String {
        switch state {
        case .weakSignalCountdown: "Weak signal"
        case .connectionLostCountdown: "Signal lost"
        default: headline
        }
    }

    var countdownDisclosure: String? {
        switch state {
        case .weakSignalCountdown:
            "Near But Far’s app screen only; macOS stays unlocked."
        case .connectionLostCountdown(let seconds):
            "Local estimate: app screen in \(seconds)s; macOS stays unlocked."
        default:
            nil
        }
    }

    var announcementTitle: String {
        switch state {
        case .weakSignalCountdown: "Weak signal countdown started"
        case .connectionLostCountdown: "Signal lost"
        default: headline
        }
    }
}

enum PhoneMacStatus: Equatable {
    case unavailable, waiting, nearby, weakSignal, signalLost
}

enum PhoneDisconnectCause {
    case transportLost, reconnectAttempt, pairingStarted, bluetoothUnavailable
}

enum PhoneAppScreenDisplayState: Equatable {
    case active, inactive, unavailable
}

enum PhoneAppScreenCommandReadiness {
    static func canSend(
        sessionReady: Bool,
        stateReceived: Bool,
        bluetoothAvailable: Bool,
        hasActiveLink: Bool,
        hasSession: Bool,
        hasPeripheral: Bool,
        hasCharacteristic: Bool
    ) -> Bool {
        sessionReady && stateReceived && bluetoothAvailable && hasActiveLink && hasSession &&
        hasPeripheral && hasCharacteristic
    }
}

@MainActor
final class PhoneModel: ObservableObject {
    @Published private(set) var lastRSSI: Int?
    @Published private(set) var macBatteryLevel: UInt8?
    @Published private(set) var presenceState: PhonePresenceState = .waiting
    @Published private(set) var macStatus: PhoneMacStatus = .unavailable
    @Published private(set) var hasReceivedMacStatus = false
    var authenticatedMacStatus: PhoneMacStatus? { hasReceivedMacStatus ? macStatus : nil }
    @Published private(set) var appScreenState: AppScreenState = .inactive
    @Published private(set) var hasReceivedAppScreenStateForSession = false
    var appScreenDisplayState: PhoneAppScreenDisplayState {
        guard hasReceivedAppScreenStateForSession else { return .unavailable }
        return appScreenState == .active ? .active : .inactive
    }
    var canSendAppScreenCommand: Bool {
        sessionReady && bluetoothAvailable && hasReceivedAppScreenStateForSession
    }
    var localSignalThreshold: SignalThreshold { presenceTracker.threshold }
    @Published private(set) var authenticatedPeerID: UUID?
    @Published private(set) var sessionReady = false
    @Published private(set) var signalThreshold: SignalThreshold?
    @Published private(set) var countdownDuration: CountdownDuration
    @Published private(set) var hasReceivedThresholdForSession = false
    var canLockNow: Bool { canSendAppScreenCommand }
    var canUnlock: Bool { canSendAppScreenCommand }

    private enum LossReason: Equatable {
        case weakSignal
        case connectionLost
    }

    private var presenceTracker: PresenceTracker
    private let userDefaults: UserDefaults
    private var lastChallengeAt: ContinuousClock.Instant?
    private var lastMacBatteryUpdateAt: ContinuousClock.Instant?
    private var lossReason: LossReason?
    private var bluetoothAvailable = true

    private static let thresholdPreferenceKey = "authenticatedMacSignalThresholdDBm"
    private static let countdownDurationPreferenceKey = "countdownDurationSeconds"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let threshold = Self.loadSavedThreshold(from: userDefaults)
        signalThreshold = threshold
        let storedDuration = userDefaults.object(forKey: Self.countdownDurationPreferenceKey) as? Int
        let duration = storedDuration.flatMap(CountdownDuration.init(validating:)) ?? .defaultDuration
        countdownDuration = duration
        presenceTracker = PresenceTracker(threshold: threshold ?? .default, duration: duration)
    }

    func setBluetoothAvailable(_ available: Bool) {
        bluetoothAvailable = available
        refreshPresence()
    }

    func didDisconnect(cause: PhoneDisconnectCause, at now: ContinuousClock.Instant) {
        sessionReady = false
        hasReceivedThresholdForSession = false
        authenticatedPeerID = nil
        macBatteryLevel = nil
        lastMacBatteryUpdateAt = nil
        macStatus = .unavailable
        hasReceivedMacStatus = false
        hasReceivedAppScreenStateForSession = false
        lastChallengeAt = nil
        switch cause {
        case .transportLost:
            if presenceTracker.isArmed, presenceTracker.lossStartedAt == nil {
                presenceTracker.missedChallenge(at: now)
            }
            lossReason = .connectionLost
        case .reconnectAttempt:
            if presenceTracker.lossStartedAt == nil { lossReason = nil }
        case .pairingStarted, .bluetoothUnavailable:
            presenceTracker = PresenceTracker(threshold: signalThreshold ?? .default, duration: countdownDuration)
            lossReason = nil
        }
        refreshPresence(at: now)
    }

    func didReceiveAuthenticated(_ message: PeerMessage, at now: ContinuousClock.Instant) {
        switch message {
        case .pairingComplete:
            sessionReady = true
        case let .status(status):
            hasReceivedMacStatus = true
            switch status {
            case .unavailable: macStatus = .unavailable
            case .waiting: macStatus = .waiting
            case .nearby: macStatus = .nearby
            case .weakSignal: macStatus = .weakSignal
            case .signalLost: macStatus = .signalLost
            }
        case let .threshold(rawValue):
            guard let threshold = SignalThreshold(validating: rawValue) else { return }
            signalThreshold = threshold
            hasReceivedThresholdForSession = true
            presenceTracker.threshold = threshold
            userDefaults.set(Int(rawValue), forKey: Self.thresholdPreferenceKey)
        case let .countdownDuration(seconds):
            guard sessionReady,
                  let duration = CountdownDuration(validating: Int(seconds)) else { return }
            countdownDuration = duration
            userDefaults.set(duration.seconds, forKey: Self.countdownDurationPreferenceKey)
            presenceTracker.setConfiguredDuration(duration)
        case let .appScreenState(state):
            guard sessionReady else { return }
            appScreenState = state
            hasReceivedAppScreenStateForSession = true
        case let .macBatteryLevel(level):
            guard sessionReady else { return }
            macBatteryLevel = level
            lastMacBatteryUpdateAt = now
        case let .challenge(sequence):
            _ = sequence
            guard sessionReady else { return }
            lastChallengeAt = now
            if !presenceTracker.isArmed { presenceTracker.acknowledge(at: now) }
            refreshPresence(at: now)
        case .pairingPrepared, .pairingAccepted, .acknowledgement, .appScreenCommand:
            break
        }
    }

    func didAuthenticate(peerID: UUID) {
        authenticatedPeerID = peerID
        sessionReady = true
        hasReceivedAppScreenStateForSession = false
    }

    private func didReadRSSI(_ rssi: Int16?, at now: ContinuousClock.Instant) {
        lastRSSI = rssi.map(Int.init)
        let wasCountingDown = presenceTracker.lossStartedAt != nil
        presenceTracker.observeRSSI(rssi, at: now)

        if let rssi {
            if rssi <= presenceTracker.threshold.rawValue {
                if !wasCountingDown { lossReason = .weakSignal }
            } else {
                lossReason = nil
            }
        }
        refreshPresence(at: now)
    }

    func didReadAuthenticatedRSSI(_ rssi: Int16?, at now: ContinuousClock.Instant) {
        guard sessionReady else { return }
        didReadRSSI(rssi, at: now)
    }

    func refreshPresence(at now: ContinuousClock.Instant = ContinuousClock.now) {
        if let lastMacBatteryUpdateAt,
           lastMacBatteryUpdateAt.duration(to: now) >= .seconds(120) {
            macBatteryLevel = nil
            self.lastMacBatteryUpdateAt = nil
        }

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

        _ = presenceTracker.takeWouldLock(at: now)
        guard presenceTracker.isArmed else {
            presenceState = .waiting
            return
        }

        if let remaining = presenceTracker.secondsRemaining(at: now) {
            if remaining == 0 {
                presenceState = .away
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

    private static func loadSavedThreshold(from userDefaults: UserDefaults) -> SignalThreshold? {
        guard let stored = userDefaults.object(forKey: thresholdPreferenceKey) as? Int,
              let value = Int16(exactly: stored) else { return nil }
        return SignalThreshold(validating: value)
    }
}
