import AppKit
import SwiftUI
import Common

private let workspacePreviewPanelId = "WinMux.workspacePreview"
let workspacePreviewWindowWidth = standardGap * 55
let workspacePreviewWindowHeight = workspacePreviewWindowWidth
let workspacePreviewColumns = 5
let workspacePreviewMaximumRows = 3
let workspacePreviewMaximumWindows = workspacePreviewColumns * workspacePreviewMaximumRows
private let workspacePreviewTileHeight = workspacePreviewWindowHeight + WinMuxSpacing.comfortable + standardGap * 3.5
private let workspacePreviewRowSpacing = standardGap * 3
private let workspacePreviewPanelPadding = WinMuxSpacing.page
let workspacePreviewMaximumWidth = standardGap * 420
let workspacePreviewCornerRadius = standardGap * 1.75
let workspacePreviewFocusRingWidth = standardGap * 2
let workspacePreviewMaximumHeight = standardGap * 250

private struct WorkspacePreviewItem: Identifiable {
    let id: String
    let workspace: Workspace
    let displayName: String
    let windows: [WorkspacePreviewWindowItem]
    let legacyWindows: [WorkspacePreviewWindowItem]
    let workspaceAspectRatio: CGFloat
}

struct WorkspacePreviewWindowItem: Identifiable {
    let id: UInt32
    let title: String
    let appName: String
    let appIcon: NSImage?
    let thumbnail: NSImage?
    var layoutFrame: CGRect = .zero
    var stackId: UInt32? = nil
}

