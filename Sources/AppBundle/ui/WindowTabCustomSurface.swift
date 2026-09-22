import SwiftUI

struct WindowTabCustomSurface: View {
    let palette: WinMuxOverlayPalette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if !reduceTransparency {
                VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow)
            }
            LinearGradient(
                colors: [
                    Color(nsColor: palette.isDark ? GeistColorTokens.windowTab100Dark : GeistColorTokens.windowTab100Light),
                    Color(nsColor: palette.isDark ? GeistColorTokens.windowTab200Dark : GeistColorTokens.windowTab200Light),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(reduceTransparency ? 1 : 0.94)
        }
        .clipShape(Capsule(style: .continuous))
    }
}
