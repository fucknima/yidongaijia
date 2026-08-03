import SwiftUI
import UIKit

@MainActor
@main
struct AijiaDirectApp: App {
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