@MainActor
final class WorkspacePreviewPanel: NSPanelHud {
    static let shared = WorkspacePreviewPanel()

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var items: [WorkspacePreviewItem] = []
    private var currentIndex: Int = 0
    private var selectedIndex: Int = 0
    private var selectedWindowId: UInt32?
    private var pendingKeyCode: UInt16?
    private var pendingCommands: [any Command]?
    private var isOptionPressed = false
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
        selectedWindowId = nil
        selectedIndex = (selectedIndex + direction + items.count) % items.count
        render()
    }

    func select(index: Int) {
        if !isPreviewActive {
            begin(direction: 0)
        }
        guard isPreviewActive, items.indices.contains(index) else { return }
        selectedWindowId = nil
        selectedIndex = index
        render()
    }

    func commitIfActive() {
        guard isPreviewActive else { return }
        let targetWindow = selectedWindowId.flatMap { Window.get(byId: $0) }
        let target = items.getOrNil(atIndex: selectedIndex)?.workspace
        pendingKeyCode = nil
        pendingCommands = nil
        if !isOptionPressed { dismiss() }
        if let targetWindow {
            Task { @MainActor in
                guard let token: RunSessionGuard = .isServerEnabled else { return }
                try await runLightSession(.hotkeyBinding, token) { _ = targetWindow.focusWindow() }
                refreshAfterShortcutSwitch()
            }
            return
        }
        guard let target, target != focus.workspace else { return }
        Task { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.menuBarButton, token) {
                rearrangeWorkspacesOnMonitors()
                _ = target.focusWorkspace()
            }
            refreshAfterShortcutSwitch()
        }
    }

    private func refreshAfterShortcutSwitch() {
        if isOptionPressed && isPreviewActive { begin(direction: 0) }
    }

    func dismiss() {
        guard isPreviewActive else { return }
        isPreviewActive = false
        items = []
        selectedIndex = 0
        selectedWindowId = nil
        pendingKeyCode = nil
        pendingCommands = nil
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
                legacyWindows: workspacePreviewWindowItems(for: workspace, workspaceRect: workspacePreviewRect(for: workspace)),
                workspaceAspectRatio: workspacePreviewAspectRatio(for: workspace.workspaceMonitor.rect),
            )
        }
        currentIndex = items.firstIndex { $0.workspace == current } ?? 0
        selectedIndex = (currentIndex + direction + items.count) % items.count
        selectedWindowId = direction == 0 ? focus.windowOrNil?.windowId : nil
        isPreviewActive = true
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rows = workspacePreviewStackRows(items[currentIndex].windows)
        let widestRow = rows.map(\.count).max() ?? 1
        let width = workspacePreviewPanelWidth(itemCount: items.count, availableWidth: screenFrame.width, windowCount: widestRow, workspaceAspectRatio: items[currentIndex].workspaceAspectRatio)
        let height = workspacePreviewPanelHeight(
            maximumWindowCount: items[currentIndex].windows.count,
            availableHeight: screenFrame.height,
            workspaceCount: max(items.count - 1, 0),
            columns: workspacePreviewColumnCount(windowCount: widestRow, workspaceCount: items.count, availableWidth: width, workspaceAspectRatio: items[currentIndex].workspaceAspectRatio),
            stackRowCount: rows.count,
            workspaceAspectRatio: items[currentIndex].workspaceAspectRatio
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
                currentIndex: currentIndex,
                selectedIndex: selectedIndex,
                selectedWindowId: selectedWindowId,
                onSelect: { [weak self] index in
                    self?.selectedWindowId = nil
                    self?.selectedIndex = index
                    self?.commitIfActive()
                },
                onWindowSelect: { [weak self] id in
                    self?.dismiss()
                    Task { @MainActor in
                        guard let token: RunSessionGuard = .isServerEnabled else { return }
                        try await runLightSession(.menuBarButton, token) {
                            _ = Window.get(byId: id)?.focusWindow()
                        }
                    }
                },
                onDismiss: { [weak self] in self?.dismiss() },
            )
        )
    }

    // Preview selection changes on key-down; native focus changes on key-up.
    func previewShortcut(commands: [any Command], keyCode: UInt16) -> Bool {
        guard commands.count == 1 else { return false }
        pendingCommands = nil
        if let command = commands[0] as? FocusCommand,
           case .tabRelative(let direction) = command.args.target {
            present()
            guard isPreviewActive else { return true }
            let workspace = items[currentIndex].workspace
            let window = selectedWindowId.flatMap { Window.get(byId: $0) } ?? focus.windowOrNil
            let target = LiveFocus(windowOrNil: window, workspace: workspace)
            pendingKeyCode = keyCode
            guard let candidate = workspacePreviewRelativeWindow(target, command.args.boundariesAction, direction) else { return true }
            selectedWindowId = candidate.windowId
            selectedIndex = currentIndex
            render()
            return true
        }
        if let command = commands[0] as? WorkspaceCommand {
            if case .fresh = command.args.target.val { return false }
            present()
            guard isPreviewActive else { return true }
            let current = items[selectedIndex].workspace
            let target: Workspace?
            switch command.args.target.val {
                case .direct(let name): target = findDirectWorkspaceTarget(named: name.raw, from: current)
                case .relative(let direction): target = getNextPrevWorkspace(current: current, isNext: direction == .next, wrapAround: true, stdin: nil)
                case .fresh: return false
            }
            guard let target, let index = items.firstIndex(where: { $0.workspace == target }) else {
                pendingCommands = commands
                pendingKeyCode = keyCode
                return true
            }
            selectedWindowId = nil
            selectedIndex = index
            pendingKeyCode = keyCode
            render()
            return true
        }
        return false
    }

    func shortcutKeyReleased(_ keyCode: UInt16) {
        guard pendingKeyCode == keyCode else { return }
        pendingKeyCode = nil
        if let commands = pendingCommands {
            pendingCommands = nil
            if !isOptionPressed { dismiss() }
            Task { @MainActor in
                guard let token: RunSessionGuard = .isServerEnabled else { return }
                try await runLightSession(.hotkeyBinding, token, shouldSchedulePostRefresh: !commands.canSkipPostCommandRefresh) {
                    _ = try await commands.runCmdSeq(.defaultEnv, .emptyStdin)
                }
                refreshAfterShortcutSwitch()
            }
            return
        }
        commitIfActive()
    }

    func optionReleased() {
        isOptionPressed = false
        // Releasing Option alone cancels the reveal. A selected shortcut waits
        // for its physical key-up even if Option is released first.
        if pendingKeyCode == nil { dismiss() }
    }

    func optionPressed() {
        guard !isOptionPressed else { return }
        isOptionPressed = true
        present()
    }

    func hotkeyReleased(_ keyCode: UInt16) {
        // Carbon reports a chord release when its modifier is lifted too.
        // Commit only after the physical S/number key is actually up.
        guard !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode)) else { return }
        shortcutKeyReleased(keyCode)
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
                stackId: window.nearestWindowTabGroup?.allLeafWindowsRecursive.first?.windowId,
            )
        }
}

