import SwiftUI

@main
struct NearButFarMacApp: App {
    @StateObject private var peripheral = MacPeripheral()

    var body: some Scene {
        MenuBarExtra("Near But Far", systemImage: "dot.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Near But Far").font(.headline)
                Label(peripheral.bluetoothState, systemImage: "wave.3.right")
                Text(peripheral.isSubscribed ? "iPhone subscribed" : "Waiting for iPhone")
                Text(peripheral.lastRSSI.map { "Last RSSI: \($0) dBm" } ?? "Last RSSI: —")
                Text("Test threshold: \(PresenceTracker.weakSignalThreshold) dBm")
                if let countdown = peripheral.countdown {
                    Text("Would lock in: \(countdown)s")
                }
                Divider()
                Text("Local log").font(.caption).foregroundStyle(.secondary)
                Text(peripheral.logPath.isEmpty ? "Unavailable" : peripheral.logPath)
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
