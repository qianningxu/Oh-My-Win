import AppKit

@MainActor
func windowTabGroupAppCornerRadius(activeWindowId: UInt32?) -> CGFloat {
    let radius = activeWindowId.map(estimatedWindowPreviewCornerRadius) ?? windowTabPreviewCornerRadius
    return max(radius, 0)
}

func windowTabGroupOuterCornerRadius(innerCornerRadius _: CGFloat) -> CGFloat {
    windowTabStripCornerRadius
}

func windowTabGroupTopInnerCornerRadius(_: CGFloat) -> CGFloat {
    0
}

func windowTabGroupTopCornerShieldRadius(_ topInnerCornerRadius: CGFloat) -> CGFloat {
    min(topInnerCornerRadius + windowTabGroupCornerShieldOverreach, windowTabGroupFrameMaxTopInnerCornerRadius)
}

func windowTabGroupBottomCornerShieldRadius(_ appCornerRadius: CGFloat) -> CGFloat {
    min(
        appCornerRadius + windowTabGroupCornerShieldOverreach,
        windowTabGroupFrameMaxInnerCornerRadius + windowTabGroupCornerShieldOverreach
    )
}

func windowTabGroupInnerAppFrame(groupSize: CGSize, tabHeight: CGFloat) -> CGRect {
    let horizontalInset = min(windowTabGroupShellHorizontalInset(), groupSize.width / 2)
    let contentTop = min(tabHeight + windowTabGroupShellTopInset(), groupSize.height)
    let availableHeight = max(groupSize.height - contentTop, 0)
    let bottomInset = min(windowTabGroupShellBottomInset(), availableHeight)
    return CGRect(
        x: horizontalInset,
        y: contentTop,
        width: max(groupSize.width - horizontalInset * 2, 0),
        height: max(availableHeight - bottomInset, 0)
    )
}
