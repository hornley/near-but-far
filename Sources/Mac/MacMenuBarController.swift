import AppKit
import SwiftUI

final class MacMenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let quitMenu = NSMenu()
    private var hostingController: NSHostingController<MacMenuBarPanel>!

    override init() {
        super.init()
        hostingController = NSHostingController(rootView: MacMenuBarPanel(onClose: { }))
        hostingController.rootView = MacMenuBarPanel(onClose: { [weak self] in self?.closePopover() })

        popover.behavior = .transient
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "Near But Far")
            button.setAccessibilityLabel("Near But Far")
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "Show Quit menu", target: self, selector: #selector(showQuitMenuFromAccessibility))
            ])
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem.target = self
            statusItem.action = #selector(handleStatusItemClick(_:))
        }

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        quitMenu.addItem(quitItem)
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        switch event.type {
        case .rightMouseUp:
            showQuitMenu()
        case .leftMouseUp where event.modifierFlags.contains(.control):
            showQuitMenu()
        case .leftMouseUp:
            togglePopover()
        default:
            break
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func showQuitMenu() {
        closePopover()
        guard let button = statusItem.button else { return }
        quitMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
    }

    @objc private func showQuitMenuFromAccessibility() -> Bool {
        showQuitMenu()
        return true
    }
}
