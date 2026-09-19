    import AppKit
    import Common
    import Foundation
    import SwiftUI
    
@MainActor
public func menuBar(viewModel: TrayMenuModel) -> some Scene {
    MenuBarExtra {
        WorkspaceProjectMenuBarContent(viewModel: viewModel)
    } label: {
        MenuBarLabel().environmentObject(viewModel)
    }
}

private struct WorkspaceProjectMenuBarContent: View {
    @ObservedObject var viewModel: TrayMenuModel
    @State private var workspaceNameDrafts: [String: String] = [:]

    private var selectedProjectId: WorkspaceProjectId {
        viewModel.workspaceSidebarActiveProjectId
    }

    private var selectedProject: WorkspaceSidebarProjectViewModel? {
        viewModel.workspaceSidebarProjects.first { $0.id == selectedProjectId }
    }

    var body: some View {
        ForEach(viewModel.workspaceSidebarProjects) { project in
            Menu {
                let workspaces = workspaces(in: project)
                if workspaces.isEmpty {
                    Text("No workspaces")
                } else {
                    ForEach(workspaces) { workspace in
                        workspaceMenu(workspace)
                    }
                }
            } label: {
                if project.id == selectedProjectId {
                    Label(project.displayName, systemImage: "checkmark")
                } else {
                    Text(project.displayName)
                }
            }
        }

        Divider()

        Menu("Config") {
            if let project = selectedProject, projectsAreEnabled() {
                Button("Rename project…") { rename(project) }
                Button("Delete project") {
                    handleWorkspaceSidebarAction(.deleteProject(project.id), viewModel: viewModel)
                }
                .disabled(!canDeleteWorkspaceProject(project.id))
            }
        }

        if projectsAreEnabled() {
            Button("New project") { createProject() }
        }
    }

    private func workspaces(
        in project: WorkspaceSidebarProjectViewModel
    ) -> [WorkspaceSidebarWorkspaceViewModel] {
        viewModel.workspaceSidebarWorkspaces.filter { $0.projectId == project.id }
    }

    @ViewBuilder
    private func workspaceMenu(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> some View {
        Menu {
            Text("Rename")
            TextField("Workspace name", text: workspaceNameBinding(for: workspace))
                .textFieldStyle(.plain)
                .frame(width: standardGap * 45)
                .onSubmit { commitWorkspaceRename(workspace) }
        } label: {
            if workspace.isFocused {
                Label(workspace.displayName, systemImage: "checkmark")
            } else {
                Text(workspace.displayName)
            }
        }
    }

    private func workspaceNameBinding(
        for workspace: WorkspaceSidebarWorkspaceViewModel
    ) -> Binding<String> {
        Binding(
            get: {
                workspaceNameDrafts[workspace.name]
                    ?? (workspace.sidebarLabel.isEmpty ? workspace.displayName : workspace.sidebarLabel)
            },
            set: { workspaceNameDrafts[workspace.name] = $0 }
        )
    }

    private func commitWorkspaceRename(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
        let currentName = workspace.sidebarLabel.isEmpty ? workspace.displayName : workspace.sidebarLabel
        let displayName = (workspaceNameDrafts[workspace.name] ?? currentName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }
        workspaceNameDrafts[workspace.name] = displayName
        handleWorkspaceSidebarAction(
            .renameWorkspace(workspace.name, displayName: displayName),
            viewModel: viewModel
        )
    }

    private func createProject() {
        guard let name = projectNamePrompt(title: "New project", initialValue: "") else { return }
        createWorkspaceSidebarProject(displayName: name, viewModel: viewModel)
    }

    private func rename(_ project: WorkspaceSidebarProjectViewModel) {
        guard let name = projectNamePrompt(title: "Rename project", initialValue: project.displayName) else { return }
        handleWorkspaceSidebarAction(.renameProject(project.id, displayName: name), viewModel: viewModel)
    }
}

@MainActor
private func projectNamePrompt(title: String, initialValue: String) -> String? {
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

@MainActor @ViewBuilder
func openConfigButton(showShortcutGroup: Bool = false) -> some View {
    let button = Button("Open configuration file") {
        switch findCustomConfigUrl() {
            case .file(let url):
                NSWorkspace.shared.open(url)
            case .noCustomConfigExists:
                let createdUrl = try? ensureBootstrapConfigExistsIfNeeded()
                NSWorkspace.shared.open(createdUrl ?? preferredEditableConfigUrl())
            case .ambiguousConfigError:
                NSWorkspace.shared.open(preferredEditableConfigUrl())
        }
    }.keyboardShortcut(",", modifiers: .command)
    if showShortcutGroup {
        shortcutGroup(label: Text("⌘ ,"), content: button)
    } else {
        button
    }
}

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false) -> some View {
    if let token: RunSessionGuard = .isServerEnabled {
        let button = Button("Reload configuration") {
            Task {
                try await runLightSession(.menuBarButton, token) { _ = try await reloadConfig() }
            }
        }.keyboardShortcut("R", modifiers: .command)
        if showShortcutGroup {
            shortcutGroup(label: Text("⌘ R"), content: button)
        } else {
            button
        }
    }
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: standardGap * 3) {
            label
                .foregroundStyle(winMuxOverlayContent(.secondary))
            content
        }
    }
}
