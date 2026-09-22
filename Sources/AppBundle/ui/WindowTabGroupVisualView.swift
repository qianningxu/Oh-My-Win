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
                .background(
                    Color(nsColor: GeistColorTokens.background1Light.nsColor)
                        .opacity(palette.isDark ? 0.25 : 0.60),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                    .strokeBorder(
                        palette.color(.gray, .color10).opacity(palette.isDark ? 0.30 : 0.06),
                        lineWidth: WinMuxBarStyle.strokeWidth
                    )
                }
                .padding(.top, windowTabBarOuterInset())

                Spacer(minLength: WinMuxSpacing.none)
            }
        }
            .allowsHitTesting(false)
    }
}
