import SwiftUI

@main
struct BibleShareApp: App {
    /// App-wide auth state, injected into the view hierarchy.
    @State private var authViewModel = AuthViewModel()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
                .environment(router)
        }
    }
}
