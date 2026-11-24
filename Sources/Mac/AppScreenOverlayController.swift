import AppKit
import SwiftUI

@MainActor
final class AppScreenOverlayController: NSObject {
    // Active presentations retain their owner until dismissal or app termination completes cleanup.
    private static var activeController: AppScreenOverlayController?

    private final class OverlayWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private var windows: [String: NSWindow] = [:]
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var screenObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private let onAuthenticate: () -> Void

    init(onAuthenticate: @escaping () -> Void) {
        self.onAuthenticate = onAuthenticate
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcileWindows() }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    func present() {
        guard previousPresentationOptions == nil else {
            reconcileWindows()
            return
        }
        precondition(Self.activeController == nil || Self.activeController === self)
        Self.activeController = self
        previousPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableAppleMenu,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication
        ]
        reconcileWindows()
    }

    func dismiss() {
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
        restorePresentationOptions()
        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    private func reconcileWindows() {
        guard previousPresentationOptions != nil else { return }
        let activeScreens = NSScreen.screens
        let activeIDs = Set(activeScreens.map(Self.identifier(for:)))

        let removedIDs = windows.keys.filter { !activeIDs.contains($0) }
        for identifier in removedIDs {
            windows[identifier]?.orderOut(nil)
            windows.removeValue(forKey: identifier)
        }

        for screen in activeScreens {
            let identifier = Self.identifier(for: screen)
            let window: NSWindow
            if let existing = windows[identifier] {
                window = existing
                window.setFrame(screen.frame, display: true)
            } else {
                let created = OverlayWindow(
                    contentRect: screen.frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                created.level = .screenSaver
                created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                created.isOpaque = true
                created.backgroundColor = NSColor(red: 0.035, green: 0.039, blue: 0.047, alpha: 1)
                created.hasShadow = false
                created.contentView = NSHostingView(rootView: AppScreenView(onAuthenticate: onAuthenticate))
                windows[identifier] = created
                window = created
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restorePresentationOptions() {
        guard let previousPresentationOptions else { return }
        self.previousPresentationOptions = nil
        NSApp.presentationOptions = previousPresentationOptions
    }

    private static func identifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return "screen-\(screen.frame.origin.x)-\(screen.frame.origin.y)-\(screen.frame.width)-\(screen.frame.height)"
    }
}
