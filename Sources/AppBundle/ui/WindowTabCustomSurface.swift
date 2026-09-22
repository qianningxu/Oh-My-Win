import SwiftUI

struct WindowTabCustomSurface: View {
    let palette: WinMuxOverlayPalette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if !reduceTransparency {
                VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow)
            }
            Color(nsColor: palette.isDark
                ? GeistColorTokens.gray500Dark.nsColor
                : GeistColorTokens.gray100Light.nsColor)
                .opacity(reduceTransparency ? 1 : (palette.isDark ? 0.72 : 0.60))
        }
        .clipShape(Capsule(style: .continuous))
    }
}
