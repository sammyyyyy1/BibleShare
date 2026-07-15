import SwiftUI

enum Theme {
    static let cream    = Color(red: 0.980, green: 0.965, blue: 0.937) // #FAF6EF
    static let ink      = Color(red: 0.118, green: 0.106, blue: 0.294) // #1E1B4B
    static let indigo   = Color(red: 0.192, green: 0.180, blue: 0.506) // #312E81
    static let muted    = Color(red: 0.471, green: 0.443, blue: 0.424) // #78716C
    static let field    = Color.white                                   // #FFFFFF
    static let hairline = Color(red: 0.906, green: 0.878, blue: 0.835) // #E7E0D5
    static let success  = Color(red: 0.086, green: 0.639, blue: 0.290) // #16A34A
    static let danger   = Color(red: 0.863, green: 0.149, blue: 0.149) // #DC2626

    static let corner: CGFloat = 12
    static var wordmark: Font { .system(.largeTitle, design: .serif).weight(.bold) }
}
