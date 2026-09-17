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
    private var videoRecorder: BTCExampleVideoRecorder?

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

        if let option = CommandLine.arguments.firstIndex(of: "--record-video") {
            guard CommandLine.arguments.indices.contains(option + 1),
                  CommandLine.arguments[option + 1].hasPrefix("/") else {
                failRecording("--record-video requires an absolute output path.")
            }
            let path = CommandLine.arguments[option + 1]
            var duration: TimeInterval = 22
            if let durationOption = CommandLine.arguments.firstIndex(of: "--record-duration") {
                guard CommandLine.arguments.indices.contains(durationOption + 1),
                      let value = Double(CommandLine.arguments[durationOption + 1]),
                      value.isFinite, value > 0 else {
                    failRecording("--record-duration requires a positive number of seconds.")
                }
                duration = value
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                guard let view = window.contentView else {
                    failRecording("The example window has no content view.")
                }
                do {
                    let recorder = try BTCExampleVideoRecorder(
                        view: view, outputURL: URL(fileURLWithPath: path), duration: duration
                    ) { result in
                        switch result {
                        case .success:
                            NSApplication.shared.terminate(nil)
                        case let .failure(error):
                            self.failRecording(error.localizedDescription)
                        }
                    }
                    videoRecorder = recorder
                    try recorder.start()
                } catch {
                    failRecording(error.localizedDescription)
                }
            }
            return
        }

        // Optional deterministic screenshot for checking the example without UI automation.
        if let option = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.indices.contains(option + 1) {
            let path = CommandLine.arguments[option + 1]
            DispatchQueue.main.async {
                window.contentView?.layoutSubtreeIfNeeded()
                // The initial layout reports the viewport asynchronously. Allow
                // the provider's detail selection and SwiftUI labels to settle.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
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
    }

    private func failRecording(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Video recording failed: \(message)\n".utf8))
        exit(EXIT_FAILURE)
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
