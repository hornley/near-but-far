import Foundation

struct AppScreenPolicy {
    private(set) var state: AppScreenState = .inactive
    private(set) var returnIsArmed = false
    private(set) var dismissalIsLatched = false

    static func pairedPhoneIsDisconnected(
        hasPairedPhone: Bool,
        hasSecureSession: Bool,
        bluetoothIsPoweredOn: Bool
    ) -> Bool {
        hasPairedPhone && !hasSecureSession && bluetoothIsPoweredOn
    }

    mutating func activateManually(whileAway: Bool) {
        state = .active
        if whileAway { returnIsArmed = true }
    }

    mutating func activateAutomatically() -> Bool {
        guard state == .inactive, !dismissalIsLatched else { return false }
        state = .active
        returnIsArmed = true
        return true
    }

    mutating func observeAway() {
        if state == .active { returnIsArmed = true }
    }

    mutating func observeFreshStrongPresence() -> Bool {
        dismissalIsLatched = false
        guard returnIsArmed else { return false }
        state = .inactive
        returnIsArmed = false
        return true
    }

    mutating func dismiss() {
        guard state == .active else { return }
        if returnIsArmed { dismissalIsLatched = true }
        state = .inactive
        returnIsArmed = false
    }
}
