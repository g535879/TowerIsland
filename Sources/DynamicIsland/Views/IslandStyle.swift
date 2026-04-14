import SwiftUI

/// Visual chrome aligned with the physical notch / camera housing strip: **pure black** base.
enum IslandStyle {
    /// Capsule + expanded panel — matches the notch area (OLED black).
    static let surface = Color.black
    static let strokeOpacity: CGFloat = 0.14

    /// Session cards — subtle lift on black (avoid grey “second surface”).
    static let cardRest = Color.white.opacity(0.06)
    static let cardHover = Color.white.opacity(0.10)
    static let cardStrokeRest: CGFloat = 0.08
    static let cardStrokeHover: CGFloat = 0.14

    /// Nested rows (permission copy, question options, jump chip).
    static let insetFill = Color.white.opacity(0.06)

    /// Code / diff / markdown wells — slightly different depth than `insetFill`.
    static let codeWell = Color.white.opacity(0.05)
}
