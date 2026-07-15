import SwiftUI

@main
struct BibleShareApp: App {
    /// App-wide auth state, injected into the view hierarchy.
    @State private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
        }
    }
}
