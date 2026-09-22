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
                    palette.color(palette.activeGeistFamily, .color1),
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
                        winMuxBarForeground(palette).opacity(WinMuxBarStyle.windowBarStrokeOpacity),
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
