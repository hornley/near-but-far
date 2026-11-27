import AppKit
import SwiftUI

struct MacMenuBarPanel: View {
    @StateObject private var coordinator = MacCoordinator()
    @State private var menuState = MacMenuState()
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            pageHeader
            switch menuState.page {
            case .home:
                homeView
            case .settings:
                settingsView
            case .pairing:
                PairingView(
                    coordinator: coordinator,
                    menuState: $menuState,
                    onClose: closePairing,
                    onRequestPairing: requestPairing
                )
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    @ViewBuilder
    private var pageHeader: some View {
        HStack {
            Text(pageTitle)
                .font(.headline)
            Spacer()
            switch menuState.page {
            case .home:
                Button("Settings") { menuState.showSettings() }
                    .buttonStyle(.plain)
            case .settings:
                Button("Back") { menuState.showHome() }
                    .buttonStyle(.plain)
            case .pairing:
                Button("Back") { closePairing() }
                    .buttonStyle(.plain)
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Near But Far")
        }
    }

    private var pageTitle: String {
        switch menuState.page {
        case .home: return "Near But Far"
        case .settings: return "Settings"
        case .pairing: return "Pair iPhone"
        }
    }

    private var homeView: some View {
        VStack(spacing: 16) {
            Toggle("Presence monitoring", isOn: $coordinator.monitoringEnabled)
                .toggleStyle(.switch)

            VStack(spacing: 6) {
                Image(systemName: presenceSymbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(coordinator.isSubscribed ? .green : .secondary)
                Text(statusTitle)
                    .font(.title3.weight(.semibold))
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(coordinator.lastRSSI.map { "iPhone signal · \($0) dBm" } ?? "Waiting for iPhone signal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            VStack(spacing: 8) {
                Button("Lock now", systemImage: "lock.fill") {
                    coordinator.activateAppScreen()
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.canLockNow)
            }
            .frame(maxWidth: .infinity)

            Text("App screen · \(coordinator.appScreenState == .active ? "Active" : "Inactive")")
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
            Text("This app screen is a deterrent; it does not lock macOS.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Signal threshold")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(coordinator.signalThreshold.rawValue) dBm")
                        .font(.system(.subheadline, design: .monospaced))
                        .accessibilityLabel("Signal threshold \(coordinator.signalThreshold.rawValue) dBm")
                }
                Slider(value: thresholdBinding, in: -90 ... -50, step: 1)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel("Signal threshold")
                    .accessibilityValue("\(coordinator.signalThreshold.rawValue) dBm")
                Text("This threshold controls presence detection and the app screen; it does not lock macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Pair iPhone", systemImage: "qrcode") {
                openPairing()
            }
            .buttonStyle(.bordered)
            .disabled(!coordinator.pairingCapability.isAvailable)
            .accessibilityHint(coordinator.pairingAvailabilityMessage)
        }
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(coordinator.signalThreshold.rawValue) },
            set: { coordinator.setSignalThreshold(Int16($0)) }
        )
    }

    private func openPairing() {
        menuState.openPairing(returningTo: .settings)
        requestPairing()
    }

    private func requestPairing() {
        switch coordinator.requestPairing() {
        case .pairingStarted, .unavailable:
            break
        case .replacementConfirmationRequired:
            menuState.requestConfirmation(.replacePhone)
        }
    }

    private func closePairing() {
        coordinator.dismissPairingDetails()
        menuState.closePairing()
    }

    private var presenceSymbol: String {
        if !coordinator.monitoringEnabled { return "pause.circle" }
        if coordinator.isSubscribed { return "iphone.gen3.radiowaves.left.and.right" }
        return "iphone.slash"
    }

    private var statusTitle: String {
        if coordinator.bluetoothState != "Bluetooth on" {
            return coordinator.bluetoothState.hasPrefix("Starting") ? "Starting Bluetooth" : "Bluetooth unavailable"
        }
        if !coordinator.monitoringEnabled { return "Monitoring off" }
        if coordinator.appScreenState == .active { return "App screen active" }
        if coordinator.countdown != nil { return "Presence lost" }
        return coordinator.isSubscribed ? "iPhone nearby" : "Waiting for iPhone"
    }

    private var statusDetail: String {
        if coordinator.bluetoothState != "Bluetooth on" { return "Turn on Bluetooth on this Mac to resume monitoring." }
        if !coordinator.monitoringEnabled { return "Presence monitoring is off." }
        if let countdown = coordinator.countdown, countdown > 0 { return "\(countdown) seconds remaining" }
        if coordinator.isSubscribed { return "Authenticated phone presence received." }
        return "No authenticated phone presence yet."
    }
}
