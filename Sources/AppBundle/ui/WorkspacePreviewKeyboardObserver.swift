import AppKit
import CoreGraphics

// Observe physical releases before Carbon consumes registered shortcut events.
private let workspacePreviewKeyboardCallback: CGEventTapCallBack = { _, type, event, _ in
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let optionPressed = event.flags.contains(.maskAlternate)
    DispatchQueue.main.async {
        switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                WorkspacePreviewKeyboardObserver.shared.enable()
            case .keyUp:
                WorkspacePreviewPanel.shared.shortcutKeyReleased(keyCode)
            case .flagsChanged:
                if optionPressed {
                    WorkspacePreviewPanel.shared.optionPressed()
                } else {
                    WorkspacePreviewPanel.shared.optionReleased()
                }
            default: break
        }
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class WorkspacePreviewKeyboardObserver {
    static let shared = WorkspacePreviewKeyboardObserver()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func install() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyUp.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .listenOnly, eventsOfInterest: mask,
                                         callback: workspacePreviewKeyboardCallback, userInfo: nil),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        else { return }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        enable()
    }

    func enable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}