@MainActor
func workspacePreviewRect(for workspace: Workspace) -> Rect {
    workspace.rootTilingContainer.lastAppliedLayoutPhysicalRect
        ?? workspace.rootTilingContainer.lastAppliedLayoutVirtualRect
        ?? workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
}

func workspacePreviewAspectRatio(for rect: Rect) -> CGFloat {
    guard rect.width > 0, rect.height > 0 else { return 1 }
    return rect.width / rect.height
}

@MainActor
func workspacePreviewWindowItems(
    for workspace: Workspace,
    workspaceRect: Rect,
) -> [WorkspacePreviewWindowItem] {
    var items: [WorkspacePreviewWindowItem] = []
    let resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    appendWorkspacePreviewItems(
        from: workspace.rootTilingContainer,
        workspaceRect: workspaceRect,
        fallbackRect: workspaceRect,
        resolvedGaps: resolvedGaps,
        to: &items,
    )
    for window in workspace.floatingWindows where window.isBound {
        if let item = workspacePreviewItem(
            for: window,
            workspaceRect: workspaceRect,
            fallbackRect: nil,
            prefersActualRect: true,
        ) {
            items.append(item)
        }
    }
    return items
}

@MainActor
private func appendWorkspacePreviewItems(
    from node: TreeNode,
    workspaceRect: Rect,
    fallbackRect: Rect,
    resolvedGaps: ResolvedGaps,
    to items: inout [WorkspacePreviewWindowItem],
) {
    switch node.nodeCases {
        case .window(let window):
            if let item = workspacePreviewItem(
                for: window,
                workspaceRect: workspaceRect,
                fallbackRect: fallbackRect,
                prefersActualRect: false,
            ) {
                items.append(item)
            }
        case .tilingContainer(let container):
            if container.usesWindowTabBehavior {
                if let item = workspacePreviewItem(for: container, workspaceRect: workspaceRect, fallbackRect: fallbackRect) {
                    items.append(item)
                }
            } else {
                switch container.layout {
                    case .tiles:
                        appendWorkspacePreviewTileItems(
                            from: container,
                            workspaceRect: workspaceRect,
                            fallbackRect: fallbackRect,
                            resolvedGaps: resolvedGaps,
                            to: &items,
                        )
                    case .tabGroup:
                        for child in container.children {
                            appendWorkspacePreviewItems(
                                from: child,
                                workspaceRect: workspaceRect,
                                fallbackRect: fallbackRect,
                                resolvedGaps: resolvedGaps,
                                to: &items,
                            )
                        }
                }
            }
        case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return
    }
}

