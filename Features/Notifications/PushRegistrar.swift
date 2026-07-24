import Foundation
import UIKit

/// Bridges the APNs device-token callback to `device_tokens`. Everything here
/// is best-effort: without a provisioning profile the simulator's registration
/// simply fails, and that must never surface to the user or block auth.
@MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()

    private let service: NotificationServicing
    private var currentToken: String?

    init(service: NotificationServicing = NotificationService.shared) {
        self.service = service
    }

    /// Called after sign-in. Authorization is requested here — the point of
    /// value — rather than at launch.
    func registerAfterLogin() async {
        guard await CheckinReminderScheduler.requestAuthorization() else { return }
        // Immediately after the grant, so reminders that a group list load
        // skipped earlier (permission still undecided at the time) get
        // scheduled now, rather than waiting for another load to happen.
        await CheckinReminderScheduler.resyncLastKnown()
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        currentToken = token
        do { try await service.registerDeviceToken(token) } catch {
            // A dead token is recoverable on the next launch; never surface it.
            print("[push] token registration failed: \(error)")
        }
    }

    func didFailToRegister(error: Error) {
        // Expected on the simulator and without a provisioning profile.
        print("[push] remote notification registration unavailable: \(error)")
    }

    /// Called before sign-out, while the session can still authorize the RPC.
    func unregisterBeforeLogout() async {
        guard let token = currentToken else { return }
        try? await service.unregisterDeviceToken(token)
        currentToken = nil
    }
}
