import AppKit
import SwiftUI

/// A menu owns its window instead of inheriting the tab bar's ordering group.
@MainActor
final class WinMuxMenuPanelController {
    private let panel = MenuPanel()
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private weak var anchor: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    var onDismiss: () -> Void = {}

    init() {
        panel.contentView = hostingView
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.identifier = NSUserInterfaceItemIdentifier("WinMux.contextMenu")
    }

    func show<Content: View>(from anchor: NSView, @ViewBuilder content: () -> Content) {
        guard anchor.window != nil else { return }
        self.anchor = anchor
        hostingView.rootView = AnyView(content()
            .fixedSize()
            .background(GeometryReader { proxy in
                WinMuxDesignTokens.transparent.preference(key: MenuSizeKey.self, value: proxy.size)
            })
            .onPreferenceChange(MenuSizeKey.self) { [weak self] size in
                Task { @MainActor in self?.resize(size) }
            }
        )
        guard !panel.isVisible else { return }
        resize(hostingView.fittingSize)
        panel.makeKeyAndOrderFront(nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.dismiss(); return nil }
            } else if event.window !== self.panel {
                self.dismiss()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        panel.orderOut(nil)
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        onDismiss()
    }

    private func resize(_ size: CGSize) {
        guard size.width > 0, size.height > 0,
              let anchor, let window = anchor.window else { return }
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? rect
        panel.setFrame(NSRect(
            x: min(max(rect.minX, screen.minX), screen.maxX - size.width),
            y: max(screen.minY, rect.minY - size.height),
            width: size.width,
            height: size.height
        ), display: true)
        panel.level = .popUpMenu
        if panel.isVisible { panel.orderFrontRegardless() }
    }

    private final class MenuPanel: NSPanelHud {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private struct MenuSizeKey: PreferenceKey {
        static let defaultValue = CGSize.zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
    }
}

struct WinMuxMenuPanelAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> WinMuxMenuPanelController { WinMuxMenuPanelController() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let controller = context.coordinator
        controller.onDismiss = { if isPresented { isPresented = false } }
        if isPresented {
            controller.show(from: view, content: content)
        } else {
            controller.dismiss()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: WinMuxMenuPanelController) {
        coordinator.onDismiss = {}
        coordinator.dismiss()
    }
}
