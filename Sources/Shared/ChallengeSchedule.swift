import Foundation

enum ChallengeAction: Equatable {
    case sendNew(sequence: UInt32)
    case retry(sequence: UInt32)
}

struct ChallengeSchedule {
    static let sampleInterval: Duration = .seconds(1)
    static let responseTimeout: Duration = .seconds(5)
    static let retryInterval: Duration = .seconds(5)

    private struct OutstandingChallenge {
        let sequence: UInt32
        var firstQueuedAt: ContinuousClock.Instant?
        var lastQueuedAt: ContinuousClock.Instant?
    }

    private var nextSequence: UInt32 = 1
    private var outstanding: OutstandingChallenge?
    private var pendingAction: ChallengeAction?
    private var nextSampleAt: ContinuousClock.Instant?

    mutating func nextAction(at now: ContinuousClock.Instant) -> ChallengeAction? {
        if let pendingAction { return pendingAction }

        if let outstanding {
            guard let lastQueuedAt = outstanding.lastQueuedAt,
                  lastQueuedAt.duration(to: now) >= Self.retryInterval else { return nil }
            let action = ChallengeAction.retry(sequence: outstanding.sequence)
            pendingAction = action
            return action
        }

        guard nextSampleAt.map({ $0 <= now }) ?? true else { return nil }
        let sequence = nextSequence
        nextSequence &+= 1
        outstanding = OutstandingChallenge(sequence: sequence)
        let action = ChallengeAction.sendNew(sequence: sequence)
        pendingAction = action
        return action
    }

    mutating func didQueue(_ action: ChallengeAction, at now: ContinuousClock.Instant) {
        guard pendingAction == action,
              var outstanding,
              outstanding.sequence == action.sequence else { return }

        if outstanding.firstQueuedAt == nil { outstanding.firstQueuedAt = now }
        outstanding.lastQueuedAt = now
        self.outstanding = outstanding
        pendingAction = nil
    }

    mutating func acknowledge(_ sequence: UInt32) {
        acknowledge(sequence, at: ContinuousClock.now)
    }

    mutating func acknowledge(_ sequence: UInt32, at now: ContinuousClock.Instant) {
        guard let outstanding,
              outstanding.sequence == sequence,
              outstanding.lastQueuedAt != nil else { return }

        self.outstanding = nil
        pendingAction = nil
        nextSampleAt = now + Self.sampleInterval
    }

    func responseTimedOut(at now: ContinuousClock.Instant) -> Bool {
        guard let queuedAt = outstanding?.firstQueuedAt else { return false }
        return queuedAt.duration(to: now) >= Self.responseTimeout
    }

    mutating func reset() {
        self = Self()
    }
}

private extension ChallengeAction {
    var sequence: UInt32 {
        switch self {
        case let .sendNew(sequence), let .retry(sequence): sequence
        }
    }
}
