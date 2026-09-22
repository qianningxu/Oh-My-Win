import AppKit

@MainActor
public final class NativeMenuBarController: NSObject, NSMenuDelegate {
    private let viewModel: TrayMenuModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    public init(viewModel: TrayMenuModel) {
        self.viewModel = viewModel
        super.init()
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "oh!",
            attributes: [
                .font: NSFont(name: "SignPainter-HouseScriptSemibold", size: 20)
                    ?? NSFont.boldSystemFont(ofSize: 18),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        statusItem.button?.toolTip = "Oh-My-Win"
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for project in viewModel.workspaceSidebarProjects {
            if project.id == viewModel.workspaceSidebarActiveProjectId {
                menu.addItem(activeProjectMenu(project))
            } else {
                let item = actionItem(project.displayName, #selector(selectProject(_:)))
                item.representedObject = project.id.rawValue
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        if projectsAreEnabled() {
            menu.addItem(actionItem("New project", #selector(createProject)))
        }
        menu.addItem(actionItem("Show Dashboard", #selector(showDashboard)))
        menu.addItem(actionItem("Quit", #selector(quit)))
    }

    private func activeProjectMenu(_ project: WorkspaceSidebarProjectViewModel) -> NSMenuItem {
        let item = NSMenuItem(title: project.displayName, action: nil, keyEquivalent: "")
        item.state = .on
        let submenu = NSMenu()
        let workspaces = viewModel.workspaceSidebarWorkspaces.filter { $0.projectId == project.id }
        if workspaces.isEmpty {
            let emptyItem = NSMenuItem(title: "No workspaces", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for workspace in workspaces {
                let workspaceItem = actionItem(workspace.displayName, #selector(selectWorkspace(_:)))
                workspaceItem.representedObject = workspace.name
                workspaceItem.state = workspace.isFocused ? .on : .off
                submenu.addItem(workspaceItem)
            }
        }
        submenu.addItem(.separator())
        let rename = actionItem("Rename current project…", #selector(renameProject(_:)))
        rename.representedObject = project.id.rawValue
        rename.isEnabled = projectsAreEnabled()
        submenu.addItem(rename)
        item.submenu = submenu
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func selectProject(_ item: NSMenuItem) {
        guard let rawId = item.representedObject as? String else { return }
        handleWorkspaceSidebarAction(.selectProject(WorkspaceProjectId(rawId)), viewModel: viewModel)
    }

    @objc private func selectWorkspace(_ item: NSMenuItem) {
        guard let workspaceName = item.representedObject as? String else { return }
        handleWorkspaceSidebarAction(.selectWorkspace(workspaceName), viewModel: viewModel)
    }

    @objc private func showDashboard() {
        menu.cancelTracking()
        openWorkspaceSidebarFromMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func renameProject(_ item: NSMenuItem) {
        guard let rawId = item.representedObject as? String,
              let project = viewModel.workspaceSidebarProjects.first(where: { $0.id.rawValue == rawId }),
              let name = promptForProjectName("Rename project", initialValue: project.displayName)
        else { return }
        handleWorkspaceSidebarAction(.renameProject(project.id, displayName: name), viewModel: viewModel)
    }

    @objc private func createProject() {
        guard let name = promptForProjectName("New project", initialValue: "") else { return }
        createWorkspaceSidebarProject(displayName: name, viewModel: viewModel)
    }
}

@MainActor
private func promptForProjectName(_ title: String, initialValue: String) -> String? {
    let field = NSTextField(string: initialValue)
    field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
    let alert = NSAlert()
    alert.messageText = title
    alert.accessoryView = field
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}
