import AppKit
import SwiftUI

@main
struct NearButFarMacApp: App {
    @NSApplicationDelegateAdaptor(MacMenuBarAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class MacMenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MacMenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MacMenuBarController()
    }
}
