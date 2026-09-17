import AppKit
import SwiftUI

/// Shared visual rules for project tabs, workspace tabs, and the widget bar.
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
    static let projectTabsBarOuterInset = WinMuxSpacing.comfortable
    static let projectTabsBarContentHeight = standardGap * 10
    static let projectTabsBarHorizontalInset = WinMuxSpacing.section
    static let projectTabsBarFontSize = fontSize + strokeWidth
    static let projectBarCornerRadius = projectTabsBarContentHeight / 2
    static let projectBarHeight = projectTabsBarContentHeight + projectTabsBarOuterInset
    static let projectBarTintOpacity: CGFloat = 0.08
    static let projectBarStrokeOpacity: CGFloat = 0.44
    static let workspaceTabContentHeight = standardGap * 10
    static let workspaceBarHeight = workspaceTabContentHeight + windowTabStripContentPaddingValue * 2
    static let workspaceTabCornerRadius = workspaceTabContentHeight / 2
    static let workspaceTabBarCornerRadius = workspaceBarHeight / 2
    static let workspaceBarTintOpacity: CGFloat = 0.06
    static let workspaceBarStrokeOpacity: CGFloat = 0.4
    static let topBarTintOpacity: CGFloat = 0.06
    static let topBarStrokeOpacity: CGFloat = 0.34
    static let selectedSegmentOpacity: CGFloat = 0.56
    static let hoveredSegmentOpacity: CGFloat = 0.24
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

private struct WinMuxGlassBarSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let palette: WinMuxOverlayPalette
    let cornerRadius: CGFloat
    let material: NSVisualEffectView.Material
    let tintOpacity: CGFloat
    let strokeOpacity: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    winMuxBarSurfaceFill(palette)
                } else {
                    ZStack {
                        VisualEffectBlur(material: material, blendingMode: .behindWindow)
                        winMuxBarSurfaceFill(palette).opacity(tintOpacity)
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.13 : 0.24),
                                    Color.white.opacity(colorScheme == .dark ? 0.035 : 0.07),
                                    Color.black.opacity(colorScheme == .dark ? 0.08 : 0.035),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    winMuxBarSurfaceStroke(palette).opacity(
                        reduceTransparency ? 1 : strokeOpacity
                    ),
                    lineWidth: WinMuxBarStyle.strokeWidth
                )
                .allowsHitTesting(false)
            }
            .overlay {
                if !reduceTransparency {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.38 : 0.72),
                                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.26),
                                Color.black.opacity(colorScheme == .dark ? 0.24 : 0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: WinMuxBarStyle.strokeWidth
                    )
                    .allowsHitTesting(false)
                }
            }
            .shadow(
                color: Color.black.opacity(reduceTransparency ? 0 : colorScheme == .dark ? 0.32 : 0.18),
                radius: standardGap * 3,
                y: standardGap
            )
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

    func winMuxBarSegment(_ palette: WinMuxOverlayPalette, isSelected: Bool, isHovered: Bool) -> some View {
        background {
            if isSelected {
                Rectangle().fill(
                    palette.geistBackground(.primary).opacity(WinMuxBarStyle.selectedSegmentOpacity)
                )
            } else if isHovered {
                Rectangle().fill(
                    palette.color(palette.activeGeistFamily, .color2)
                        .opacity(WinMuxBarStyle.hoveredSegmentOpacity)
                )
            }
        }
    }
}
