import Foundation

/// Client-side username format check. MUST match the DB constraint
/// `^[A-Za-z0-9_]{3,20}$` in supabase/migrations/*_auth_onboarding.sql.
enum UsernameValidator {
    static let pattern = "^[A-Za-z0-9_]{3,20}$"

    static func isValidFormat(_ candidate: String) -> Bool {
        candidate.range(of: pattern, options: .regularExpression) != nil
    }
}
