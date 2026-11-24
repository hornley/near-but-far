import SwiftUI
import UIKit

@main
struct NearButFarPhoneApp: App {
    @StateObject private var central = PhoneCentral()

    var body: some Scene {
        WindowGroup {
            PhoneContentView()
                .environmentObject(central)
                .environmentObject(central.model)
        }
    }
}

private struct PhoneContentView: View {
    @EnvironmentObject private var central: PhoneCentral
    @EnvironmentObject private var model: PhoneModel
    @State private var showsActivityScreen = false
    @State private var showsStatusDetails = false
    @State private var showsPairing = false
    @ScaledMetric(relativeTo: .largeTitle) private var statusTitlePointSize = 60.0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .center, spacing: 24) {
                        statusCard
                        lockActions
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .center)
                }
                .background(Color.black.ignoresSafeArea())
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Near But Far")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Pair a Mac", systemImage: "qrcode.viewfinder") {
                            central.beginPairing()
                            showsPairing = true
                        }
                        Button("Scan again", systemImage: "arrow.clockwise") {
                            central.scanAgain()
                        }
                        Button("Status details", systemImage: "info.circle") {
                            showsStatusDetails = true
                        }
                        Button("Recent activity", systemImage: "clock") {
                            showsActivityScreen = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More options")
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(isPresented: $showsActivityScreen) {
                RecentActivityView(events: central.events)
            }
            .navigationDestination(isPresented: $showsStatusDetails) {
                statusDetailsScreen
                    .navigationTitle("Status details")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsPairing, onDismiss: central.cancelPairing) {
            PairingScannerView(state: pairingPresentationState,
                               onPayload: central.acceptScannedPayload,
                               onCameraUnavailable: central.cameraUnavailable,
                               onRetry: central.retryPairing,
                               onCancel: { showsPairing = false })
        }
        .onChange(of: statusTitle) { _, title in
            UIAccessibility.post(notification: .announcement, argument: title)
        }
        .onChange(of: macMonitoringTitle) { _, title in
            UIAccessibility.post(notification: .announcement, argument: "Mac monitoring: \(title)")
        }
        .onChange(of: appScreenTitle) { _, title in
            UIAccessibility.post(notification: .announcement, argument: "App screen: \(title)")
        }
        .onChange(of: pairingTitle) { _, title in
            UIAccessibility.post(notification: .announcement, argument: "Pairing: \(title)")
        }
    }

    private var statusCard: some View {
        VStack(spacing: 4) {
            Text(statusTitle)
                .font(.system(size: statusTitlePointSize, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            if let countdownSeconds {
                Text(formatDuration(countdownSeconds))
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Text(signalSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let statusContext {
                Text(statusContext)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusCardAccessibilityLabel)
    }

    private var statusDetailsScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statusRows
                Text("The home button shows or dismisses the app screen; it does not lock or unlock macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var statusRows: some View {
        VStack(spacing: 0) {
            pairingRow
            Divider().overlay(.white.opacity(0.16))
            statusRow("Mac monitoring", value: macMonitoringTitle)
            Divider().overlay(.white.opacity(0.16))
            statusRow("App screen", value: appScreenTitle)
        }
    }

    private var pairingRow: some View {
        HStack(spacing: 8) {
            Text("Pairing")
                .font(.caption)
            Spacer(minLength: 8)
            Text(pairingTitle)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Pairing status: \(pairingTitle)")
            if central.canRetryConnection {
                Button("Retry", action: central.retryPairing)
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Retry connection")
                    .accessibilityHint("Reconnect to the saved Mac.")
            }
        }
        .frame(minHeight: 44)
    }

    private func statusRow(_ title: String, value: String, accessibilityValue: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(accessibilityValue ?? value)")
    }

    private var lockActions: some View {
        Button(action: toggleAppScreen) {
            Text(appScreenActionTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(appScreenActionForeground)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(appScreenActionBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!central.canSendAppScreenCommand)
        .accessibilityLabel(appScreenActionTitle)
        .accessibilityHint(appScreenActionHint)
    }

    private var appScreenActionTitle: String {
        switch model.appScreenDisplayState {
        case .active: "Unlock"
        case .inactive: "Lock now"
        case .unavailable: "App screen unavailable"
        }
    }

    private var appScreenActionBackground: Color {
        guard central.canSendAppScreenCommand else { return Color(uiColor: .tertiarySystemBackground) }
        switch model.appScreenDisplayState {
        case .active: return .green
        case .inactive: return .red
        case .unavailable: return Color(uiColor: .tertiarySystemBackground)
        }
    }

    private var appScreenActionForeground: Color {
        central.canSendAppScreenCommand ? .black : .secondary
    }

    private var appScreenActionHint: String {
        switch model.appScreenDisplayState {
        case .active: "Dismiss the app-owned Mac screen. This does not unlock macOS."
        case .inactive: "Show the app-owned Mac screen. This does not lock macOS."
        case .unavailable: "Connect to the paired Mac to control its app screen."
        }
    }

    private func toggleAppScreen() {
        guard central.canSendAppScreenCommand else { return }
        switch model.appScreenDisplayState {
        case .active: central.dismissAppScreen()
        case .inactive: central.activateAppScreen()
        case .unavailable: break
        }
    }

    private var statusTitle: String {
        switch model.presenceState {
        case .waiting: "Waiting for Mac"
        case .nearby: "Nearby"
        case .weakSignalCountdown: "Weak signal"
        case .connectionLostCountdown: "Signal lost"
        case .away: "Away"
        case .unavailable: "Unavailable"
        }
    }

    private var statusContext: String? {
        switch model.presenceState {
        case .waiting:
            return central.connectionState.isEmpty ? nil : central.connectionState
        case .nearby:
            return nil
        case .weakSignalCountdown(_):
            return "Signal is at or below threshold"
        case .connectionLostCountdown(_):
            return "No fresh response · local estimate"
        case .away:
            return "Phone appears away · local estimate"
        case .unavailable:
            let context = central.bluetoothState == "Bluetooth on" ? central.connectionState : central.bluetoothState
            return context.isEmpty ? nil : context
        }
    }

    private var countdownSeconds: Int? {
        switch model.presenceState {
        case .weakSignalCountdown(let seconds), .connectionLostCountdown(let seconds): seconds
        default: nil
        }
    }

    private var statusCardAccessibilityLabel: String {
        let countdown = countdownSeconds.map { "\(formatDuration($0)) remaining. " } ?? ""
        let context = statusContext.map { "\($0). " } ?? ""
        return "Phone presence: \(statusTitle). \(countdown)\(context)\(signalSummaryAccessibility)"
    }

    private var pairingTitle: String {
        switch pairingPresentationState {
        case .unpaired: "Not paired"
        case .scanning: central.bluetoothIsAvailable ? "Scanning for Mac" : "Bluetooth unavailable"
        case .waitingForMacApproval: central.bluetoothIsAvailable ? "Waiting for Mac approval" : "Bluetooth unavailable"
        case .paired: model.sessionReady ? "Paired" : "Reconnecting"
        case .expired: "Pairing expired"
        case .qrMismatch: "QR identity mismatch"
        case .untrustedMac: "Mac identity mismatch"
        case .cameraUnavailable: "Camera unavailable"
        case .storageUnavailable: "Secure storage unavailable"
        case .bluetoothUnavailable: "Bluetooth unavailable"
        }
    }

    private var macMonitoringTitle: String {
        guard let status = model.authenticatedMacStatus else { return "Unavailable" }
        switch status {
        case .unavailable: return "Off"
        case .waiting: return "Waiting for iPhone"
        case .nearby: return "Nearby"
        case .weakSignal: return "Weak signal"
        case .signalLost: return "Signal lost"
        }
    }

    private var appScreenTitle: String {
        switch model.appScreenDisplayState {
        case .active: "Active"
        case .inactive: "Inactive"
        case .unavailable: "Unavailable"
        }
    }

    private var signalSummary: String {
        let reading = model.lastRSSI.map { "\($0) dBm" } ?? "— dBm"
        let signal = model.sessionReady ? reading : (model.lastRSSI.map { "Last \($0) dBm" } ?? reading)
        if model.hasReceivedThresholdForSession, let threshold = model.signalThreshold {
            return "\(signal) · threshold \(threshold.rawValue) dBm"
        }
        if model.sessionReady {
            return "\(signal) · threshold syncing"
        }
        if let threshold = model.signalThreshold {
            return "\(signal) · threshold \(threshold.rawValue) dBm last synced"
        }
        return "\(signal) · threshold unavailable"
    }

    private var signalSummaryAccessibility: String {
        let reading = model.lastRSSI.map { "\($0) dBm" } ?? "unavailable"
        let signal = model.sessionReady ? "Latest signal, \(reading)" : "Last signal, \(reading)"
        if model.hasReceivedThresholdForSession, let threshold = model.signalThreshold {
            return "\(signal). Current authenticated Mac signal threshold, \(threshold.rawValue) dBm. Read only."
        }
        if model.sessionReady {
            return "\(signal). Waiting for the authenticated Mac signal threshold."
        }
        if let threshold = model.signalThreshold {
            return "\(signal). Last synced Mac signal threshold, \(threshold.rawValue) dBm. Read only."
        }
        return "\(signal). Mac signal threshold unavailable. Waiting for an authenticated sync."
    }

    private var pairingPresentationState: PairingScannerState {
        guard !central.bluetoothIsAvailable else { return central.pairingState }
        switch central.pairingState {
        case .scanning, .waitingForMacApproval, .qrMismatch, .untrustedMac: return .bluetoothUnavailable
        default: return central.pairingState
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
