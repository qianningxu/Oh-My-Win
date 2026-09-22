import AppKit

extension WindowMouseInteractionDriver {
    func startDisplayLoop() {
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            self?.displayFrame()
        }
    }

    func displayFrame() {
        guard isLeftMouseButtonDown else {
            finishAfterMissedMouseUpIfNeeded()
            return
        }
        renderMoveFrame(force: false)
        sampleResizeFrame(force: false)
        if resizeSession != nil {
            // AppKit can restore a live-resized window's alpha while the native
            // gesture is active. Keep the native content hidden beneath the
            // two empty compositor frames until the gesture finishes.
            WindowMouseInteractionOpacityController.shared.reapplyHiddenWindowAlpha()
        }
    }

    func finishAfterMissedMouseUpIfNeeded() {
        guard resizeSession != nil || moveSession != nil else {
            logWindowDragLive("resizePreview hide requested reason=displayLoop.idle mouseDown=\(isLeftMouseButtonDown)")
            DisplayRefreshDriver.shared.remove(owner: self)
            WindowResizePreviewPanel.shared.endStableFrame()
            WindowResizePreviewPanel.shared.hide(reason: "displayLoop.idle")
            return
        }
        guard !isMouseUpResetScheduled else { return }
        isMouseUpResetScheduled = true
        DisplayRefreshDriver.shared.remove(owner: self)
        Task { @MainActor in
            try? await resetManipulatedWithMouseIfPossible()
            isMouseUpResetScheduled = false
        }
    }
}
