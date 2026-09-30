import AppKit
import Combine

@MainActor
public final class NativeMenuBarController: NSObject, NSMenuDelegate {
    private struct WorkspaceProjectMove {
        let workspaceName: String
        let projectId: WorkspaceProjectId
    }

    private let viewModel: TrayMenuModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var activeProjectObservation: AnyCancellable?

    public init(viewModel: TrayMenuModel) {
        self.viewModel = viewModel
        super.init()
        updateStatusItemTitle(projectName: nil)
        activeProjectObservation = viewModel.$workspaceSidebarProjects
            .combineLatest(viewModel.$workspaceSidebarActiveProjectId)
            .sink { [weak self] projects, activeProjectId in
                let projectName = projects.first { $0.id == activeProjectId }?.displayName
                DispatchQueue.main.async {
                    self?.updateStatusItemTitle(projectName: projectName)
                }
            }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    private func updateStatusItemTitle(projectName: String?) {
        let name = projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleName = name.flatMap { $0.isEmpty ? nil : $0 }
        let brandFont = NSFont(name: "SignPainter-HouseScriptSemibold", size: 20)
            ?? NSFont.boldSystemFont(ofSize: 18)
        let projectFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let title = NSMutableAttributedString(
            string: "oh!",
            attributes: [
                .font: brandFont,
                .foregroundColor: NSColor.labelColor,
            ]
        )

        if let visibleName {
            title.append(NSAttributedString(
                string: "  ·  ",
                attributes: [
                    .font: projectFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ))
            title.append(NSAttributedString(
                string: boundedStatusProjectName(visibleName, font: projectFont),
                attributes: [
                    .font: projectFont,
                    .foregroundColor: NSColor.labelColor,
                ]
            ))
        }

        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = visibleName.map { "Oh-My-Win — \($0)" } ?? "Oh-My-Win"
        statusItem.button?.setAccessibilityLabel(
            visibleName.map { "Oh-My-Win, project \($0)" } ?? "Oh-My-Win"
        )
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for workspace in viewModel.workspaceSidebarWorkspaces
            where workspace.projectId == viewModel.workspaceSidebarActiveProjectId {
            menu.addItem(workspaceMenu(workspace))
        }
        menu.addItem(.separator())
        for project in viewModel.workspaceSidebarProjects {
            menu.addItem(projectMenu(project))
        }
        menu.addItem(.separator())
        menu.addItem(savedWorkspaceMenu())
        if projectsAreEnabled() {
            menu.addItem(actionItem("New project", #selector(createProject)))
        }
        menu.addItem(actionItem("Quit", #selector(quit)))
    }

    private func workspaceMenu(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> NSMenuItem {
        let item = NSMenuItem(title: boundedNativeMenuTitle(workspace.displayName), action: nil, keyEquivalent: "")
        item.state = workspace.isFocused ? .on : .off
        let submenu = NSMenu()
        let open = actionItem("Switch", #selector(selectWorkspace(_:)))
        open.representedObject = workspace.name
        submenu.addItem(open)
        let rename = actionItem("Rename…", #selector(renameWorkspace(_:)))
        rename.representedObject = workspace.name
        submenu.addItem(rename)
        let destinations = workspaceSidebarProjectDestinations(
            projects: viewModel.workspaceSidebarProjects,
            currentProjectId: workspace.projectId
        )
        let move = NSMenuItem(title: "Move to project", action: nil, keyEquivalent: "")
        move.isEnabled = !destinations.isEmpty
        let moveMenu = NSMenu()
        for project in destinations {
            let destination = actionItem(boundedNativeMenuTitle(project.displayName), #selector(moveWorkspaceToProject(_:)))
            destination.representedObject = WorkspaceProjectMove(workspaceName: workspace.name, projectId: project.id)
            moveMenu.addItem(destination)
        }
        move.submenu = moveMenu
        submenu.addItem(move)
        item.submenu = submenu
        return item
    }

    private func projectMenu(_ project: WorkspaceSidebarProjectViewModel) -> NSMenuItem {
        let item = NSMenuItem(title: boundedNativeMenuTitle(project.displayName), action: nil, keyEquivalent: "")
        item.state = project.id == viewModel.workspaceSidebarActiveProjectId ? .on : .off
        let submenu = NSMenu()
        let open = actionItem("Open", #selector(selectProject(_:)))
        open.representedObject = project.id.rawValue
        submenu.addItem(open)
        let rename = actionItem("Rename…", #selector(renameProject(_:)))
        rename.representedObject = project.id.rawValue
        rename.isEnabled = projectsAreEnabled()
        submenu.addItem(rename)
        let delete = actionItem("Delete project…", #selector(deleteProject(_:)))
        delete.representedObject = project.id.rawValue
        delete.isEnabled = canDeleteWorkspaceProject(project.id)
        submenu.addItem(delete)
        item.submenu = submenu
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    private func savedWorkspaceMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Open saved", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(actionItem("School", #selector(openSchoolSavedWorkspace)))
        item.submenu = submenu
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

    @objc private func openSchoolSavedWorkspace() {
        menu.cancelTracking()
        SavedWorkspaceLauncher.shared.open(.school)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func renameProject(_ item: NSMenuItem) {
        guard let rawId = item.representedObject as? String,
              let project = viewModel.workspaceSidebarProjects.first(where: { $0.id.rawValue == rawId })
        else { return }
        presentNamePrompt("Rename project", initialValue: project.displayName) { name in
            handleWorkspaceSidebarAction(.renameProject(project.id, displayName: name), viewModel: self.viewModel)
        }
    }

    @objc private func renameWorkspace(_ item: NSMenuItem) {
        guard let workspaceName = item.representedObject as? String,
              let workspace = viewModel.workspaceSidebarWorkspaces.first(where: { $0.name == workspaceName })
        else { return }
        presentNamePrompt("Rename workspace", initialValue: workspace.displayName) { name in
            renameWorkspaceFromSidebar(workspaceName, displayName: name)
        }
    }

    @objc private func moveWorkspaceToProject(_ item: NSMenuItem) {
        guard let destination = item.representedObject as? WorkspaceProjectMove else { return }
        handleWorkspaceSidebarAction(
            .moveWorkspaceToProject(destination.workspaceName, projectId: destination.projectId),
            viewModel: viewModel
        )
    }

    @objc private func deleteProject(_ item: NSMenuItem) {
        guard let rawId = item.representedObject as? String,
              let project = viewModel.workspaceSidebarProjects.first(where: { $0.id.rawValue == rawId })
        else { return }
        menu.cancelTracking()
        DispatchQueue.main.async {
            deleteWorkspaceSidebarProject(project, viewModel: self.viewModel)
        }
    }

    @objc private func createProject() {
        presentNamePrompt("New project", initialValue: "") { name in
            createWorkspaceSidebarProject(displayName: name, viewModel: self.viewModel)
        }
    }

    private func presentNamePrompt(_ title: String, initialValue: String, onSave: @escaping (String) -> Void) {
        menu.cancelTracking()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            guard let name = promptForProjectName(title, initialValue: initialValue) else { return }
            onSave(name)
        }
    }
}

private func boundedStatusProjectName(_ title: String, font: NSFont) -> String {
    let maxWidth = standardGap * 32
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    func width(_ value: String) -> CGFloat { (value as NSString).size(withAttributes: attributes).width }
    guard width(title) > maxWidth else { return title }

    var clipped = title
    while !clipped.isEmpty && width(clipped + "…") > maxWidth {
        clipped.removeLast()
    }
    return clipped + "…"
}

private func boundedNativeMenuTitle(_ title: String) -> String {
    let maxWidth = standardGap * 56
    let font = NSFont.menuFont(ofSize: 0)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    func width(_ value: String) -> CGFloat { (value as NSString).size(withAttributes: attributes).width }
    guard width(title) > maxWidth else { return title }
    var clipped = ""
    for character in title {
        let next = clipped + String(character)
        guard width(next + "…") <= maxWidth else { break }
        clipped = next
    }
    return clipped + "…"
}

@MainActor
private func promptForProjectName(_ title: String, initialValue: String) -> String? {
    let field = NSTextField(string: initialValue)
    field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
    let alert = NSAlert()
    alert.messageText = title
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}