@MainActor
private func appendWorkspacePreviewTileItems(
    from container: TilingContainer,
    workspaceRect: Rect,
    fallbackRect: Rect,
    resolvedGaps: ResolvedGaps,
    to items: inout [WorkspacePreviewWindowItem],
) {
    guard !container.children.isEmpty else { return }
    let orientation = container.orientation
    let totalWeight = CGFloat(container.children.sumOfDouble { $0.getWeight(orientation) })
    let delta = (fallbackRect.getDimension(orientation) - totalWeight) / CGFloat(container.children.count)
    let rawGap = resolvedGaps.inner.get(orientation).toDouble()
    let lastIndex = container.children.indices.last
    var point = fallbackRect.topLeftCorner

    for (index, child) in container.children.enumerated() {
        let childDimension = max(child.getWeight(orientation) + delta, 0)
        let gap = rawGap - (index == 0 ? rawGap / 2 : 0) - (index == lastIndex ? rawGap / 2 : 0)
        let childFallbackRect: Rect
        switch orientation {
            case .h:
                childFallbackRect = Rect(
                    topLeftX: index == 0 ? point.x : point.x + rawGap / 2,
                    topLeftY: fallbackRect.topLeftY,
                    width: max(childDimension - gap, 0),
                    height: fallbackRect.height,
                )
                point = point.addingXOffset(childDimension)
            case .v:
                childFallbackRect = Rect(
                    topLeftX: fallbackRect.topLeftX,
                    topLeftY: index == 0 ? point.y : point.y + rawGap / 2,
                    width: fallbackRect.width,
                    height: max(childDimension - gap, 0),
                )
                point = point.addingYOffset(childDimension)
        }
        appendWorkspacePreviewItems(
            from: child,
            workspaceRect: workspaceRect,
            fallbackRect: childFallbackRect,
            resolvedGaps: resolvedGaps,
            to: &items,
        )
    }
}

@MainActor
private func workspacePreviewItem(
    for container: TilingContainer,
    workspaceRect: Rect,
    fallbackRect: Rect,
) -> WorkspacePreviewWindowItem? {
    guard let representative = container.tabActiveWindow ?? container.mostRecentWindowRecursive ?? container.anyLeafWindowRecursive,
          let layoutFrame = workspacePreviewNormalizedFrame(
            for: container.lastAppliedLayoutPhysicalRect ?? container.lastAppliedLayoutVirtualRect ?? fallbackRect,
            in: workspaceRect
          )
    else { return nil }
    return workspacePreviewItem(for: representative, layoutFrame: layoutFrame)
}

@MainActor
private func workspacePreviewItem(
    for window: Window,
    workspaceRect: Rect,
    fallbackRect: Rect?,
    prefersActualRect: Bool,
) -> WorkspacePreviewWindowItem? {
    let rect = prefersActualRect
        ? (window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect ?? window.lastAppliedLayoutVirtualRect)
        : (window.lastAppliedLayoutPhysicalRect ?? window.lastAppliedLayoutVirtualRect ?? fallbackRect ?? window.lastKnownActualRect)
    guard let layoutFrame = workspacePreviewNormalizedFrame(for: rect, in: workspaceRect) else { return nil }
    return workspacePreviewItem(for: window, layoutFrame: layoutFrame)
}

@MainActor
private func workspacePreviewItem(
    for window: Window,
    layoutFrame: CGRect,
) -> WorkspacePreviewWindowItem {
    WorkspacePreviewWindowItem(
        id: window.windowId,
        title: sidebarDisplayLabel(for: window),
        appName: window.app.name ?? "Unknown",
        appIcon: appIconImage(bundleIdentifier: window.app.rawAppBundleId, bundlePath: window.app.bundlePath),
        thumbnail: cachedExposeThumbnail(window.windowId).map { NSImage(cgImage: $0, size: .zero) },
        layoutFrame: layoutFrame,
    )
}

func workspacePreviewNormalizedFrame(for rect: Rect?, in workspaceRect: Rect) -> CGRect? {
    guard let rect,
          workspaceRect.width > 0,
          workspaceRect.height > 0
    else { return nil }

    let minX = max(rect.minX, workspaceRect.minX)
    let minY = max(rect.minY, workspaceRect.minY)
    let maxX = min(rect.maxX, workspaceRect.maxX)
    let maxY = min(rect.maxY, workspaceRect.maxY)
    guard maxX > minX, maxY > minY else { return nil }

    return CGRect(
        x: (minX - workspaceRect.minX) / workspaceRect.width,
        y: (minY - workspaceRect.minY) / workspaceRect.height,
        width: (maxX - minX) / workspaceRect.width,
        height: (maxY - minY) / workspaceRect.height,
    )
}

