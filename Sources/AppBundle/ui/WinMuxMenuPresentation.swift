import AppKit
import SwiftUI

/// Native menus inherit their owner's level when they start tracking.
@MainActor
final class WinMuxMenuPresentation {
    static let shared = WinMuxMenuPresentation()
    private weak var owner: NSWindow?
    private var restingLevel: NSWindow.Level = .normal
    private var trackingDepth = 0
    private var observers: [NSObjectProtocol] = []

    private init() {
        observers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if Self.shared.owner != nil { Self.shared.trackingDepth += 1 }
                }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    Self.shared.trackingDepth = max(0, Self.shared.trackingDepth - 1)
                    Self.shared.restoreIfFinished()
                }
            },
        ]
    }

    func prepare(_ window: NSWindow) {
        guard owner !== window else { return }
        restore()
        owner = window
        restingLevel = window.level
        window.level = .popUpMenu
        window.orderFrontRegardless()
    }

    func finishEvent() {
        DispatchQueue.main.async { self.restoreIfFinished() }
    }

    func setLevel(_ level: NSWindow.Level, for window: NSWindow) {
        if owner === window {
            restingLevel = level
            window.level = .popUpMenu
        } else {
            window.level = level
        }
    }

    func owns(_ window: NSWindow) -> Bool { owner === window }

    private func restoreIfFinished() {
        if trackingDepth == 0 { restore() }
    }

    private func restore() {
        owner?.level = restingLevel
        owner = nil
        trackingDepth = 0
    }
}

/// SwiftUI and AppKit popovers also inherit the low resting level of the tab bar.
struct WinMuxMenuPopoverLevel: NSViewRepresentable {
    func makeNSView(context: Context) -> LevelView { LevelView() }
    func updateNSView(_ view: LevelView, context: Context) { view.raisePopover() }

    final class LevelView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            raisePopover()
            DispatchQueue.main.async { [weak self] in self?.raisePopover() }
        }

        func raisePopover() {
            guard let window, !(window is NSPanelHud) else { return }
            window.level = .popUpMenu
        }
    }
}
