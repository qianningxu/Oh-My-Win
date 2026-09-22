import AppKit
import Common
import MASShortcut
import SwiftUI

public let shortcutSettingsWindowId = "\(winMuxAppName).shortcutSettings"

struct ShortcutSettingsWindowPresentationRetryPolicy: Equatable {
    var maxAttempts = 20
    var delayNanoseconds: UInt64 = 50_000_000
}

@MainActor
public func getShortcutSettingsWindow(model: ShortcutSettingsModel) -> some Scene {
    SwiftUI.Window("Oh-My-Win Settings", id: shortcutSettingsWindowId) {
        ShortcutSettingsView(model: model)
            .frame(minWidth: 720, minHeight: 600)
            .onAppear {
                NSApp.setActivationPolicy(.regular)
            }
    }
}

@MainActor
public func openShortcutSettingsWindow(_ openWindow: OpenWindowAction) {
    ShortcutSettingsModel.shared.reload()
    if let existingWindow = shortcutSettingsWindow() {
        presentShortcutSettingsWindow(existingWindow)
    } else {
        openWindow(id: shortcutSettingsWindowId)
        presentShortcutSettingsWindowWhenAvailable()
    }
}

@MainActor
@discardableResult
func presentShortcutSettingsWindowWhenAvailable(
    policy: ShortcutSettingsWindowPresentationRetryPolicy = .init(),
    lookup: @escaping @MainActor () -> NSWindow? = { shortcutSettingsWindow() },
    present: @escaping @MainActor (NSWindow) -> Void = { presentShortcutSettingsWindow($0) },
) -> Task<Void, Never> {
    Task { @MainActor in
        let maxAttempts = max(1, policy.maxAttempts)
        for attempt in 0 ..< maxAttempts {
            if let window = lookup() {
                present(window)
                return
            }
            guard attempt + 1 < maxAttempts else { return }
            do {
                try await Task.sleep(nanoseconds: policy.delayNanoseconds)
            } catch {
                return
            }
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        NavigationSplitView {
            List(ShortcutSettingsModel.Tab.allCases, selection: $model.selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: standardGap * 50, ideal: standardGap * 55)
        } detail: {
            switch model.selectedTab {
                case .setting:
                    SettingsDashboardView(model: model)
                case .savedWorkspace:
                    SavedWorkspacesView()
            }
        }
    }
}

private struct SettingsDashboardView: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: standardGap * 20) {
                if let error = model.errorMessage {
                    Text(error)
                        .foregroundStyle(winMuxOverlayGeistBackground(.primary))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(winMuxOverlayColor(.red, .color7))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                UnifiedSettingsSection(title: "Managed shortcuts", systemImage: "keyboard") {
                    ShortcutCategoryView(model: model, category: .managed)
                }

                UnifiedSettingsSection(title: "Common shortcuts", systemImage: "keyboard") {
                    ShortcutCategoryView(model: model, category: .common)
                }

                UnifiedSettingsSection(title: "General", systemImage: "gearshape") {
                    ShortcutGeneralView(model: model)
                }

                UnifiedSettingsSection(title: "Advanced", systemImage: "slider.horizontal.3") {
                    ShortcutAdvancedView(model: model)
                }
            }
            .padding(standardGap * 12)
        }
    }
}

private struct UnifiedSettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: standardGap * 8) {
            Label(title, systemImage: systemImage)
                .font(.title2.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShortcutCategoryView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let category: ShortcutSettingsModel.Category

    var body: some View {
        LazyVStack(alignment: .leading, spacing: standardGap * 16) {
            let sections = model.sections.filter { $0.category == category && $0.id != "managed-move" }
            ForEach(sections) { section in
                ShortcutSectionView(model: model, section: section)
            }
        }
    }
}

struct ShortcutSectionView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let section: ShortcutSettingsModel.Section

    var body: some View {
        VStack(alignment: .leading, spacing: standardGap * 8) {
            if section.id != "managed-focus" {
                VStack(alignment: .leading, spacing: standardGap * 1) {
                    Text(section.title)
                        .font(.headline)
                    if let summary = section.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(winMuxOverlayContent(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if section.id == "managed-focus" {
                ManagedDirectionalShortcutsView(model: model)
            } else if section.id == "managed-move" {
                EmptyView()
            } else if section.id == "managed-splits" {
                CompassPad(model: model, title: "Split", prefix: "split") {
                    SplitDemoView()
                }
            } else if section.id == "workspaces" {
                WorkspaceShortcutSectionView(model: model)
            } else {
                VStack(spacing: standardGap * 0) {
                    ForEach(section.actions.indices, id: \.self) { index in
                        let action = section.actions[index]
                        ShortcutRow(model: model, action: action)
                        if index < section.actions.count - 1 {
                            Divider().padding(.leading, standardGap * 6)
                        }
                    }
                }
                .background(winMuxOverlayGeistBackground(.primary))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(winMuxOverlayBorder(.normal), lineWidth: 0.5)
                )
            }
        }
    }
}


struct ShortcutRow: View {
    @ObservedObject var model: ShortcutSettingsModel
    let action: ShortcutSettingsModel.Action

    var body: some View {
        HStack(spacing: standardGap * 6) {
            VStack(alignment: .leading, spacing: standardGap * 1) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(winMuxOverlayContent(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderView(
                shortcut: .init(get: { model.shortcutValue(for: action.id) },
                                set: { model.setShortcutValue($0, for: action.id) }),
                onChange: { _ in }
            )
            .frame(width: 140, height: 22)
        }
        .padding(.vertical, standardGap * 5)
        .padding(.horizontal, standardGap * 6)
    }
}
