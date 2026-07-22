import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushRegistrar.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushRegistrar.shared.didFailToRegister(error: error) }
    }
}

@main
struct BibleShareApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// App-wide auth state, injected into the view hierarchy.
    @State private var authViewModel = AuthViewModel()
    /// Added in Task 8 — keep it; RootTabView's selection binding depends on it.
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
                .environment(router)
        }
    }
}
