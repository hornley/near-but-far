import SwiftUI

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusCard

                    Button("Scan again", systemImage: "arrow.clockwise") {
                        central.scanAgain()
                    }
                    .buttonStyle(.bordered)

                    Text("Recent activity")
                        .font(.headline)

                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(central.events.reversed().enumerated()), id: \.offset) { _, event in
                            Text(event)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Near But Far")
        }
        .preferredColorScheme(.dark)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: statusSymbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusTint)
                Text(statusTitle)
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 0)
            }

            if let seconds = countdownSeconds {
                Text(formatDuration(seconds))
                    .font(.system(size: 48, weight: .medium, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if model.presenceState != .unavailable {
                HStack(spacing: 18) {
                    metric(label: "Last RSSI", value: model.lastRSSI.map { "\($0) dBm" } ?? "—")
                    metric(label: "Test threshold", value: "\(PresenceTracker.weakSignalThreshold) dBm")
                }
                .padding(.top, 2)
            }

            Divider()
                .overlay(.white.opacity(0.08))

            Label("Mac lock state unavailable", systemImage: "questionmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Prototype only · Near But Far does not lock your Mac")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var statusTitle: String {
        switch model.presenceState {
        case .waiting: "Waiting for Mac"
        case .nearby: "Nearby"
        case .weakSignalCountdown: "Weak signal"
        case .connectionLostCountdown: "Signal lost"
        case .wouldLock: "Would lock"
        case .unavailable: "Unavailable"
        }
    }

    private var statusDetail: String {
        switch model.presenceState {
        case .waiting: central.connectionState
        case .nearby: "Mac responding · \(central.connectionState)"
        case .weakSignalCountdown: "At or below −70 dBm · phone-side estimate"
        case .connectionLostCountdown: "Connection lost · phone-side estimate"
        case .wouldLock: "Test only · the Mac is not being locked"
        case .unavailable: central.bluetoothState
        }
    }

    private var countdownSeconds: Int? {
        switch model.presenceState {
        case .weakSignalCountdown(let seconds), .connectionLostCountdown(let seconds): seconds
        default: nil
        }
    }

    private var statusSymbol: String {
        switch model.presenceState {
        case .waiting: "dot.radiowaves.left.and.right"
        case .nearby: "dot.radiowaves.left.and.right"
        case .weakSignalCountdown, .connectionLostCountdown: "hourglass"
        case .wouldLock: "hourglass.bottomhalf.filled"
        case .unavailable: "wave.3.right.slash"
        }
    }

    private var statusTint: Color {
        switch model.presenceState {
        case .waiting, .unavailable: .secondary
        case .nearby: .mint
        case .weakSignalCountdown: .orange
        case .connectionLostCountdown: .yellow
        case .wouldLock: .yellow
        }
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
