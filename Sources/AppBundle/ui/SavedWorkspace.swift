import AppKit
import Common
import SwiftUI

enum SavedWorkspacePreset: String, CaseIterable, Identifiable, Sendable {
    case school

    var id: String { rawValue }

    var title: String {
        switch self {
            case .school: "School"
        }
    }

    var summary: String {
        switch self {
            case .school: "Two Obsidian vaults stacked together in the leftmost pane."
        }
    }

    var obsidianWindows: [SavedObsidianWindow] {
        switch self {
            case .school:
                [
                    SavedObsidianWindow(vault: "y4s1", file: "handbook"),
                    SavedObsidianWindow(vault: "self_ob", file: "2026-09-19"),
                ]
        }
    }
}

struct SavedObsidianWindow: Hashable, Sendable {
    let vault: String
    let file: String
}

@MainActor
final class SavedWorkspaceLauncher: ObservableObject {
    static let shared = SavedWorkspaceLauncher()

    @Published private(set) var openingPreset: SavedWorkspacePreset?
    @Published private(set) var errorMessage: String?

    private init() {}

    func open(_ preset: SavedWorkspacePreset) {
        guard openingPreset == nil else { return }
        openingPreset = preset
        errorMessage = nil
        Task { @MainActor in
            defer { openingPreset = nil }
            do {
                try await instantiateSavedWorkspace(preset)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct SavedWorkspacesView: View {
    @ObservedObject private var launcher = SavedWorkspaceLauncher.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: standardGap * 12) {
                Text("Saved workspace")
                    .font(.title2.weight(.semibold))
                Text("Open a fresh tab with a reusable set of apps and layout.")
                    .foregroundStyle(winMuxOverlayContent(.secondary))

                ForEach(SavedWorkspacePreset.allCases) { preset in
                    savedWorkspaceCard(preset)
                }

                if let errorMessage = launcher.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(winMuxOverlayColor(.red, .color9))
                        .padding(standardGap * 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(winMuxOverlayColor(.red, .color1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(standardGap * 12)
        }
    }

    private func savedWorkspaceCard(_ preset: SavedWorkspacePreset) -> some View {
        VStack(alignment: .leading, spacing: standardGap * 6) {
            HStack(alignment: .top, spacing: standardGap * 6) {
                Image(systemName: "graduationcap")
                    .font(.title2)
                VStack(alignment: .leading, spacing: standardGap * 1) {
                    Text(preset.title)
                        .font(.headline)
                    Text(preset.summary)
                        .font(.subheadline)
                        .foregroundStyle(winMuxOverlayContent(.secondary))
                }
                Spacer()
                Button(launcher.openingPreset == preset ? "Opening…" : "Open") {
                    launcher.open(preset)
                }
                .disabled(launcher.openingPreset != nil)
            }

            Divider()

            ForEach(preset.obsidianWindows, id: \.self) { window in
                Label("\(window.vault) — \(window.file)", systemImage: "diamond")
                    .font(.system(size: 12))
                    .foregroundStyle(winMuxOverlayContent(.secondary))
            }
        }
        .padding(standardGap * 7)
        .background(winMuxOverlayGeistBackground(.primary))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(winMuxOverlayBorder(.normal), lineWidth: 0.5)
        )
    }
}

private enum SavedWorkspaceError: LocalizedError {
    case appDisabled
    case cannotCreateTab
    case obsidianCLIUnavailable
    case obsidianCommandFailed(String)
    case windowNotFound(SavedObsidianWindow)

    var errorDescription: String? {
        switch self {
            case .appDisabled:
                "Oh-My-Win must be enabled to open a saved workspace."
            case .cannotCreateTab:
                "Oh-My-Win could not create a new tab for this saved workspace."
            case .obsidianCLIUnavailable:
                "Obsidian CLI was not found in the installed Obsidian app."
            case .obsidianCommandFailed(let message):
                "Obsidian could not open the saved workspace. \(message)"
            case .windowNotFound(let window):
                "Obsidian did not create the \(window.vault) — \(window.file) window."
        }
    }
}

@MainActor
private func instantiateSavedWorkspace(_ preset: SavedWorkspacePreset) async throws {
    guard let token = RunSessionGuard.isServerEnabled else {
        throw SavedWorkspaceError.appDisabled
    }
    let existingWindowIds = Set(MacWindow.allWindowsMap.keys)
    let currentWorkspace = focus.workspace
    let targetWorkspace = try await runLightSession(
        .menuBarButton,
        token,
        shouldSchedulePostRefresh: false,
        prioritizeFocusSync: true
    ) {
        let workspace = createFreshAdjacentBlankWorkspace(
            folderId: currentWorkspace.folderId,
            monitor: currentWorkspace.workspaceMonitor,
            after: currentWorkspace
        )
        guard workspace.focusWorkspace() else {
            throw SavedWorkspaceError.cannotCreateTab
        }
        return workspace
    }

    var openedWindows: [MacWindow] = []
    var knownWindowIds = existingWindowIds
    for window in preset.obsidianWindows {
        try await openObsidianWindow(window)
        let openedWindow = try await waitForSavedObsidianWindow(
            window,
            excluding: knownWindowIds,
            targetWorkspace: targetWorkspace
        )
        openedWindows.append(openedWindow)
        knownWindowIds.insert(openedWindow.windowId)
    }

    try await runLightSession(.menuBarButton, token, prioritizeFocusSync: true) {
        let io = CmdIo(stdin: .emptyStdin)
        for window in openedWindows where window.nodeWorkspace !== targetWorkspace {
            guard moveWindowToWorkspace(
                window,
                targetWorkspace,
                io,
                focusFollowsWindow: false,
                failIfNoop: false
            ) else {
                throw SavedWorkspaceError.cannotCreateTab
            }
        }
        guard let firstWindow = openedWindows.first else { return }
        for window in openedWindows.dropFirst() {
            createOrAppendWindowTabStack(sourceWindow: window, onto: firstWindow)
        }
        if let stack = firstWindow.parent as? TilingContainer,
           stack.layout == .tabGroup,
           stack.ownIndex != 0
        {
            stack.unbindFromParent()
            stack.bind(
                to: targetWorkspace.rootTilingContainer,
                adaptiveWeight: WEIGHT_AUTO,
                index: 0
            )
        }
        _ = targetWorkspace.focusWorkspace()
    }
    persistSidebarStateForRestartIfPossible()
}

private func openObsidianWindow(_ window: SavedObsidianWindow) async throws {
    let executable = URL(filePath: "/Applications/Obsidian.app/Contents/MacOS/obsidian-cli")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        throw SavedWorkspaceError.obsidianCLIUnavailable
    }
    try await runProcess(
        executable,
        arguments: ["vault=\(window.vault)", "open", "file=\(window.file)"]
    )
    try await runProcess(
        executable,
        arguments: ["vault=\(window.vault)", "command", "id=workspace:open-in-new-window"]
    )
}

@MainActor
private func waitForSavedObsidianWindow(
    _ requestedWindow: SavedObsidianWindow,
    excluding existingWindowIds: Set<UInt32>,
    targetWorkspace: Workspace
) async throws -> MacWindow {
    for _ in 0 ..< 30 {
        try await Task.sleep(nanoseconds: 100_000_000)
        try await runRefreshSessionBlocking(.windowInventoryReconciliation)
        for window in MacWindow.allWindows where
            !existingWindowIds.contains(window.windowId) &&
            window.macApp.rawAppBundleId == "md.obsidian"
        {
            let title = try await window.title
            if title.localizedCaseInsensitiveContains(requestedWindow.file) &&
                title.localizedCaseInsensitiveContains(requestedWindow.vault)
            {
                if window.nodeWorkspace !== targetWorkspace {
                    let io = CmdIo(stdin: .emptyStdin)
                    _ = moveWindowToWorkspace(
                        window,
                        targetWorkspace,
                        io,
                        focusFollowsWindow: false,
                        failIfNoop: false
                    )
                }
                return window
            }
        }
    }
    throw SavedWorkspaceError.windowNotFound(requestedWindow)
}

private func runProcess(_ executable: URL, arguments: [String]) async throws {
    let result = try await Task.detached {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let message = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, message)
    }.value
    guard result.0 == 0 else {
        throw SavedWorkspaceError.obsidianCommandFailed(result.1)
    }
}
