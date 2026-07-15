import Foundation

/// UI status for the live username availability check.
enum UsernameStatus: Equatable, Sendable {
    case idle, checking, available, taken, invalid
}

/// Maps thrown auth errors to a short, user-facing message.
func mapAuthError(_ error: Error) -> String {
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut:
            return "No internet connection. Please try again."
        default:
            return "Network error. Please try again."
        }
    }

    let text = error.localizedDescription.lowercased()
    if text.contains("already registered") || text.contains("already been registered") {
        return "That email is already registered. Try signing in."
    }
    if text.contains("invalid login") || text.contains("invalid credentials") {
        return "Incorrect email or password."
    }
    if text.contains("password") && text.contains("short") {
        return "Password must be at least 6 characters."
    }
    return error.localizedDescription
}
