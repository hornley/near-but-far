import SwiftUI

@main
struct NearButFarMacApp: App {
    @StateObject private var coordinator = MacCoordinator()

    var body: some Scene {
        MenuBarExtra("Near But Far", systemImage: "dot.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Near But Far").font(.headline)
                Label(coordinator.bluetoothState, systemImage: "wave.3.right")
                Text(coordinator.isSubscribed ? "iPhone subscribed" : "Waiting for iPhone")
                Text(coordinator.lastRSSI.map { "Last RSSI: \($0) dBm" } ?? "Last RSSI: —")
                Text("Test threshold: \(PresenceTracker.weakSignalThreshold) dBm")
                if let countdown = coordinator.countdown {
                    Text("Would lock in: \(countdown)s")
                }
                Divider()
                Text("Local log").font(.caption).foregroundStyle(.secondary)
                Text(coordinator.logPath.isEmpty ? "Unavailable" : coordinator.logPath)
                    .font(.caption2).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text("Prototype only — this app never locks your Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 310, alignment: .leading)
        }
        .menuBarExtraStyle(.window)
    }
}
