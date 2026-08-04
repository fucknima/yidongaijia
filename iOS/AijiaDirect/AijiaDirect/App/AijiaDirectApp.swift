import SwiftUI
import UIKit

final class AijiaDirectAppDelegate: NSObject, UIApplicationDelegate {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
}

@MainActor
@main
struct AijiaDirectApp: App {
    @UIApplicationDelegateAdaptor(AijiaDirectAppDelegate.self) private var appDelegate
    @StateObject private var playerModel = PlayerViewModel()

    init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        DiagnosticsLogger.shared.info(
            "APP",
            "应用启动 version=\(version) ios=\(UIDevice.current.systemVersion) device=\(UIDevice.current.model)"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: playerModel)
        }
    }
}
