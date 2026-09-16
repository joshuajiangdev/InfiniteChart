#if os(macOS)
import AppKit
import SwiftUI
import BTCExampleSupport

@main
enum BTCMacExample {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = BTCExampleAppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class BTCExampleAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit BTC Example", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        NSApplication.shared.mainMenu = menu

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "InfiniteChart · BTC / USD"
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: BTCExampleScreen())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Optional deterministic screenshot for checking the example without UI automation.
        if let option = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.indices.contains(option + 1) {
            let path = CommandLine.arguments[option + 1]
            DispatchQueue.main.async {
                window.contentView?.layoutSubtreeIfNeeded()
                guard let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    fatalError("Could not render example snapshot")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                do {
                    guard let data = bitmap.representation(using: .png, properties: [:]) else {
                        fatalError("Could not encode example snapshot")
                    }
                    try data.write(to: URL(fileURLWithPath: path))
                    NSApplication.shared.terminate(nil)
                } catch {
                    fatalError("Could not save example snapshot: \(error)")
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#else
@main
enum BTCMacExample {
    static func main() {
        print("Run swift run --package-path Examples BTCMacExample on macOS.")
    }
}
#endif
