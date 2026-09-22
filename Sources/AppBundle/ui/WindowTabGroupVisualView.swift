import SwiftUI

struct WindowTabGroupVisualView: View {
    let strip: WindowTabStripViewModel

    @ObservedObject private var trayModel = TrayMenuModel.shared
    @Environment(\.colorScheme) private var colorScheme
    private var palette: WinMuxOverlayPalette { trayModel.projectPalette(workspaceName: strip.workspaceName, colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: WinMuxSpacing.none) {
                WinMuxDesignTokens.transparent
                .frame(
                    width: max(geometry.size.width - windowTabGroupShellHorizontalInset() * 2, 0),
                    height: min(WinMuxBarStyle.workspaceBarHeight, geometry.size.height)
                )
                .background {
                    WindowTabCustomSurface(palette: palette)
                }
                .overlay {
                    Capsule(style: .continuous)
                    .strokeBorder(
                        Color(nsColor: palette.isDark
                            ? GeistColorTokens.windowTab300Dark
                            : GeistColorTokens.windowTab300Light)
                            .opacity(0.60),
                        lineWidth: WinMuxBarStyle.strokeWidth * 0.25
                    )
                }
                .padding(.top, windowTabBarOuterInset())

                Spacer(minLength: WinMuxSpacing.none)
            }
        }
            .allowsHitTesting(false)
    }
}