func workspacePreviewPlacedWindows(
    windows: [WorkspacePreviewWindowItem],
    workspaceAspectRatio: CGFloat,
    in size: CGSize,
    inset: CGFloat = 0,
    fillsCanvas: Bool = false,
) -> [WorkspacePreviewPlacedWindow] {
    let canvasRect = workspacePreviewCanvasRect(
        workspaceAspectRatio: workspaceAspectRatio,
        in: size,
        inset: inset,
    )
    let bounds = windows.reduce(CGRect.null) { $0.union($1.layoutFrame) }
    return windows.map { window in
        let frame = window.layoutFrame
        let normalized = fillsCanvas && bounds.width > 0 && bounds.height > 0
            ? CGRect(x: (frame.minX - bounds.minX) / bounds.width,
                     y: (frame.minY - bounds.minY) / bounds.height,
                     width: frame.width / bounds.width, height: frame.height / bounds.height)
            : frame
        return WorkspacePreviewPlacedWindow(
            window: window,
            frame: workspacePreviewFrame(for: normalized, in: fillsCanvas ? CGRect(origin: .zero, size: size) : canvasRect),
        )
    }
}

func workspacePreviewCanvasRect(
    workspaceAspectRatio: CGFloat,
    in size: CGSize,
    inset: CGFloat = WinMuxSpacing.regular,
) -> CGRect {
    let available = CGRect(
        x: inset,
        y: inset,
        width: max(size.width - inset * 2, 1),
        height: max(size.height - inset * 2, 1),
    )
    guard workspaceAspectRatio > 0, available.width > 0, available.height > 0 else {
        return available
    }
    let availableAspectRatio = available.width / available.height
    if availableAspectRatio > workspaceAspectRatio {
        let width = available.height * workspaceAspectRatio
        return CGRect(
            x: available.minX + (available.width - width) / 2,
            y: available.minY,
            width: width,
            height: available.height,
        )
    } else {
        let height = available.width / workspaceAspectRatio
        return CGRect(
            x: available.minX,
            y: available.minY + (available.height - height) / 2,
            width: available.width,
            height: height,
        )
    }
}

func workspacePreviewFrame(for normalizedFrame: CGRect, in canvasRect: CGRect) -> CGRect {
    CGRect(
        x: canvasRect.minX + normalizedFrame.minX * canvasRect.width,
        y: canvasRect.minY + normalizedFrame.minY * canvasRect.height,
        width: normalizedFrame.width * canvasRect.width,
        height: normalizedFrame.height * canvasRect.height,
    )
}

// Preserve tree order, keeping each stack separate. Large stacks continue in
// another row after five windows; the panel scrolls beyond three visible rows.
func workspacePreviewStackRows(_ windows: [WorkspacePreviewWindowItem]) -> [[WorkspacePreviewWindowItem]] {
    var groups: [[WorkspacePreviewWindowItem]] = []
    var indices: [UInt32: Int] = [:]
    for window in windows.prefix(workspacePreviewMaximumWindows) {
        let key = window.stackId ?? window.id
        if let index = indices[key] {
            groups[index].append(window)
        } else {
            indices[key] = groups.count
            groups.append([window])
        }
    }
    return groups.flatMap { group in
        stride(from: 0, to: group.count, by: workspacePreviewColumns).map {
            Array(group[$0..<min($0 + workspacePreviewColumns, group.count)])
        }
    }
}

func workspacePreviewWorkspaceSize(aspectRatio: CGFloat) -> CGSize {
    let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
    return ratio >= 1
        ? CGSize(width: workspacePreviewWindowWidth * ratio, height: workspacePreviewWindowWidth)
        : CGSize(width: workspacePreviewWindowWidth, height: workspacePreviewWindowWidth / ratio)
}

