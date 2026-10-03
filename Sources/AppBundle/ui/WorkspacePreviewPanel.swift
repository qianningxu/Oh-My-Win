import AppKit
import SwiftUI

private let workspacePreviewPanelId = "WinMux.workspacePreview"
let workspacePreviewWindowWidth = standardGap * 45
let workspacePreviewWindowHeight = standardGap * 28
private let workspacePreviewTileHeight = workspacePreviewWindowHeight + standardGap * 10
private let workspacePreviewCardChromeHeight = standardGap * 12
private let workspacePreviewCardWidth = workspacePreviewWindowWidth * 2 + WinMuxSpacing.regular * 3
let workspacePreviewMaximumWidth = standardGap * 280
let workspacePreviewMaximumHeight = standardGap * 180
private let workspacePreviewCardSpacing = standardGap * 3.5
private let workspacePreviewPanelPadding = standardGap * 6

private struct WorkspacePreviewItem: Identifiable {
    let id: String
    let workspace: Workspace
    let displayName: String
    let windows: [WorkspacePreviewWindowItem]
}

struct WorkspacePreviewWindowItem: Identifiable {
    let id: UInt32
    let title: String
    let appName: String
    let appIcon: NSImage?
    let thumbnail: NSImage?
}

@MainActor
final class WorkspacePreviewPanel: NSPanelHud {
    static let shared = WorkspacePreviewPanel()

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var items: [WorkspacePreviewItem] = []
    private var selectedIndex: Int = 0
    private(set) var isPreviewActive = false

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(workspacePreviewPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .clear
        applyWinMuxLayer(.overlay)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func present() {
        guard !isPreviewActive else { return }
        begin(direction: 0)
    }

    func advance(direction: Int) {
        if !isPreviewActive {
            begin(direction: direction)
            return
        }
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + direction + items.count) % items.count
        render()
    }

    func select(index: Int) {
        if !isPreviewActive {
            begin(direction: 0)
        }
        guard isPreviewActive, items.indices.contains(index) else { return }
        selectedIndex = index
        render()
    }

