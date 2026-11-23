import AppKit
import SwiftUI

@main
struct NearButFarMacApp: App {
    @StateObject private var coordinator = MacCoordinator()
    @State private var showingSettings = false

    var body: some Scene {
        MenuBarExtra("Near But Far", systemImage: "dot.radiowaves.left.and.right") {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Text(showingSettings ? "Settings" : "Near But Far")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingSettings.toggle()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")

                    Button {
                        NSApp.keyWindow?.close()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Near But Far")
                }

                if showingSettings {
                    settingsView
                } else {
                    homeView
                }
            }
            .padding(16)
            .frame(width: 320)
            .sheet(isPresented: pairingSheetBinding) {
                PairingView(coordinator: coordinator)
            }
        }
        .menuBarExtraStyle(.window)
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
                Button("Lock now", systemImage: "lock.fill") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                Button("Unlock", systemImage: "lock.open") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            }
            .frame(maxWidth: .infinity)

            Text("Locking is unavailable on this Mac.")
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
                    .accessibilityLabel("Signal threshold")
                    .accessibilityValue("\(coordinator.signalThreshold.rawValue) dBm")
                Text("Changing this threshold does not make locking available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Pair iPhone", systemImage: "qrcode") {
                coordinator.requestPairing()
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

    private var pairingSheetBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isPairingPresented },
            set: { isPresented in
                if isPresented {
                    coordinator.isPairingPresented = true
                } else {
                    coordinator.dismissPairingDetails()
                }
            }
        )
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
        if let countdown = coordinator.countdown { return countdown == 0 ? "Lock unavailable" : "Presence lost" }
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
