import AppKit
import CoreGraphics

// Observe modifier transitions and Tab release before Carbon consumes shortcuts.
private let workspacePreviewKeyboardCallback: CGEventTapCallBack = { _, type, event, _ in
    var flags: NSEvent.ModifierFlags = []
    if event.flags.contains(.maskAlternate) { flags.insert(.option) }
    if event.flags.contains(.maskControl) { flags.insert(.control) }
    if event.flags.contains(.maskCommand) { flags.insert(.command) }
    if event.flags.contains(.maskShift) { flags.insert(.shift) }
    let modifierFlags = flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    DispatchQueue.main.async {
        switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                WorkspacePreviewKeyboardObserver.shared.enable()
            case .flagsChanged:
                WorkspacePreviewPanel.shared.modifierFlagsChanged(modifierFlags)
            case .keyUp where keyCode == 48:
                WorkspacePreviewPanel.shared.tabKeyReleased()
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
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue | 1 << CGEventType.keyUp.rawValue)
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
