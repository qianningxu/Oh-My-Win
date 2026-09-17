import AppKit

extension WorkspaceSidebarPanel {
    func updateMousePassthrough() {
        // The panel frame hugs the visible bar, so every point is interactive.
        ignoresMouseEvents = false
    }

    func isMouseInsideHoverRegion() -> Bool {
        isVisible && frame.contains(NSEvent.mouseLocation)
    }

    func isMouseInsideInteractiveRegion() -> Bool {
        guard isVisible else { return false }
        return isPointInsideInteractiveRegion(NSEvent.mouseLocation)
    }

    func isPointInsideInteractiveRegion(_ point: CGPoint) -> Bool {
        isVisible && frame.contains(point)
    }

    func isMouseInsideVisibleRegion() -> Bool {
        isVisible && frame.contains(NSEvent.mouseLocation)
    }

    func isMouseDeepEnoughToExpand(collapsedWidth: CGFloat) -> Bool {
        isVisible
    }

    func visualSidebarFrame() -> NSRect {
        frame
    }

    func sideAreaBackgroundFrame() -> NSRect {
        frame
    }
}
