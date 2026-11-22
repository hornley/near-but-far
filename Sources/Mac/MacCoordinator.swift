import Combine
import Foundation

final class MacCoordinator: ObservableObject {
    @Published private(set) var bluetoothState = "Starting Bluetooth…"
    @Published private(set) var isSubscribed = false
    @Published private(set) var lastRSSI: Int16?
    @Published private(set) var countdown: Int?
    @Published private(set) var logPath = ""

    private let peripheral: MacPeripheral
    private let logger: CSVLogger?
    private var schedule = ChallengeSchedule()
    private var tracker = PresenceTracker()
    private var outstandingSequence: UInt32?
    private var queueBlocked = false
    private var challengeTimer: Timer?
    private var displayTimer: Timer?

    init(peripheral: MacPeripheral = MacPeripheral()) {
        self.peripheral = peripheral
        do {
            logger = try CSVLogger()
            logPath = logger?.fileURL.path ?? ""
        } catch {
            logger = nil
            bluetoothState = "Log unavailable: \(error.localizedDescription)"
        }
        peripheral.onEvent = { [weak self] event in self?.handle(event) }
        scheduleChallengeTick(after: 1)
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshDisplay()
        }
    }

    private func scheduleChallengeTick(after interval: TimeInterval) {
        challengeTimer?.invalidate()
        challengeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.tick()
        }
    }

    private func handle(_ event: MacTransportEvent) {
        switch event {
        case let .bluetoothState(state):
            bluetoothState = state
            logger?.log("bluetooth_state", details: state)
            if state != "Bluetooth on" {
                isSubscribed = false
                schedule.reset()
                outstandingSequence = nil
                queueBlocked = false
                tracker = PresenceTracker()
                countdown = nil
            }
        case let .subscriptionChanged(isSubscribed):
            self.isSubscribed = isSubscribed
            logger?.log(isSubscribed ? "subscribed" : "unsubscribed")
            if isSubscribed { tick() }
        case .readyToUpdate:
            queueBlocked = false
            tick()
        case let .log(event, details):
            logger?.log(event, details: details)
        case let .acknowledgement(acknowledgement, respond):
            respond(receive(acknowledgement) ? .success : .invalidAttributeValueLength)
        }
    }

    private func tick() {
        defer { scheduleChallengeTick(after: 1) }
        let now = ContinuousClock.now
        if schedule.responseTimedOut(at: now), tracker.isArmed, tracker.lossStartedAt == nil {
            tracker.missedChallenge(at: now)
            logger?.log("missed_response", sequence: outstandingSequence)
        }
        guard isSubscribed, !queueBlocked, let action = schedule.nextAction(at: now) else {
            refreshDisplay()
            return
        }
        guard peripheral.publish(action) else {
            if !queueBlocked { logger?.log("challenge_queue_full", sequence: action.sequence) }
            queueBlocked = true
            refreshDisplay()
            return
        }
        queueBlocked = false
        schedule.didQueue(action, at: now)
        outstandingSequence = action.sequence
        logger?.log(action.isRetry ? "challenge_retransmitted" : "challenge_queued", sequence: action.sequence)
        refreshDisplay()
    }

    private func receive(_ acknowledgement: BLEProtocol.Acknowledgement) -> Bool {
        guard let expected = outstandingSequence, acknowledgement.sequence == expected else {
            logger?.log("invalid_acknowledgement")
            return false
        }
        let now = ContinuousClock.now
        let wasCountingDown = tracker.lossStartedAt != nil
        schedule.acknowledge(acknowledgement.sequence, at: now)
        tracker.observeRSSI(acknowledgement.rssi, at: now)
        lastRSSI = acknowledgement.rssi
        if !wasCountingDown, tracker.lossStartedAt != nil, let rssi = acknowledgement.rssi {
            logger?.log("weak_signal", sequence: acknowledgement.sequence, rssi: rssi,
                        details: "threshold_dbm=\(PresenceTracker.weakSignalThreshold)")
        } else if wasCountingDown, tracker.lossStartedAt == nil, let rssi = acknowledgement.rssi {
            logger?.log("signal_recovered", sequence: acknowledgement.sequence, rssi: rssi)
        }
        logger?.log("acknowledgement", sequence: acknowledgement.sequence, rssi: acknowledgement.rssi,
                    details: acknowledgement.rssi == nil ? "rssi_unavailable" : "")
        outstandingSequence = nil
        refreshDisplay(at: now)
        scheduleChallengeTick(after: 1)
        return true
    }

    private func refreshDisplay(at now: ContinuousClock.Instant = .now) {
        countdown = tracker.secondsRemaining(at: now)
        if tracker.takeWouldLock(at: now), let started = tracker.lossStartedAt {
            logger?.log("would_lock", sequence: outstandingSequence,
                        details: "elapsed_seconds=\(started.duration(to: now).components.seconds)")
        }
    }
}
