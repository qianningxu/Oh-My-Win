import SwiftUI

/// Shared visual rules for project tabs, workspace tabs, and the widget bar.
enum WinMuxBarStyle {
    static let cornerRadius = standardGap * 4
    static let topBarCornerRadius = standardGap * 4
    static let topBarSurfaceCornerRadius = standardGap * 4
    static let innerSpacing = standardGap * 0.75
    // The outer bar sits 3pt beyond its 16pt tabs, so add that inset to keep
    // the nested continuous curves concentric.
    static let workspaceTabBarCornerRadius = cornerRadius + innerSpacing
    static let containerInset = WinMuxSpacing.comfortable
    static let topBarContentInset = WinMuxSpacing.comfortable
    static let contentInset = innerSpacing * 4
    static let iconSpacing = innerSpacing
    static let strokeWidth = standardGap * 0.25
    static let fontSize: CGFloat = 14
    static let maximumTabWidth = standardGap * 50
    static let projectTabsBarOuterInset = WinMuxSpacing.comfortable
    static let projectTabsBarSurfaceHeight = standardGap * 8 + innerSpacing * 2
    static let projectBarHeight = projectTabsBarSurfaceHeight - innerSpacing * 2 + projectTabsBarOuterInset
    static let workspaceBarHeight = standardGap * 8 + windowTabStripContentPaddingValue * 2
}

struct WinMuxBarDivider: View {
    let height: CGFloat
    let palette: WinMuxOverlayPalette

    var body: some View {
        Rectangle()
            .fill(palette.color(palette.activeGeistFamily, .color6).opacity(0.5))
            .frame(width: WinMuxBarStyle.strokeWidth, height: height)
            .allowsHitTesting(false)
    }
}

func winMuxBarSurfaceFill(_ palette: WinMuxOverlayPalette) -> Color {
    palette.color(palette.activeGeistFamily, .color3)
}

func winMuxBarSurfaceStroke(_ palette: WinMuxOverlayPalette) -> Color {
    palette.color(palette.activeGeistFamily, .color5)
}

extension View {
    func winMuxBarSurface(
        _ palette: WinMuxOverlayPalette,
        joinedToWindow: Bool = false,
        joinsLeadingBar: Bool = false,
        joinsTrailingBar: Bool = false,
        cornerStyle: RoundedCornerStyle = .continuous,
        cornerRadius: CGFloat = WinMuxBarStyle.cornerRadius
    ) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: joinsLeadingBar ? 0 : cornerRadius,
            bottomLeadingRadius: joinedToWindow || joinsLeadingBar ? 0 : cornerRadius,
            bottomTrailingRadius: joinedToWindow || joinsTrailingBar ? 0 : cornerRadius,
            topTrailingRadius: joinsTrailingBar ? 0 : cornerRadius,
            style: cornerStyle
        )
        return self
            .background(winMuxBarSurfaceFill(palette))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(winMuxBarSurfaceStroke(palette), lineWidth: WinMuxBarStyle.strokeWidth)
                    .allowsHitTesting(false)
            }
    }

    func winMuxBarSegment(_ palette: WinMuxOverlayPalette, isSelected: Bool, isHovered: Bool) -> some View {
        background {
            if isSelected {
                Rectangle().fill(palette.geistBackground(.primary))
            } else if isHovered {
                Rectangle().fill(palette.color(palette.activeGeistFamily, .color2))
            }
        }
    }
}
