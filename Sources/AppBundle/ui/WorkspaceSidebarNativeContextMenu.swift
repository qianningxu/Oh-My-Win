import AppKit
import SwiftUI

/// Keep context commands in a separate popover, outside native menu scrolling constraints.
struct WorkspaceSidebarNativeContextMenu: NSViewRepresentable {
    let items: [Item]
    let colorScheme: ColorScheme

    struct Item {
        let title: String
        var isEnabled = true
        var symbol: String? = nil
        var children: [Item]? = nil
        var action: () -> Void = {}

        static var separator: Item { Item(title: "", isEnabled: false) }
    }

    func makeNSView(context: Context) -> MenuView {
        MenuView()
    }

    func updateNSView(_ view: MenuView, context: Context) {
        view.items = items
        view.colorScheme = colorScheme
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }

    static func dismantleNSView(_ view: MenuView, coordinator: ()) {
        view.dismissMenu()
    }

    final class MenuView: NSView {
        var items: [Item] = []
        var colorScheme: ColorScheme = .light
        private var menuPanel: WinMuxMenuPanelController?

        func dismissMenu() { menuPanel?.dismiss() }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown ||
                    (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            menuPanel?.dismiss()
            let controller = WinMuxMenuPanelController()
            menuPanel = controller
            controller.show(from: self) {
                WorkspaceSidebarContextCommands(items: items) { [weak controller] in
                    controller?.dismiss()
                }
                .environment(\.colorScheme, colorScheme)
            }
        }

        override func mouseDown(with event: NSEvent) {
            rightMouseDown(with: event)
        }
    }
}

private struct WorkspaceSidebarContextCommands: View {
    let items: [WorkspaceSidebarNativeContextMenu.Item]
    let dismiss: () -> Void
    @State private var submenu: WorkspaceSidebarNativeContextMenu.Item?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WinMuxSpacing.hairline) {
            if let submenu {
                Button { self.submenu = nil } label: {
                    Label(submenu.title, systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .padding(.vertical, standardGap)
                Divider()
            }
            ForEach(Array((submenu?.children ?? items).enumerated()), id: \.offset) { _, item in
                if item.title.isEmpty {
                    Divider()
                } else {
                    Button {
                        if item.children != nil {
                            submenu = item
                        } else {
                            dismiss()
                            item.action()
                        }
                    } label: {
                        HStack(spacing: standardGap) {
                            if let symbol = item.symbol { Image(systemName: symbol) }
                            Text(item.title).lineLimit(1)
                            Spacer(minLength: standardGap)
                            if item.children != nil { Image(systemName: "chevron.right") }
                        }
                        .frame(maxWidth: .infinity, minHeight: workspaceSidebarProjectPopupRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!item.isEnabled)
                }
            }
        }
        .font(.system(size: workspaceSidebarProjectLabelFontSize))
        .foregroundStyle(palette.content(.primary))
        .padding(WinMuxSpacing.section)
        .frame(width: standardGap * 80)
        .background(palette.geistBackground(.primary))

    }
}