    func commitIfActive() {
        guard isPreviewActive else { return }
        let target = items.getOrNil(atIndex: selectedIndex)?.workspace
        dismiss()
        guard let target, target != focus.workspace else { return }
        Task { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.menuBarButton, token) {
                rearrangeWorkspacesOnMonitors()
                _ = target.focusWorkspace()
            }
        }
    }

    func dismiss() {
        guard isPreviewActive else { return }
        isPreviewActive = false
        items = []
        selectedIndex = 0
        orderOut(nil)
        hostingView.rootView = AnyView(EmptyView())
    }

    private func begin(direction: Int) {
        let current = focus.workspace
        let candidates = workspacePreviewCandidateWorkspaces(current: current)
        guard !candidates.isEmpty else { return }
        items = candidates.map { workspace in
            return WorkspacePreviewItem(
                id: workspace.name,
                workspace: workspace,
                displayName: workspaceDisplayName(workspace.name),
                windows: workspacePreviewWindowItems(for: workspace),
            )
        }
        let currentIndex = items.firstIndex { $0.workspace == current } ?? 0
        selectedIndex = (currentIndex + direction + items.count) % items.count
        isPreviewActive = true
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let width = workspacePreviewPanelWidth(itemCount: items.count, availableWidth: screenFrame.width)
        let height = workspacePreviewPanelHeight(
            maximumWindowCount: items.map { $0.windows.count }.max() ?? 0,
            availableHeight: screenFrame.height
        )
        setFrame(CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width,
            height: height
        ), display: true, animate: false)
        render()
        orderFrontRegardless()
    }

    private func render() {
        hostingView.rootView = AnyView(
            WorkspacePreviewView(
                items: items,
                selectedIndex: selectedIndex,
                onSelect: { [weak self] index in
                    self?.selectedIndex = index
                    self?.commitIfActive()
                },
                onDismiss: { [weak self] in self?.dismiss() },
            )
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss(); return }
        super.keyDown(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
func workspacePreviewCandidateWorkspaces(current: Workspace) -> [Workspace] {
    userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: current)
        .filter {
            $0.projectId == current.projectId &&
                $0.workspaceMonitor.rect.topLeftCorner == current.workspaceMonitor.rect.topLeftCorner
        }
}

@MainActor
func handleWorkspacePreviewHotkey(_ binding: String) -> Bool {
    switch binding {
        case "alt-tab":
            WorkspacePreviewPanel.shared.advance(direction: 1)
            return true
        case "alt-shift-tab":
            WorkspacePreviewPanel.shared.advance(direction: -1)
            return true
        default:
            guard workspacePreviewSelectionIndex(for: binding) != nil else { return false }
            WorkspacePreviewPanel.shared.dismiss()
            return false
    }
}

func workspacePreviewSelectionIndex(for binding: String) -> Int? {
    guard binding.hasPrefix("alt-"),
          let number = Int(binding.dropFirst("alt-".count)),
          (0 ... 9).contains(number)
    else {
        return nil
    }
    return number == 0 ? 9 : number - 1
}

// Enumerate every leaf rather than the visible representative of each tab stack.
// Hidden workspaces can have offscreen or missing frames; neither excludes a window.
@MainActor
func workspacePreviewWindowItems(for workspace: Workspace) -> [WorkspacePreviewWindowItem] {
    (workspace.rootTilingContainer.allLeafWindowsRecursive + workspace.floatingWindows + workspaceOwnedMinimizedWindows(workspace))
        .filter { $0.isBound }
        .map { window in
            WorkspacePreviewWindowItem(
                id: window.windowId,
                title: sidebarDisplayLabel(for: window),
                appName: window.app.name ?? "Unknown",
                appIcon: appIconImage(bundleIdentifier: window.app.rawAppBundleId, bundlePath: window.app.bundlePath),
                thumbnail: cachedExposeThumbnail(window.windowId).map { NSImage(cgImage: $0, size: .zero) },
            )
        }
}

func workspacePreviewPanelWidth(itemCount: Int, availableWidth: CGFloat) -> CGFloat {
    let itemCount = max(itemCount, 0)
    let contentWidth = CGFloat(itemCount) * workspacePreviewCardWidth +
        CGFloat(max(itemCount - 1, 0)) * workspacePreviewCardSpacing +
        workspacePreviewPanelPadding * 2
    return min(contentWidth, workspacePreviewMaximumWidth, availableWidth * 0.92)
}

func workspacePreviewPanelHeight(maximumWindowCount: Int, availableHeight: CGFloat) -> CGFloat {
    let rows = max((max(maximumWindowCount, 0) + 1) / 2, 1)
    let contentHeight = CGFloat(rows) * workspacePreviewTileHeight +
        CGFloat(rows - 1) * WinMuxSpacing.regular + workspacePreviewCardChromeHeight +
        workspacePreviewPanelPadding * 1.5
    return min(contentHeight, workspacePreviewMaximumHeight, availableHeight * 0.8)
}

private struct WorkspacePreviewView: View {
    let items: [WorkspacePreviewItem]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onDismiss: () -> Void
    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            GeometryReader { geometry in
                let panelWidth = geometry.size.width
                let contentHeight = max(
                    geometry.size.height - workspacePreviewPanelPadding * 1.5 - workspacePreviewCardChromeHeight,
                    0
                )

                ScrollViewReader { proxy in
                    VStack {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: workspacePreviewCardSpacing) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    WorkspacePreviewCard(
                                        item: item,
                                        isSelected: index == selectedIndex,
                                        maximumContentHeight: contentHeight,
                                    )
                                    .id(index)
                                    .onTapGesture { onSelect(index) }
                                }
                            }
                            .padding(.horizontal, workspacePreviewPanelPadding)
                            .padding(.top, workspacePreviewPanelPadding)
                            .padding(.bottom, workspacePreviewPanelPadding * 0.5)
                            .frame(minWidth: panelWidth, alignment: .center)
                        }
                        .frame(width: panelWidth, height: geometry.size.height)
                        .background { WorkspacePreviewSwitcherSurface() }
                        .clipShape(RoundedRectangle(cornerRadius: standardGap * 8, style: .continuous))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear { proxy.scrollTo(selectedIndex, anchor: .center) }
                    .onChange(of: selectedIndex) { index in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

private struct WorkspacePreviewCard: View {
    let item: WorkspacePreviewItem
    let isSelected: Bool
    let maximumContentHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WinMuxOverlayPalette { WinMuxOverlayPalette(colorScheme: colorScheme) }

    var body: some View {
        let columns = 2
        let rows = max((item.windows.count + columns - 1) / columns, 1)
        let tileHeight = workspacePreviewTileHeight
        VStack(alignment: .leading, spacing: WinMuxSpacing.section) {
            HStack(spacing: WinMuxSpacing.compact) {
                Text(item.displayName)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: WinMuxSpacing.compact)
                Text("\(item.windows.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.content(.secondary))
            }
            .foregroundStyle(palette.content(.primary))

            ScrollView(.vertical, showsIndicators: true) {
                if item.windows.isEmpty {
                    Text("Empty")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.content(.secondary))
                        .frame(maxWidth: .infinity, minHeight: tileHeight)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(workspacePreviewWindowWidth), spacing: WinMuxSpacing.regular), count: columns),
                        spacing: WinMuxSpacing.regular
                    ) {
                        ForEach(item.windows) { window in
                            VStack(alignment: .leading, spacing: WinMuxSpacing.compact) {
                                WorkspacePreviewWindowTile(window: window)
                                    .frame(width: workspacePreviewWindowWidth, height: workspacePreviewWindowHeight)
                                Text(window.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(palette.content(.primary))
                                    .lineLimit(1)
                                Text(window.appName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(palette.content(.secondary))
                                    .lineLimit(1)
                            }
                            .frame(width: workspacePreviewWindowWidth, height: tileHeight, alignment: .topLeading)
                            .help(window.title)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(rows) * tileHeight + CGFloat(rows - 1) * WinMuxSpacing.regular, maximumContentHeight))
        }
        .padding(WinMuxSpacing.regular)
        .frame(width: workspacePreviewCardWidth)
        .background(palette.componentBackground(isSelected ? .active : .normal))
        .clipShape(RoundedRectangle(cornerRadius: WinMuxSpacing.section, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WinMuxSpacing.section, style: .continuous)
                .strokeBorder(palette.geistBorder(isSelected ? .active : .normal), lineWidth: isSelected ? 2 : 1)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isSelected)
    }
}

private struct WorkspacePreviewSwitcherSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WinMuxOverlayPalette(colorScheme: colorScheme)
        RoundedRectangle(cornerRadius: standardGap * 8, style: .continuous)
            .fill(palette.geistBackground(.primary))
            .overlay {
                RoundedRectangle(cornerRadius: standardGap * 8, style: .continuous)
                    .strokeBorder(palette.geistBorder(.normal), lineWidth: 1)
            }
            .allowsHitTesting(false)
    }
}

