import AppKit

extension Monitor {
    @MainActor
    var workspaceSidebarInset: CGFloat {
        // The sidebar is hosted in the menu-bar safe region and no longer
        // consumes horizontal canvas space.
        0
    }

    @MainActor
    var visibleRectPaddedByOuterGaps: Rect {
        let topLeft = visibleRect.topLeftCorner
        let gaps = ResolvedGaps(
            gaps: config.gaps,
            monitor: self,
            canvasGap: config.workspaceSidebar.enabled ? Int(WinMuxSpacing.comfortable) : nil
        )
        let projectBarReservation = workspaceSidebarProjectBarVisibleReservation(for: self)
        let leftInset = max(gaps.outer.left.toDouble(), 0)
        let contentTopGap = config.workspaceSidebar.enabled ? WinMuxSpacing.comfortable : max(gaps.outer.top.toDouble(), 0)
        let topInset = contentTopGap
        let rightInset = max(gaps.outer.right.toDouble(), 0)
        let contentBottomGap = config.workspaceSidebar.enabled
            ? WinMuxSpacing.comfortable * 0.5
            : max(gaps.outer.bottom.toDouble(), 0)
        let bottomInset = contentBottomGap + projectBarReservation
        return Rect(
            topLeftX: topLeft.x + leftInset,
            topLeftY: topLeft.y + topInset,
            width: visibleRect.width - leftInset - rightInset,
            height: visibleRect.height - topInset - bottomInset,
        )
    }

    @MainActor
    var monitorId_oneBased: Int? {
        sortedMonitors.firstIndex { $0.rect.topLeftCorner == rect.topLeftCorner }.map { $0 + 1 }
    }
}