func workspacePreviewColumnCount(windowCount: Int, workspaceCount: Int, availableWidth: CGFloat = .infinity, workspaceAspectRatio: CGFloat = 1.6) -> Int {
    let sidebarWidth = workspacePreviewWorkspaceSize(aspectRatio: workspaceAspectRatio).width + WinMuxSpacing.section * 2 + standardGap * 0.125
    let availableGridWidth = availableWidth - workspacePreviewPanelPadding * 2 - sidebarWidth
    let fittingColumns = availableWidth.isFinite ? max(Int((availableGridWidth + workspacePreviewRowSpacing) / (workspacePreviewWindowWidth + workspacePreviewRowSpacing)), 1) : workspacePreviewColumns
    return min(max(windowCount, 1), workspacePreviewColumns, fittingColumns)
}

func workspacePreviewPanelWidth(itemCount: Int, availableWidth: CGFloat, windowCount: Int = workspacePreviewMaximumWindows, workspaceAspectRatio: CGFloat = 1.6) -> CGFloat {
    let maximum = min(workspacePreviewMaximumWidth, availableWidth * 0.92)
    let columns = workspacePreviewColumnCount(windowCount: windowCount, workspaceCount: itemCount, availableWidth: maximum, workspaceAspectRatio: workspaceAspectRatio)
    let contentWidth = workspacePreviewWorkspaceSize(aspectRatio: workspaceAspectRatio).width + workspacePreviewWindowWidth * CGFloat(columns) + workspacePreviewRowSpacing * CGFloat(columns - 1) +
        WinMuxSpacing.section * 2 + standardGap * 0.125 + workspacePreviewPanelPadding * 2
    return min(contentWidth, maximum)
}

func workspacePreviewPanelHeight(maximumWindowCount: Int, availableHeight: CGFloat, workspaceCount: Int = 2, columns: Int = workspacePreviewColumns, stackRowCount: Int? = nil, workspaceAspectRatio: CGFloat = 1.6) -> CGFloat {
    let rows = min(max(stackRowCount ?? ((max(maximumWindowCount, 0) + columns - 1) / columns), 1), workspacePreviewMaximumRows)
    let gridHeight = CGFloat(rows) * workspacePreviewTileHeight + CGFloat(rows - 1) * workspacePreviewRowSpacing
    let visibleWorkspaces = min(max(workspaceCount, 1), 4)
    let workspaceHeight = CGFloat(visibleWorkspaces) * (workspacePreviewWorkspaceSize(aspectRatio: workspaceAspectRatio).height + WinMuxSpacing.comfortable + standardGap * 5) + CGFloat(visibleWorkspaces - 1) * workspacePreviewRowSpacing
    let contentHeight = workspacePreviewPanelPadding * 2 + standardGap * 8 + max(gridHeight, workspaceHeight)
    return min(contentHeight, workspacePreviewMaximumHeight, availableHeight * 0.8)
}

