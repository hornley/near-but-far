import SwiftUI

struct RecentActivityView: View {
    let events: [String]

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView("No local activity yet.", systemImage: "clock")
            } else {
                List {
                    ForEach(Array(events.reversed().enumerated()), id: \.offset) { _, event in
                        RecentActivityRow(event: event)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Recent activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .statusBarHidden(false)
    }
}

private struct RecentActivityRow: View {
    let event: String

    private var parts: (timestamp: String, label: String) {
        guard let separator = event.range(of: "  ") else { return ("", event) }
        let timestamp = String(event[..<separator.lowerBound])
        let value = String(event[separator.upperBound...])
        let labels: [String: String] = [
            "scan_started": "Scanning for Mac",
            "connected": "Bluetooth connected",
            "connect_failed": "Bluetooth connection failed",
            "disconnected": "Bluetooth disconnected",
            "core_bluetooth_restored": "Bluetooth restored",
            "invalid_pairing_qr": "QR code not recognized",
            "pairing_expired": "Pairing expired",
            "secure_session_closed": "Secure session closed"
        ]
        if value.hasPrefix("bluetooth_") {
            var recordedState = value.dropFirst("bluetooth_".count)
            if recordedState.hasPrefix("bluetooth_") {
                recordedState = recordedState.dropFirst("bluetooth_".count)
            }
            let state = recordedState
                .split(separator: "_").map { $0.capitalized }.joined(separator: " ")
            return (timestamp, "Bluetooth: \(state)")
        }
        return (timestamp, labels[value] ?? value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(parts.label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            if !parts.timestamp.isEmpty {
                Text(parts.timestamp)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
