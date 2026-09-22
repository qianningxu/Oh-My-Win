import AppKit

private let windowTabBarOuterInsetValue = WinMuxSpacing.hairline
// The workspace layout already supplies the gap between groups. Keep the
// bar and native window on the same horizontal bounds without adding it twice.
private let windowTabGroupShellHorizontalInsetValue = WinMuxSpacing.none
// Keep equal vertical padding above and below the workspace tab bar.
private let windowTabGroupShellTopInsetValue = windowTabBarOuterInsetValue * 2
private let windowTabGroupShellBottomInsetValue = WinMuxSpacing.none
// Match the visible height of the menu-bar surfaces.
private let windowTabBarMinimumHeightValue = workspaceSidebarTabRowHeight - standardGap * 0.5

func windowTabGroupShellHorizontalInset() -> CGFloat {
    windowTabGroupShellHorizontalInsetValue
}

func windowTabGroupShellTopInset() -> CGFloat {
    windowTabGroupShellTopInsetValue
}

func windowTabGroupShellBottomInset() -> CGFloat {
    windowTabGroupShellBottomInsetValue
}

func windowTabBarOuterInset() -> CGFloat {
    windowTabBarOuterInsetValue
}

@MainActor
func resolvedWindowTabBarHeight() -> CGFloat {
    guard NSScreen.main != nil else { return WinMuxBarStyle.workspaceBarHeight }
    return WinMuxBarStyle.workspaceBarHeight
}
