import AppKit
import SwiftUI

struct WorkspaceSidebarProjectMenu: NSViewRepresentable {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let configuration: [WorkspaceSidebarNativeContextMenu.Item]
    let allowsCreation: Bool
    let colorScheme: ColorScheme
    let onSelect: (WorkspaceProjectId) -> Void
    let onCreate: (@escaping (WorkspaceProjectId) -> Void) -> Void
    let onRename: (WorkspaceProjectId, String) -> Void

    func makeNSView(context: Context) -> ProjectButton { ProjectButton() }
    func updateNSView(_ button: ProjectButton, context: Context) {
        button.model = self
        button.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        button.setAccessibilityLabel("Project: \(projects.first { $0.id == selectedProjectId }?.displayName ?? "Main")")
    }

    final class ProjectButton: NSButton, NSTextFieldDelegate {
        var model: WorkspaceSidebarProjectMenu?
        private let menuBuilder = WorkspaceSidebarNativeContextMenu.MenuView()
        private var trackingMenu: NSMenu?
        private var editing: (id: WorkspaceProjectId, row: NSMenuItem, field: NSTextField)?
        private var keyMonitor: Any?

        init() {
            super.init(frame: .zero)
            image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
            imagePosition = .imageOnly
            isBordered = false
            focusRingType = .none
            target = self
            action = #selector(openProjects)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func openProjects() {
            guard let model, let window else { return }
            let menu = menuBuilder.makeMenu(model.projects.map { project in
                .init(title: project.displayName, symbol: project.id == model.selectedProjectId ? "checkmark" : nil) {
                    model.onSelect(project.id)
                }
            } + [.separator, .init(title: "Config", children: model.configuration)])
            if model.allowsCreation {
                let row = NSMenuItem()
                let button = NSButton(title: "New project", target: self, action: #selector(createProject))
                button.isBordered = false
                button.alignment = .left
                button.font = .menuFont(ofSize: 0)
                button.focusRingType = .none
                button.frame = NSRect(x: 0, y: 0, width: max(menu.size.width, standardGap * 46), height: standardGap * 6)
                row.view = button
                menu.addItem(row)
            }
            trackingMenu = menu
            let anchor = NSPanelHud()
            anchor.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            let rect = window.convertToScreen(convert(bounds, to: nil))
            anchor.setFrame(NSRect(x: rect.minX, y: rect.minY, width: 1, height: 1), display: false)
            anchor.appearance = appearance
            anchor.level = .popUpMenu
            anchor.hasShadow = false
            anchor.ignoresMouseEvents = true
            anchor.orderFrontRegardless()
            menu.popUp(positioning: nil, at: .zero, in: anchor.contentView)
            finishEditing()
            trackingMenu = nil
            anchor.orderOut(nil)
        }

        @objc private func createProject() {
            finishEditing()
            model?.onCreate { [weak self] id in
                guard let self, let menu = self.trackingMenu,
                      let project = workspaceProjects().first(where: { $0.id == id }) else { return }
                let field = NSTextField(string: project.name)
                field.isBordered = false
                field.drawsBackground = false
                field.focusRingType = .none
                field.font = .menuFont(ofSize: 0)
                field.delegate = self
                field.setAccessibilityLabel("Project name")
                field.frame = NSRect(x: 0, y: 0, width: max(menu.size.width, standardGap * 46), height: standardGap * 6)
                let row = NSMenuItem(title: project.name, action: nil, keyEquivalent: "")
                row.view = field
                menu.insertItem(row, at: menu.items.firstIndex(where: \.isSeparatorItem) ?? 0)
                self.editing = (id, row, field)
                menu.update()
                DispatchQueue.main.async {
                    field.window?.makeFirstResponder(field)
                    field.selectText(nil)
                }
                self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let editing = self.editing else { return event }
                    if event.keyCode == 36 || event.keyCode == 76 {
                        self.finishEditing()
                    } else if event.keyCode == 53 {
                        self.finishEditing(cancelled: true)
                    } else if let editor = editing.field.currentEditor() {
                        editor.keyDown(with: event)
                    } else {
                        return event
                    }
                    return nil
                }
            }
        }

        private func finishEditing(cancelled: Bool = false) {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            guard let editing else { return }
            self.editing = nil
            let name = editing.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cancelled && !name.isEmpty {
                model?.onRename(editing.id, name)
                editing.row.title = name
            }
            editing.row.view = nil
            let id = editing.id
            let replacement = menuBuilder.makeMenu([.init(title: editing.row.title) { [weak self] in
                self?.model?.onSelect(id)
            }]).items[0]
            editing.row.target = replacement.target
            editing.row.action = replacement.action
            editing.row.representedObject = replacement.representedObject
        }
    }
}
