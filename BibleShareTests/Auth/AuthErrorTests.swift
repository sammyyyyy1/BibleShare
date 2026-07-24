import Testing
import Foundation
@testable import BibleShare

struct AuthErrorTests {
    @Test func mapsNetworkError() {
        let err = URLError(.notConnectedToInternet)
        #expect(mapAuthError(err).localizedCaseInsensitiveContains("connection"))
    }

    @Test func fallsBackForUnknown() {
        struct Weird: Error {}
        #expect(!mapAuthError(Weird()).isEmpty)
    }
}
