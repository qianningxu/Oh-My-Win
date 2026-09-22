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
                    palette.geistBackground(.primary).opacity(palette.isDark ? 0.12 : 0.18),
                    in: RoundedRectangle(
                        cornerRadius: WinMuxBarStyle.workspaceTabBarCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: WinMuxBarStyle.workspaceTabBarCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        palette.content(.primary).opacity(0.12),
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
