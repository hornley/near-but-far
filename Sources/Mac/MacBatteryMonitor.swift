import Combine
import Foundation
import IOKit.ps

@MainActor
final class MacBatteryMonitor: ObservableObject {
    @Published private(set) var percentage: UInt8?

    var onRefresh: ((UInt8?) -> Void)?
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    private func refresh() {
        let nextValue = Self.readPercentage()
        if percentage != nextValue { percentage = nextValue }
        onRefresh?(nextValue)
    }

    private static func readPercentage() -> UInt8? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey as String] as? String == (kIOPSInternalBatteryType as String),
                  let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
                  let maximum = description[kIOPSMaxCapacityKey] as? NSNumber else { continue }
            let currentValue = current.intValue
            let maximumValue = maximum.intValue
            guard maximumValue > 0, currentValue >= 0, currentValue <= maximumValue else { continue }
            return UInt8((currentValue * 100) / maximumValue)
        }
        return nil
    }
}
