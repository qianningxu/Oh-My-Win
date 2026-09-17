import SwiftUI

struct WorkspaceSidebarProjectMenu<Configuration: View>: View {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let allowsCreation: Bool
    let onSelect: (WorkspaceProjectId) -> Void
    let onCreate: (String) -> Void
    @ViewBuilder let configuration: () -> Configuration

    @State private var isCreating = false
    @State private var name = ""
    @FocusState private var nameIsFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    private var duplicateName: Bool {
        guard let name = workspaceSidebarNewProjectName(name) else { return false }
        return projects.contains { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: standardGap) {
            ScrollView {
                VStack(spacing: WinMuxSpacing.hairline) {
                    ForEach(projects) { project in
                        Button { onSelect(project.id) } label: {
                            HStack {
                                Text(project.displayName).lineLimit(1)
                                Spacer()
                                if project.id == selectedProjectId {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: workspaceSidebarProjectPopupRowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: min(CGFloat(projects.count) * (workspaceSidebarProjectPopupRowHeight + WinMuxSpacing.hairline), standardGap * 70))
            Divider()
            configuration()
            if allowsCreation {
                Divider()
                if isCreating {
                    HStack {
                        TextField("Project name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameIsFocused)
                            .onSubmit(createProject)
                            .onExitCommand { isCreating = false }
                            .task { nameIsFocused = true }
                            .accessibilityLabel("Project name")
                        Button("Create", action: createProject)
                            .disabled(workspaceSidebarNewProjectName(name) == nil || duplicateName)
                    }
                    if duplicateName {
                        Text("A project with this name already exists.")
                            .font(.caption)
                            .foregroundStyle(palette.content(.secondary))
                    }
                } else {
                    Button {
                        name = ""
                        isCreating = true
                    } label: {
                        Label("New project", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(.system(size: workspaceSidebarProjectLabelFontSize))
        .foregroundStyle(palette.content(.primary))
        .padding(WinMuxSpacing.section)
        .frame(width: standardGap * 70)
        .background(palette.geistBackground(.primary))

    }

    private func createProject() {
        guard let name = workspaceSidebarNewProjectName(name), !duplicateName else { return }
        onCreate(name)
        self.name = ""
        isCreating = false
    }
}
