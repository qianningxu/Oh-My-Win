import AppKit
import SwiftUI

/// Present outside SwiftUI's tab/scroll-view layout so refreshes cannot resize an open menu.
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
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }

    final class MenuView: NSView {
        var items: [Item] = []

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown ||
                    (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            // Build a separate, stable menu for the duration of native menu tracking.
            NSMenu.popUpContextMenu(makeMenu(items), with: event, for: self)
        }

        override func mouseDown(with event: NSEvent) {
            rightMouseDown(with: event)
        }

        private func makeMenu(_ items: [Item]) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for item in items {
                if item.title.isEmpty {
                    menu.addItem(.separator())
                    continue
                }
                let row = NSMenuItem(title: item.title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
                row.target = self
                row.representedObject = item
                row.isEnabled = item.isEnabled
                if let symbol = item.symbol {
                    row.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                }
                if let children = item.children {
                    row.submenu = makeMenu(children)
                }
                menu.addItem(row)
            }
            return menu
        }

        @objc private func performMenuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? Item)?.action()
        }
    }
}
