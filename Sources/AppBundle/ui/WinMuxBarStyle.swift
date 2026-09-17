import AppKit
import SwiftUI

/// Shared visual rules for workspace tabs, window tabs, and the widget bar.
enum WinMuxBarStyle {
    static let cornerRadius = standardGap * 4
    static let topBarCornerRadius = standardGap * 4
    static let topBarSurfaceCornerRadius = standardGap * 4
    static let innerSpacing = standardGap * 0.75
    static let containerInset = WinMuxSpacing.comfortable
    static let topBarContentInset = WinMuxSpacing.compact
    static let contentInset = innerSpacing * 4
    static let iconSpacing = innerSpacing
    static let strokeWidth = standardGap * 0.25
    static let fontSize: CGFloat = 14
    static let maximumTabWidth = standardGap * 50
    static let projectTabsBarOuterInset = WinMuxSpacing.regular
    static let projectTabsBarContentHeight = standardGap * 12
    static let projectTabsBarHorizontalInset = WinMuxSpacing.panel
    static let projectTabsBarFontSize = fontSize + WinMuxSpacing.hairline
    static let projectBarCornerRadius = projectTabsBarContentHeight / 2
    static let projectBarHeight = projectTabsBarContentHeight + projectTabsBarOuterInset
    static let projectBarTintOpacity: CGFloat = 0.30
    static let projectBarStrokeOpacity: CGFloat = 0.28
    static let workspaceTabContentHeight = standardGap * 8
    static let workspaceBarHeight = workspaceTabContentHeight + windowTabStripContentPaddingValue * 2
    static let workspaceTabCornerRadius = cornerRadius
    static let workspaceTabBarCornerRadius = cornerRadius + innerSpacing
    static let workspaceBarTintOpacity: CGFloat = 0.25
    static let workspaceBarStrokeOpacity: CGFloat = 0.24
    static let topBarTintOpacity: CGFloat = 0.05
    static let topBarStrokeOpacity: CGFloat = 0.2
    static let workspaceSelectedSegmentOpacity: CGFloat = 0.75
    static let windowTabHoveredSegmentOpacity: CGFloat = 0.20
    static let selectedSegmentOpacity: CGFloat = 0.18
    static let hoveredSegmentOpacity: CGFloat = 0.08
}

struct WinMuxBarDivider: View {
    let height: CGFloat
    let palette: WinMuxOverlayPalette

    var body: some View {
        Rectangle()
            .fill(winMuxBarForeground(palette).opacity(0.5))
            .frame(width: WinMuxBarStyle.strokeWidth, height: height)
            .allowsHitTesting(false)
    }
}

func winMuxBarSurfaceFill(_ palette: WinMuxOverlayPalette) -> Color {
    palette.isDark ? .black : .white
}

func winMuxBarSurfaceStroke(_ palette: WinMuxOverlayPalette) -> Color {
    winMuxBarForeground(palette)
}

func winMuxBarForeground(_ palette: WinMuxOverlayPalette) -> Color {
    palette.isDark ? .white : .black
}

func winMuxBarForegroundNSColor(_ palette: WinMuxOverlayPalette) -> NSColor {
    palette.isDark ? .white : .black
}

private struct WinMuxGlassBarSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let palette: WinMuxOverlayPalette
    let cornerRadius: CGFloat
    let material: NSVisualEffectView.Material
    let tintOpacity: CGFloat
    let strokeOpacity: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(winMuxBarSurfaceFill(palette))
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        winMuxBarSurfaceStroke(palette),
                        lineWidth: WinMuxBarStyle.strokeWidth
                    )
                    .allowsHitTesting(false)
                }
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .clear.tint(winMuxBarSurfaceFill(palette).opacity(tintOpacity)),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        winMuxBarSurfaceStroke(palette).opacity(strokeOpacity),
                        lineWidth: WinMuxBarStyle.strokeWidth
                    )
                    .allowsHitTesting(false)
                }
        } else {
            content
                .background {
                    ZStack {
                        VisualEffectBlur(material: material, blendingMode: .behindWindow)
                        winMuxBarSurfaceFill(palette).opacity(tintOpacity)
                    }
                    .clipShape(shape)
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        winMuxBarSurfaceStroke(palette).opacity(strokeOpacity),
                        lineWidth: WinMuxBarStyle.strokeWidth
                    )
                    .allowsHitTesting(false)
                }
        }
    }
}

extension View {
    func winMuxGlassBarSurface(
        _ palette: WinMuxOverlayPalette,
        cornerRadius: CGFloat = WinMuxBarStyle.projectBarCornerRadius,
        material: NSVisualEffectView.Material = .underWindowBackground,
        tintOpacity: CGFloat = WinMuxBarStyle.projectBarTintOpacity,
        strokeOpacity: CGFloat = WinMuxBarStyle.projectBarStrokeOpacity
    ) -> some View {
        modifier(WinMuxGlassBarSurfaceModifier(
            palette: palette,
            cornerRadius: cornerRadius,
            material: material,
            tintOpacity: tintOpacity,
            strokeOpacity: strokeOpacity
        ))
    }

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

    func winMuxBarSegment(
        _ palette: WinMuxOverlayPalette,
        isSelected: Bool,
        isHovered: Bool,
        selectedOpacity: CGFloat = WinMuxBarStyle.selectedSegmentOpacity,
        hoveredOpacity: CGFloat = WinMuxBarStyle.hoveredSegmentOpacity
    ) -> some View {
        background {
            if isSelected {
                Rectangle().fill(
                    winMuxBarSurfaceFill(palette).opacity(selectedOpacity)
                )
            } else if isHovered {
                Rectangle().fill(
                    winMuxBarSurfaceFill(palette)
                        .opacity(hoveredOpacity)
                )
            }
        }
    }
}
