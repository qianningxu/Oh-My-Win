import SwiftUI

struct WindowTabCustomSurface: View {
    let palette: WinMuxOverlayPalette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if !reduceTransparency {
                VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow, opacity: 0.90)
            }
            Color(nsColor: palette.isDark
                ? GeistColorTokens.windowTab100Dark
                : GeistColorTokens.windowTab100Light)
                .opacity(reduceTransparency ? 1 : 0.01)
        }
        .clipShape(Capsule(style: .continuous))
    }
}
