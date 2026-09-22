import AppKit

extension GeistColorTokens {
    // Reference swatches in sRGB; the light highlight is darkened for
    // translucent compositing so it shades the bar instead of whitening it.
    static let windowTab100Dark = NSColor(srgbRed: 80.0 / 255, green: 80.0 / 255, blue: 80.0 / 255, alpha: 1)
    static let windowTab100Light = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let windowTab200Dark = NSColor(srgbRed: 32.0 / 255, green: 32.0 / 255, blue: 32.0 / 255, alpha: 1)
    static let windowTab200Light = NSColor(srgbRed: 190.0 / 255, green: 190.0 / 255, blue: 190.0 / 255, alpha: 1)
    static let windowTab300Dark = NSColor(srgbRed: 16.0 / 255, green: 16.0 / 255, blue: 16.0 / 255, alpha: 1)
    static let windowTab300Light = NSColor(srgbRed: 96.0 / 255, green: 96.0 / 255, blue: 96.0 / 255, alpha: 1)
}
