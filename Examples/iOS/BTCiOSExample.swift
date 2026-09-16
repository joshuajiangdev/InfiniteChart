#if os(iOS)
import UIKit
import SwiftUI
import BTCExampleSupport

@main
final class BTCExampleAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: BTCExampleScreen())
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
#else
@main
enum BTCiOSExample {
    static func main() {
        print("Run ./Examples/run-ios.sh to launch the iOS Simulator example.")
    }
}
#endif
