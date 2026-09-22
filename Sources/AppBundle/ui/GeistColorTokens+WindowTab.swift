import AppKit

extension GeistColorTokens {
    // Reference swatches in sRGB; the light highlight is darkened for
    // translucent compositing so it shades the bar instead of whitening it.
    static let windowTab100Dark = NSColor(srgbRed: 45.0 / 255, green: 45.0 / 255, blue: 45.0 / 255, alpha: 1)
    static let windowTab100Light = NSColor(srgbRed: 253.0 / 255, green: 253.0 / 255, blue: 253.0 / 255, alpha: 1)
    static let windowTab200Dark = NSColor(srgbRed: 32.0 / 255, green: 32.0 / 255, blue: 32.0 / 255, alpha: 1)
    static let windowTab200Light = NSColor(srgbRed: 190.0 / 255, green: 190.0 / 255, blue: 190.0 / 255, alpha: 1)
    static let windowTab300Dark = NSColor(srgbRed: 16.0 / 255, green: 16.0 / 255, blue: 16.0 / 255, alpha: 1)
    static let windowTab300Light = NSColor(srgbRed: 96.0 / 255, green: 96.0 / 255, blue: 96.0 / 255, alpha: 1)
}