private struct WorkspacePreviewView: View {
    let items: [WorkspacePreviewItem]
    let currentIndex: Int
    let selectedIndex: Int
    let selectedWindowId: UInt32?
    let onSelect: (Int) -> Void
    let onWindowSelect: (UInt32) -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let current = items[currentIndex]
        let workspaceSize = workspacePreviewWorkspaceSize(aspectRatio: current.workspaceAspectRatio)
        let palette = WinMuxOverlayPalette(colorScheme: colorScheme)
        GeometryReader { geometry in
            let rows = workspacePreviewStackRows(current.windows)
            let availableHeight = max(geometry.size.height - workspacePreviewPanelPadding * 2, 1)
            let sidebarWidth = workspaceSize.width + WinMuxSpacing.section * 2 + standardGap * 0.125
            let gridWidth = max(geometry.size.width - workspacePreviewPanelPadding * 2 - sidebarWidth, 1)
            HStack(alignment: .center, spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: workspacePreviewRowSpacing) {
                            ForEach(Array(items.enumerated()).filter { $0.offset != currentIndex }, id: \.element.id) { index, item in
                                WorkspacePreviewLegacyCard(item: item, isSelected: index == selectedIndex && selectedWindowId == nil)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(index) }
                            }
                        }
                        .frame(width: workspaceSize.width)
                        .frame(minHeight: availableHeight, alignment: .center)
                    }
                    .onChange(of: selectedIndex) { index in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) { proxy.scrollTo(index, anchor: .center) }
                    }
                }
                .frame(width: workspaceSize.width, height: availableHeight)
                Rectangle()
                    .fill(palette.workspacePreviewForeground(0.12))
                    .frame(width: standardGap * 0.125)
                    .padding(.horizontal, WinMuxSpacing.section)
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        VStack(spacing: WinMuxSpacing.section) {
                            sectionHeading(current.displayName, palette: palette)
                            VStack(alignment: .center, spacing: workspacePreviewRowSpacing) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                    HStack(alignment: .center, spacing: workspacePreviewRowSpacing) {
                                        ForEach(row) { window in
                                            VStack(spacing: WinMuxSpacing.comfortable) {
                                                WorkspacePreviewWindowTile(window: window)
                                                    .frame(width: workspacePreviewWindowWidth, height: workspacePreviewWindowHeight)
                                                    .overlay {
                                                        if window.id == selectedWindowId {
                                                            RoundedRectangle(cornerRadius: workspacePreviewCornerRadius, style: .continuous)
                                                                .strokeBorder(palette.workspacePreviewFocusRing, lineWidth: workspacePreviewFocusRingWidth)
                                                        }
                                                    }
                                                Text(window.title)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(palette.workspacePreviewForeground(0.98))
                                                    .lineLimit(1)
                                                    .multilineTextAlignment(.center)
                                                    .frame(width: workspacePreviewWindowWidth, height: standardGap * 3.5)
                                            }
                                            .frame(width: workspacePreviewWindowWidth, height: workspacePreviewTileHeight)
                                            .contentShape(Rectangle())
                                            .onTapGesture { onWindowSelect(window.id) }
                                            .help(window.title)
                                            .id(window.id)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(minWidth: gridWidth, minHeight: availableHeight, alignment: .center)
                    }
                    .onChange(of: selectedWindowId) { id in
                        if let id {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
                .frame(width: gridWidth, height: availableHeight)
            }
            .padding(workspacePreviewPanelPadding)
        }
        .background { WorkspacePreviewSwitcherSurface() }
        .clipShape(RoundedRectangle(cornerRadius: standardGap * 8, style: .continuous))
        .onExitCommand(perform: onDismiss)
    }

    private func sectionHeading(_ title: String, palette: WinMuxOverlayPalette) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(palette.workspacePreviewForeground(0.98))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: standardGap * 5)
    }
}

private struct WorkspacePreviewLegacyCard: View {
    let item: WorkspacePreviewItem
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let palette = WinMuxOverlayPalette(colorScheme: colorScheme)
        let size = workspacePreviewWorkspaceSize(aspectRatio: item.workspaceAspectRatio)
        VStack(spacing: WinMuxSpacing.comfortable) {
            Text(item.displayName)
                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(palette.workspacePreviewForeground(isSelected ? 0.98 : 0.76))
                .lineLimit(1)
                .frame(width: size.width, height: standardGap * 5)
            WorkspacePreviewLayoutCanvas(windows: item.legacyWindows, workspaceAspectRatio: item.workspaceAspectRatio)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: workspacePreviewCornerRadius, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: workspacePreviewCornerRadius, style: .continuous)
                            .strokeBorder(palette.workspacePreviewFocusRing, lineWidth: workspacePreviewFocusRingWidth)
                    }
                }

        }
        .frame(width: size.width)
    }
}

private struct WorkspacePreviewSwitcherSurface: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: standardGap * 8, style: .continuous)
        ZStack {
            VisualEffectBlur(
                material: .hudWindow,
                blendingMode: .behindWindow,
                opacity: 0.95
            )
            shape.fill(GeistColorTokens.previewWhite.swiftUIColor.opacity(0.01))
            shape.strokeBorder(GeistColorTokens.previewWhite.swiftUIColor.opacity(0.12), lineWidth: 0.5)
        }
        .compositingGroup()
        .shadow(color: GeistColorTokens.previewBlack.swiftUIColor.opacity(0.20), radius: standardGap * 7.5, x: 0, y: WinMuxSpacing.panel)
        .allowsHitTesting(false)
    }
}

