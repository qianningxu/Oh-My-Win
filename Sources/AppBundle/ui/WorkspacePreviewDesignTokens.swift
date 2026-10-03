import AppKit
import SwiftUI

// Legacy preview colors preserved from fee09168. Keep them separate from
// project-frame tokens: the switcher retains its original macOS HUD appearance.
extension GeistColorTokens {
    static let previewWhite: GeistColorTokenValue = .gray(1)
    static let previewBlack: GeistColorTokenValue = .gray(0)
    static let previewFocusGray: GeistColorTokenValue = .gray(0.5)
}

extension GeistColorTokenValue {
    var swiftUIColor: Color { Color(nsColor: nsColor) }
}

extension WinMuxOverlayPalette {
    var workspacePreviewFocusRing: Color {
        GeistColorTokens.previewFocusGray.swiftUIColor.opacity(0.45)
    }

    var workspacePreviewTileBackground: Color {
        Color(nsColor: NSColor(srgbRed: isDark ? 0.08 : 0.90,
                              green: isDark ? 0.09 : 0.91,
                              blue: isDark ? 0.10 : 0.92, alpha: 1))
    }

    func workspacePreviewFallbackTint(hue: Double, isBottom: Bool) -> Color {
        Color(hue: hue, saturation: isBottom ? 0.28 : 0.42,
              brightness: isBottom ? 0.22 : 0.50)
    }
}
