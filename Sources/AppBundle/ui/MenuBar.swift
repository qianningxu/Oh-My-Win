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

    private var selectedProjectId: WorkspaceProjectId {
        viewModel.workspaceSidebarActiveProjectId
    }

    var body: some View {
        ForEach(viewModel.workspaceSidebarProjects) { project in
            if project.id == selectedProjectId {
                Menu {
                    let workspaces = workspaces(in: project)
                    if workspaces.isEmpty {
                        Text("No workspaces")
                    } else {
                        ForEach(workspaces) { workspace in
                            Button {
                                handleWorkspaceSidebarAction(
                                    .selectWorkspace(workspace.name),
                                    viewModel: viewModel
                                )
                            } label: {
                                if workspace.isFocused {
                                    Label(workspace.displayName, systemImage: "checkmark")
                                } else {
                                    Text(workspace.displayName)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Rename current project…") { rename(project) }
                        .disabled(!projectsAreEnabled())
                } label: {
                    Label(project.displayName, systemImage: "checkmark")
                }
            } else {
                Button(project.displayName) {
                    handleWorkspaceSidebarAction(.selectProject(project.id), viewModel: viewModel)
                }
            }
        }

        Divider()
        if projectsAreEnabled() {
            Button("New project") { createProject() }
        }
        Button("Show Dashboard") { openWorkspaceSidebarFromMenu() }
        Button("Quit") { NSApp.terminate(nil) }
    }

    private func workspaces(
        in project: WorkspaceSidebarProjectViewModel
    ) -> [WorkspaceSidebarWorkspaceViewModel] {
        viewModel.workspaceSidebarWorkspaces.filter { $0.projectId == project.id }
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
