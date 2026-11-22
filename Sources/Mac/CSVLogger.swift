import Foundation

final class CSVLogger {
    let fileURL: URL
    private let formatter = ISO8601DateFormatter()
    private let lock = NSLock()

    init() throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NearButFar", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("ble-log.csv")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try "timestamp,event,sequence,rssi_dbm,details\n".write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func log(_ event: String, sequence: UInt32? = nil, rssi: Int16? = nil, details: String = "") {
        let escapedEvent = Self.csv(event)
        let escapedDetails = Self.csv(details)
        let row = "\(formatter.string(from: Date())),\(escapedEvent),\(sequence.map(String.init) ?? ""),\(rssi.map(String.init) ?? ""),\(escapedDetails)\n"
        lock.lock()
        defer { lock.unlock() }
        guard let data = row.data(using: .utf8), let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
