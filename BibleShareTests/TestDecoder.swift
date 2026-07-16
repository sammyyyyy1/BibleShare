import Foundation

/// Decoder matching Supabase's PostgREST timestamps (ISO8601, with or without
/// fractional seconds). Mirrors the decoder used in the Plan 1 model tests.
enum TestDecoder {
    static func postgrest() -> JSONDecoder {
        let d = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "bad date \(s)"))
        }
        return d
    }
}
