import Foundation

/// Loads runtime configuration from the bundled `Secrets.plist`.
///
/// `Secrets.plist` is git-ignored. Copy `Secrets.plist.example` to `Secrets.plist`
/// and fill in your Supabase project values before building.
struct AppSecrets {
    let supabaseURL: URL
    let supabaseAnonKey: String

    static func load() -> AppSecrets {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(
                from: data, format: nil
              ) as? [String: Any]
        else {
            fatalError(
                "Secrets.plist not found. Copy Secrets.plist.example to Resources/Secrets.plist and fill it in."
            )
        }

        guard let urlString = dict["SUPABASE_URL"] as? String,
              let supabaseURL = URL(string: urlString),
              !urlString.isEmpty,
              let anonKey = dict["SUPABASE_ANON_KEY"] as? String,
              !anonKey.isEmpty
        else {
            fatalError("Secrets.plist is missing SUPABASE_URL or SUPABASE_ANON_KEY.")
        }

        return AppSecrets(supabaseURL: supabaseURL, supabaseAnonKey: anonKey)
    }
}