private struct WorkspacePreviewLayoutCanvas: View {
    let windows: [WorkspacePreviewWindowItem]
    let workspaceAspectRatio: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WinMuxOverlayPalette { WinMuxOverlayPalette(colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            let placedWindows = workspacePreviewPlacedWindows(
                windows: windows,
                workspaceAspectRatio: workspaceAspectRatio,
                in: geometry.size,
                inset: 0,
                fillsCanvas: true,
            )

            ZStack(alignment: .topLeading) {
                if windows.isEmpty {
                    Text("Empty")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.workspacePreviewForeground(0.54))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    ForEach(Array(placedWindows.enumerated()), id: \.element.id) { index, placedWindow in
                        WorkspacePreviewWindowTile(window: placedWindow.window)
                            .frame(width: placedWindow.frame.width, height: placedWindow.frame.height)
                            .position(x: placedWindow.frame.midX, y: placedWindow.frame.midY)
                            .zIndex(Double(index))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: workspacePreviewCornerRadius, style: .continuous))
        }
    }

}

struct WorkspacePreviewPlacedWindow: Identifiable {
    let window: WorkspacePreviewWindowItem
    let frame: CGRect

    var id: UInt32 { window.id }
}

private struct WorkspacePreviewWindowTile: View {
    let window: WorkspacePreviewWindowItem
    @State private var refreshedThumbnail: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WinMuxOverlayPalette { WinMuxOverlayPalette(colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: workspacePreviewCornerRadius, style: .continuous)
                    .fill(palette.workspacePreviewTileBackground)
                if let thumbnail = refreshedThumbnail ?? window.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    WorkspacePreviewWindowFallback(window: window)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: workspacePreviewCornerRadius, style: .continuous))
        }
        .shadow(color: palette.workspacePreviewShadow(0.24, lightOpacity: 0.14), radius: standardGap * 1.25, x: 0, y: WinMuxSpacing.hairline)
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
            let hue = workspacePreviewFallbackHue(for: window)
            let tint = palette.workspacePreviewFallbackTint(hue: hue, isBottom: false)

            ZStack {
                LinearGradient(
                    colors: [
                        tint.opacity(0.58),
                        palette.workspacePreviewFallbackTint(hue: hue, isBottom: true).opacity(0.94),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                )

                if let appIcon = window.appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(max(WinMuxSpacing.comfortable, minDimension * 0.24))
                } else {
                    Text(workspacePreviewFallbackInitials(for: window))
                        .font(.system(size: max(12, minDimension * 0.34), weight: .bold, design: .rounded))
                        .foregroundStyle(GeistColorTokens.previewWhite.swiftUIColor.opacity(palette.isDark ? 0.88 : 0.92))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
        }
    }
}

private func workspacePreviewFallbackHue(for window: WorkspacePreviewWindowItem) -> Double {
    let raw = "\(window.appName)-\(window.title)-\(window.id)"
    var seed = UInt64(window.id)
    for scalar in raw.unicodeScalars {
        seed = seed &* 1_664_525 &+ UInt64(scalar.value) &+ 1_013_904_223
    }
    return Double(seed % 360) / 360.0
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

extension WinMuxOverlayPalette {
    func workspacePreviewForeground(_ opacity: Double) -> Color {
        (isDark ? GeistColorTokens.previewWhite.swiftUIColor : GeistColorTokens.previewBlack.swiftUIColor).opacity(opacity)
    }

    func workspacePreviewShadow(_ darkOpacity: Double, lightOpacity: Double? = nil) -> Color {
        GeistColorTokens.previewBlack.swiftUIColor.opacity(isDark ? darkOpacity : (lightOpacity ?? darkOpacity * 0.65))
    }
}
