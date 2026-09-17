import AppKit

@MainActor
public final class NativeMenuBarController: NSObject, NSMenuDelegate {
    private let viewModel: TrayMenuModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var workspaceNameByField: [ObjectIdentifier: String] = [:]
    private var renameFieldByMenuItem: [ObjectIdentifier: NSTextField] = [:]

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
        workspaceNameByField.removeAll(keepingCapacity: true)
        renameFieldByMenuItem.removeAll(keepingCapacity: true)

        for project in viewModel.workspaceSidebarProjects {
            let item = NSMenuItem(title: project.displayName, action: nil, keyEquivalent: "")
            item.state = project.id == viewModel.workspaceSidebarActiveProjectId ? .on : .off
            item.submenu = workspaceMenu(project)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(configMenu())
        if projectsAreEnabled() {
            menu.addItem(actionItem("New project", #selector(createProject)))
        }
    }

    private func workspaceMenu(_ project: WorkspaceSidebarProjectViewModel) -> NSMenu {
        let menu = NSMenu()
        let workspaces = viewModel.workspaceSidebarWorkspaces.filter { $0.projectId == project.id }
        guard !workspaces.isEmpty else {
            let empty = NSMenuItem(title: "No workspaces", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return menu
        }

        for workspace in workspaces {
            let item = NSMenuItem(title: workspace.displayName, action: nil, keyEquivalent: "")
            item.state = workspace.isFocused ? .on : .off
            item.submenu = renameMenu(workspace)
            menu.addItem(item)
        }
        return menu
    }

    private func renameMenu(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> NSMenu {
        let menu = NSMenu()
        let rename = NSMenuItem(title: "Rename", action: nil, keyEquivalent: "")
        rename.submenu = renameEditorMenu(workspace)
        menu.addItem(rename)
        return menu
    }

    private func renameEditorMenu(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> NSMenu {
        let menu = NSMenu()
        let field = NSTextField(
            string: workspace.sidebarLabel.isEmpty ? workspace.displayName : workspace.sidebarLabel
        )
        field.placeholderString = "Rename workspace"
        field.target = self
        field.action = #selector(commitWorkspaceRename(_:))
        field.frame = NSRect(x: 10, y: 4, width: 220, height: 24)
        workspaceNameByField[ObjectIdentifier(field)] = workspace.name

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
        container.addSubview(field)
        let item = NSMenuItem()
        item.view = container
        menu.addItem(item)
        menu.addItem(.separator())

        let commit = actionItem("Rename", #selector(commitWorkspaceRenameMenuItem(_:)))
        renameFieldByMenuItem[ObjectIdentifier(commit)] = field
        menu.addItem(commit)
        return menu
    }

    private func configMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Config", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let theme = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themes = NSMenu()
        themes.addItem(themeItem("Light", tag: 0, theme: .light))
        themes.addItem(themeItem("Dark", tag: 1, theme: .dark))
        themes.addItem(themeItem("System", tag: 2, theme: nil))
        theme.submenu = themes
        menu.addItem(theme)

        if let project = activeProject, projectsAreEnabled() {
            menu.addItem(.separator())
            let rename = actionItem("Rename project…", #selector(renameProject(_:)))
            rename.representedObject = project.id.rawValue
            menu.addItem(rename)

            let delete = actionItem("Delete project", #selector(deleteProject(_:)))
            delete.representedObject = project.id.rawValue
            delete.isEnabled = canDeleteWorkspaceProject(project.id)
            menu.addItem(delete)
        }
        item.submenu = menu
        return item
    }

    private var activeProject: WorkspaceSidebarProjectViewModel? {
        viewModel.workspaceSidebarProjects.first { $0.id == viewModel.workspaceSidebarActiveProjectId }
    }

    private func themeItem(_ title: String, tag: Int, theme: AppearanceTheme?) -> NSMenuItem {
        let item = actionItem(title, #selector(setTheme(_:)))
        item.tag = tag
        item.state = currentWorkspaceSidebarAppearancePreference() == theme ? .on : .off
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func commitWorkspaceRename(_ field: NSTextField) {
        guard let workspaceName = workspaceNameByField[ObjectIdentifier(field)] else { return }
        let displayName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }
        handleWorkspaceSidebarAction(
            .renameWorkspace(workspaceName, displayName: displayName),
            viewModel: viewModel
        )
        menu.cancelTracking()
    }

    @objc private func commitWorkspaceRenameMenuItem(_ item: NSMenuItem) {
        guard let field = renameFieldByMenuItem[ObjectIdentifier(item)] else { return }
        commitWorkspaceRename(field)
    }

    @objc private func setTheme(_ item: NSMenuItem) {
        switch item.tag {
            case 0: setWorkspaceSidebarAppearance(.light)
            case 1: setWorkspaceSidebarAppearance(.dark)
            default: setWorkspaceSidebarAppearance(nil)
        }
    }

    @objc private func renameProject(_ item: NSMenuItem) {
        guard let rawId = item.representedObject as? String,
              let project = viewModel.workspaceSidebarProjects.first(where: { $0.id.rawValue == rawId }),
              let name = promptForProjectName("Rename project", initialValue: project.displayName)
        else { return }
        handleWorkspaceSidebarAction(.renameProject(project.id, displayName: name), viewModel: viewModel)
    }

    @objc private func deleteProject(_ item: NSMenuItem) {
        guard let rawId = item.representedObject as? String else { return }
        handleWorkspaceSidebarAction(.deleteProject(WorkspaceProjectId(rawId)), viewModel: viewModel)
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
