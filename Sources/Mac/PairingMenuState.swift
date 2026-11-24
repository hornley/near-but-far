enum MacMenuPage: Equatable {
    case home
    case settings
    case pairing
}

enum PairingConfirmation: Equatable {
    case forgetPhone
    case replacePhone
}

enum PairingRequestResult: Equatable {
    case pairingStarted
    case replacementConfirmationRequired
    case unavailable
}

struct MacMenuState: Equatable {
    private(set) var page: MacMenuPage = .home
    private(set) var pairingReturnPage: MacMenuPage = .settings
    private(set) var confirmation: PairingConfirmation?

    mutating func showHome() {
        guard page != .pairing else { return }
        page = .home
    }

    mutating func showSettings() {
        guard page != .pairing else { return }
        page = .settings
    }

    mutating func openPairing(returningTo page: MacMenuPage) {
        pairingReturnPage = page
        confirmation = nil
        self.page = .pairing
    }

    mutating func requestConfirmation(_ confirmation: PairingConfirmation) {
        guard page == .pairing else { return }
        self.confirmation = confirmation
    }

    mutating func cancelConfirmation() {
        confirmation = nil
    }

    mutating func confirm() -> PairingConfirmation? {
        defer { confirmation = nil }
        return confirmation
    }

    mutating func closePairing() {
        confirmation = nil
        page = pairingReturnPage
    }
}
