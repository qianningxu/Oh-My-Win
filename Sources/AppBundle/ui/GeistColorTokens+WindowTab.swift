import AppKit

extension GeistColorTokens {
    // Reference swatches in sRGB; the light highlight is darkened for
    // translucent compositing so it shades the bar instead of whitening it.
    static let windowTab100Dark = NSColor(srgbRed: 45.0 / 255, green: 45.0 / 255, blue: 45.0 / 255, alpha: 1)
    static let windowTab100Light = NSColor(srgbRed: 253.0 / 255, green: 253.0 / 255, blue: 253.0 / 255, alpha: 1)
    static let windowTab200Dark = NSColor(srgbRed: 66.0 / 255, green: 66.0 / 255, blue: 66.0 / 255, alpha: 1)
    static let windowTab200Light = NSColor(srgbRed: 222.0 / 255, green: 222.0 / 255, blue: 222.0 / 255, alpha: 1)
}