private struct WorkspacePreviewWindowTile: View {
    let window: WorkspacePreviewWindowItem
    @State private var refreshedThumbnail: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WinMuxOverlayPalette { WinMuxOverlayPalette(colorScheme: colorScheme) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: WinMuxSpacing.regular, style: .continuous)
                .fill(palette.geistBackground(.secondary))
            if let thumbnail = refreshedThumbnail ?? window.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: WinMuxSpacing.regular, style: .continuous))
            } else {
                WorkspacePreviewWindowFallback(window: window)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: WinMuxSpacing.regular, style: .continuous))
        .task(id: window.id) {
            guard let image = await captureExposeThumbnail(window.id) else { return }
            refreshedThumbnail = NSImage(cgImage: image, size: .zero)
        }
    }
}

private struct WorkspacePreviewWindowFallback: View {
    let window: WorkspacePreviewWindowItem
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WinMuxOverlayPalette { WinMuxOverlayPalette(colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            let minDimension = max(min(geometry.size.width, geometry.size.height), 1)

            ZStack {
                palette.componentBackground(.normal)

                if let appIcon = window.appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(max(WinMuxSpacing.comfortable, minDimension * 0.24))
                } else {
                    Text(workspacePreviewFallbackInitials(for: window))
                        .font(.system(size: max(12, minDimension * 0.34), weight: .bold, design: .rounded))
                        .foregroundStyle(palette.content(.primary))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
        }
    }
}

private func workspacePreviewFallbackInitials(for window: WorkspacePreviewWindowItem) -> String {
    let source = window.appName.isEmpty || window.appName == "Unknown" ? window.title : window.appName
    let initials = source
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .prefix(2)
        .compactMap(\.first)
        .map { String($0).uppercased() }
        .joined()
    return initials.isEmpty ? "W" : initials
}
