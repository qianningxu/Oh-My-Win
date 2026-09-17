import AppKit

@MainActor
public final class NativeMenuBarController: NSObject, NSMenuDelegate {
    private let viewModel: TrayMenuModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var workspacePanel: NSPanel?
    private var workspaceNameByField: [ObjectIdentifier: String] = [:]
    private var workspaceRenameFieldByButton: [ObjectIdentifier: NSTextField] = [:]

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
        menu.addItem(actionItem("Workspace", #selector(showWorkspacePanel)))
        menu.addItem(.separator())
        menu.addItem(configMenu())
        if projectsAreEnabled() {
            menu.addItem(actionItem("New project", #selector(createProject)))
        }
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

    @objc private func showWorkspacePanel() {
        workspacePanel?.close()
        workspaceNameByField.removeAll(keepingCapacity: true)
        workspaceRenameFieldByButton.removeAll(keepingCapacity: true)

        let projects = viewModel.workspaceSidebarProjects
        let workspaces = viewModel.workspaceSidebarWorkspaces
        let contentHeight = max(
            180,
            projects.reduce(24) { height, project in
                height + 34 + workspaces.filter { $0.projectId == project.id }.count * 42
            }
        )
        let panelHeight = min(620, contentHeight + 40)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: panelHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Workspaces"
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 440, height: 220)

        let scrollView = NSScrollView(frame: NSRect(x: 18, y: 18, width: 504, height: panelHeight - 36))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let document = FlippedWorkspaceListView(frame: NSRect(x: 0, y: 0, width: 504, height: contentHeight))
        var y: CGFloat = 8
        for project in projects {
            let projectLabel = NSTextField(labelWithString: project.displayName)
            projectLabel.font = .boldSystemFont(ofSize: 13)
            projectLabel.frame = NSRect(x: 8, y: y, width: 480, height: 20)
            document.addSubview(projectLabel)
            y += 28

            for workspace in workspaces.filter({ $0.projectId == project.id }) {
                let field = NSTextField(
                    string: workspace.sidebarLabel.isEmpty ? workspace.displayName : workspace.sidebarLabel
                )
                field.placeholderString = "Workspace name"
                field.target = self
                field.action = #selector(commitWorkspaceRename(_:))
                field.frame = NSRect(x: 8, y: y, width: 376, height: 26)
                workspaceNameByField[ObjectIdentifier(field)] = workspace.name
                document.addSubview(field)

                let button = NSButton(
                    title: "Rename",
                    target: self,
                    action: #selector(commitWorkspaceRenameButton(_:))
                )
                button.bezelStyle = .rounded
                button.frame = NSRect(x: 394, y: y - 1, width: 92, height: 28)
                workspaceRenameFieldByButton[ObjectIdentifier(button)] = field
                document.addSubview(button)
                y += 42
            }
            y += 6
        }

        if workspaces.isEmpty {
            let empty = NSTextField(labelWithString: "No workspaces")
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            empty.frame = NSRect(x: 8, y: 68, width: 480, height: 22)
            document.addSubview(empty)
        }

        scrollView.documentView = document
        panel.contentView?.addSubview(scrollView)
        workspacePanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func commitWorkspaceRename(_ field: NSTextField) {
        guard let workspaceName = workspaceNameByField[ObjectIdentifier(field)] else { return }
        let displayName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }
        handleWorkspaceSidebarAction(
            .renameWorkspace(workspaceName, displayName: displayName),
            viewModel: viewModel
        )
    }

    @objc private func commitWorkspaceRenameButton(_ button: NSButton) {
        guard let field = workspaceRenameFieldByButton[ObjectIdentifier(button)] else { return }
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

private final class FlippedWorkspaceListView: NSView {
    override var isFlipped: Bool { true }
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
