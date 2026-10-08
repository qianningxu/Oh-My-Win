import AppKit
import SwiftUI
import Common

private let workspacePreviewPanelId = "WinMux.workspacePreview"
let workspacePreviewWindowHeight = standardGap * 75
let workspacePreviewWindowWidth = workspacePreviewWindowHeight
let workspacePreviewColumns = 5
private let workspacePreviewCaptionSpacing = workspacePreviewFocusRingWidth + standardGap
private let workspacePreviewTileHeight = workspacePreviewWindowHeight + workspacePreviewCaptionSpacing + standardGap * 5
private let workspacePreviewStackSeparatorHeight = workspacePreviewFocusRingWidth + standardGap * 9 + standardGap * 0.125
private let workspacePreviewColumnSpacing = workspacePreviewFocusRingWidth * 2 + standardGap * 3
private let workspacePreviewRingInset = workspacePreviewFocusRingWidth + standardGap
private let workspacePreviewPanelPadding = WinMuxSpacing.page
let workspacePreviewMaximumWidth = standardGap * 440
let workspacePreviewCornerRadius = standardGap * 1.75
let workspacePreviewFocusRingWidth = standardGap * 3
let workspacePreviewMaximumHeight = standardGap * 250

enum WorkspacePreviewKind {
    case workspaces
    case tabs

    var modifier: NSEvent.ModifierFlags { self == .workspaces ? .control : .option }
}

func workspacePreviewKindOnModifierPress(previous: NSEvent.ModifierFlags, current: NSEvent.ModifierFlags) -> WorkspacePreviewKind? {
    for kind in [WorkspacePreviewKind.workspaces, .tabs] {
        if current.contains(kind.modifier) && !previous.contains(kind.modifier) { return kind }
    }
    return nil
}

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
    var aspectRatio: CGFloat = 1
}

struct WorkspacePreviewShortcutCycle {
    private(set) var pendingModifier: NSEvent.ModifierFlags?

    mutating func select(modifier: NSEvent.ModifierFlags) { pendingModifier = modifier }
    mutating func cancel() { pendingModifier = nil }

    mutating func updateModifiers(_ flags: NSEvent.ModifierFlags) -> Bool {
        guard let modifier = pendingModifier, !flags.contains(modifier) else { return false }
        pendingModifier = nil
        return true
    }
}

@MainActor
final class WorkspacePreviewPanel: NSPanelHud {
    static let shared = WorkspacePreviewPanel()

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var items: [WorkspacePreviewItem] = []
    private var currentIndex: Int = 0
    private var selectedIndex: Int = 0
    private var selectedWindowId: UInt32?
    private var shortcutCycle = WorkspacePreviewShortcutCycle()
    private var pendingCommands: [any Command]?
    private var pressedModifiers: NSEvent.ModifierFlags = []
    private var previewModifier: NSEvent.ModifierFlags = .control
    private var previewKind: WorkspacePreviewKind = .workspaces
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

    func present(kind: WorkspacePreviewKind = .workspaces, modifier: NSEvent.ModifierFlags = .control) {
        if isPreviewActive && previewKind == kind && previewModifier == modifier { return }
        dismiss()
        begin(direction: 0, kind: kind, modifier: modifier)
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
        shortcutCycle.cancel()
        pendingCommands = nil
        if !pressedModifiers.contains(previewModifier) { dismiss() }
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
        if pressedModifiers.contains(previewModifier) && isPreviewActive { begin(direction: 0, kind: previewKind, modifier: previewModifier) }
    }

    func dismiss() {
        guard isPreviewActive else { return }
        isPreviewActive = false
        items = []
        selectedIndex = 0
        selectedWindowId = nil
        shortcutCycle.cancel()
        pendingCommands = nil
        orderOut(nil)
        hostingView.rootView = AnyView(EmptyView())
    }

    private func begin(direction: Int, kind: WorkspacePreviewKind = .workspaces, modifier: NSEvent.ModifierFlags = .control) {
        previewKind = kind
        previewModifier = modifier
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
        selectedWindowId = kind == .tabs && direction == 0 ? focus.windowOrNil?.windowId : nil
        isPreviewActive = true
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let windows = items[currentIndex].windows
        let aspectRatio = items[currentIndex].workspaceAspectRatio
        let width = workspacePreviewModeWidth(kind: kind, workspaceCount: items.count, windowCount: windows.count, availableWidth: screenFrame.width, workspaceAspectRatio: aspectRatio, windows: windows)
        let height = workspacePreviewModeHeight(kind: kind, workspaceCount: items.count, windowCount: windows.count, panelWidth: width, availableHeight: screenFrame.height, workspaceAspectRatio: aspectRatio, windows: windows)
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
                kind: previewKind,
                currentIndex: currentIndex,
                selectedIndex: selectedIndex,
                selectedWindowId: selectedWindowId,
                onSelect: { [weak self] index in
                    self?.selectedWindowId = nil
                    self?.selectedIndex = index
                    self?.commitIfActive()
                },
                onWindowSelect: { [weak self] id in
                    guard let self else { return }
                    selectedWindowId = id
                    selectedIndex = currentIndex
                    commitIfActive()
                },
                onDismiss: { [weak self] in self?.dismiss() },
            )
        )
    }

    // Shortcut keys only select; releasing the held modifier commits once.
    func previewShortcut(commands: [any Command], modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        if modifiers.intersection([.option, .command, .control]) == WorkspacePreviewKind.tabs.modifier,
           let index = optionWorkspaceIndex(for: keyCode) {
            present(kind: .tabs, modifier: WorkspacePreviewKind.tabs.modifier)
            guard isPreviewActive else { return true }
            pendingCommands = nil
            if let window = items[currentIndex].windows.getOrNil(atIndex: index) {
                selectedWindowId = window.id
                selectedIndex = currentIndex
            }
            shortcutCycle.select(modifier: WorkspacePreviewKind.tabs.modifier)
            render()
            return true
        }
        let tabModifier = modifiers.intersection([.option, .command, .control])
        if keyCode == 48, tabModifier == .option || tabModifier == .control {
            let direction = modifiers.contains(.shift) ? -1 : 1
            if tabModifier == WorkspacePreviewKind.workspaces.modifier {
                present(kind: .workspaces)
                guard isPreviewActive else { return true }
                advance(direction: direction)
            } else {
                present(kind: .tabs, modifier: WorkspacePreviewKind.tabs.modifier)
                guard isPreviewActive else { return true }
                selectedWindowId = workspacePreviewNextWindowId(items[currentIndex].windows, selectedWindowId: selectedWindowId, direction: direction)
                selectedIndex = currentIndex
                render()
            }
            pendingCommands = nil
            shortcutCycle.select(modifier: tabModifier)
            return true
        }
        guard commands.count == 1, modifiers.contains(WorkspacePreviewKind.workspaces.modifier) else { return false }
        let commitModifier = WorkspacePreviewKind.workspaces.modifier
        pendingCommands = nil
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
                shortcutCycle.select(modifier: commitModifier)
                return true
            }
            selectedWindowId = nil
            selectedIndex = index
            shortcutCycle.select(modifier: commitModifier)
            render()
            return true
        }
        return false
    }

    private func commitShortcutSelection() {
        if let commands = pendingCommands {
            dismiss()
            Task { @MainActor in
                guard let token: RunSessionGuard = .isServerEnabled else { return }
                try await runLightSession(.hotkeyBinding, token, shouldSchedulePostRefresh: !commands.canSkipPostCommandRefresh) {
                    _ = try await commands.runCmdSeq(.defaultEnv, .emptyStdin)
                }
            }
            return
        }
        commitIfActive()
    }

    func modifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let previous = pressedModifiers
        pressedModifiers = flags
        if shortcutCycle.updateModifiers(flags) {
            commitShortcutSelection()
        } else if let kind = workspacePreviewKindOnModifierPress(previous: previous, current: flags) {
            present(kind: kind, modifier: kind.modifier)
        } else if !flags.contains(previewModifier) && shortcutCycle.pendingModifier == nil {
            dismiss()
        }
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
    guard binding.hasPrefix("ctrl-"),
          let number = Int(binding.dropFirst("ctrl-".count)),
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
                aspectRatio: workspacePreviewAspectRatio(for: window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect ?? window.lastAppliedLayoutVirtualRect ?? Rect(topLeftX: 0, topLeftY: 0, width: 1, height: 1)),
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

// Preserve order and distribute every item evenly across the required rows.
func workspacePreviewBalancedRows<Item>(_ items: [Item], maximumColumns: Int) -> [[Item]] {
    guard !items.isEmpty else { return [] }
    let columns = max(maximumColumns, 1)
    let rowCount = (items.count + columns - 1) / columns
    let baseCount = items.count / rowCount
    let remainder = items.count % rowCount
    var offset = 0
    return (0..<rowCount).map { row in
        let count = baseCount + (row < remainder ? 1 : 0)
        defer { offset += count }
        return Array(items[offset..<offset + count])
    }
}

func workspacePreviewBalancedColumnCount(itemCount: Int, maximumColumns: Int) -> Int {
    let count = max(itemCount, 1)
    let rows = (count + maximumColumns - 1) / maximumColumns
    return (count + rows - 1) / rows
}

func workspacePreviewWindowRows(_ windows: [WorkspacePreviewWindowItem]) -> [[WorkspacePreviewWindowItem]] {
    workspacePreviewBalancedRows(windows, maximumColumns: workspacePreviewColumns)
}

func workspacePreviewWindowSize(_ window: WorkspacePreviewWindowItem) -> CGSize {
    let ratio = window.aspectRatio.isFinite && window.aspectRatio > 0 ? window.aspectRatio : 1
    return CGSize(width: workspacePreviewWindowHeight * ratio, height: workspacePreviewWindowHeight)
}

func workspacePreviewWindowRows(_ windows: [WorkspacePreviewWindowItem], availableWidth: CGFloat) -> [[WorkspacePreviewWindowItem]] {
    let contentWidth = max(availableWidth - workspacePreviewPanelPadding * 2 - workspacePreviewRingInset * 2, 1)
    var rows: [[WorkspacePreviewWindowItem]] = []
    var row: [WorkspacePreviewWindowItem] = []
    var rowWidth: CGFloat = 0
    for window in windows {
        let width = workspacePreviewWindowSize(window).width
        let spacing = row.isEmpty ? 0 : workspacePreviewColumnSpacing
        if !row.isEmpty && (row.count == workspacePreviewColumns || rowWidth + spacing + width > contentWidth) {
            rows.append(row)
            row = []
            rowWidth = 0
        }
        rowWidth += (row.isEmpty ? 0 : workspacePreviewColumnSpacing) + width
        row.append(window)
    }
    if !row.isEmpty { rows.append(row) }
    return rows
}

private func workspacePreviewWindowRowWidth(_ row: [WorkspacePreviewWindowItem]) -> CGFloat {
    row.reduce(0) { $0 + workspacePreviewWindowSize($1).width } + CGFloat(max(row.count - 1, 0)) * workspacePreviewColumnSpacing
}

func workspacePreviewNextWindowId(_ windows: [WorkspacePreviewWindowItem], selectedWindowId: UInt32?, direction: Int) -> UInt32? {
    let ordered = workspacePreviewWindowRows(windows).flatMap { $0 }
    guard !ordered.isEmpty else { return nil }
    guard let index = ordered.firstIndex(where: { $0.id == selectedWindowId }) else {
        return direction < 0 ? ordered.last?.id : ordered.first?.id
    }
    return ordered[(index + direction + ordered.count) % ordered.count].id
}

func workspacePreviewWorkspaceSize(aspectRatio: CGFloat) -> CGSize {
    let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
    return CGSize(width: workspacePreviewWindowHeight * ratio, height: workspacePreviewWindowHeight)
}

func workspacePreviewColumnCount(windowCount: Int, workspaceCount: Int, availableWidth: CGFloat = .infinity, workspaceAspectRatio: CGFloat = 1.6) -> Int {
    let availableGridWidth = availableWidth - workspacePreviewPanelPadding * 2 - workspacePreviewRingInset * 2
    let fittingColumns = availableWidth.isFinite ? max(Int((availableGridWidth + workspacePreviewColumnSpacing) / (workspacePreviewWindowWidth + workspacePreviewColumnSpacing)), 1) : workspacePreviewColumns
    return workspacePreviewBalancedColumnCount(itemCount: windowCount, maximumColumns: min(workspacePreviewColumns, fittingColumns))
}

func workspacePreviewWorkspaceColumnCount(itemCount: Int, availableWidth: CGFloat, workspaceAspectRatio: CGFloat = 1.6) -> Int {
    let tileWidth = workspacePreviewWorkspaceSize(aspectRatio: workspaceAspectRatio).width
    let contentWidth = availableWidth - workspacePreviewPanelPadding * 2 - workspacePreviewRingInset * 2
    let fittingColumns = max(Int((contentWidth + workspacePreviewColumnSpacing) / (tileWidth + workspacePreviewColumnSpacing)), 1)
    return workspacePreviewBalancedColumnCount(itemCount: itemCount, maximumColumns: min(4, fittingColumns))
}

func workspacePreviewPanelWidth(itemCount: Int, availableWidth: CGFloat, windowCount: Int = workspacePreviewColumns, workspaceAspectRatio: CGFloat = 1.6) -> CGFloat {
    let maximum = min(workspacePreviewMaximumWidth, availableWidth * 0.92)
    let columns = workspacePreviewColumnCount(windowCount: windowCount, workspaceCount: itemCount, availableWidth: maximum, workspaceAspectRatio: workspaceAspectRatio)
    let windowWidth = workspacePreviewWindowWidth * CGFloat(columns) + workspacePreviewColumnSpacing * CGFloat(columns - 1)
    let workspaceColumns = workspacePreviewWorkspaceColumnCount(itemCount: itemCount, availableWidth: maximum, workspaceAspectRatio: workspaceAspectRatio)
    let workspaceWidth = itemCount > 1
        ? workspacePreviewWorkspaceSize(aspectRatio: workspaceAspectRatio).width * CGFloat(workspaceColumns) + workspacePreviewColumnSpacing * CGFloat(workspaceColumns - 1)
        : 0
    let contentWidth = max(windowWidth, workspaceWidth) + workspacePreviewPanelPadding * 2 + workspacePreviewRingInset * 2
    return min(contentWidth, maximum)
}

func workspacePreviewPanelHeight(maximumWindowCount: Int, availableHeight: CGFloat, workspaceCount: Int = 2, columns: Int = workspacePreviewColumns, stackRowCount: Int? = nil, workspaceColumns: Int = 4, workspaceAspectRatio: CGFloat = 1.6) -> CGFloat {
    let rows = max(stackRowCount ?? ((max(maximumWindowCount, 0) + columns - 1) / columns), 1)
    let gridHeight = CGFloat(rows) * workspacePreviewTileHeight + CGFloat(rows - 1) * workspacePreviewStackSeparatorHeight
    let workspaceRows = workspaceCount > 1 ? (workspaceCount + workspaceColumns - 1) / workspaceColumns : 0
    let workspaceTileHeight = workspacePreviewWorkspaceSize(aspectRatio: workspaceAspectRatio).height + workspacePreviewCaptionSpacing + standardGap * 5
    let workspaceHeight = workspaceRows > 0
        ? CGFloat(workspaceRows) * workspaceTileHeight + CGFloat(workspaceRows - 1) * workspacePreviewColumnSpacing + workspacePreviewStackSeparatorHeight
        : 0
    let contentHeight = workspacePreviewPanelPadding * 1.25 + gridHeight + workspacePreviewRingInset * 1.5 + workspaceHeight
    return min(contentHeight, workspacePreviewMaximumHeight, availableHeight * 0.8)
}

func workspacePreviewModeWidth(kind: WorkspacePreviewKind, workspaceCount: Int, windowCount: Int, availableWidth: CGFloat, workspaceAspectRatio: CGFloat, windows: [WorkspacePreviewWindowItem]? = nil) -> CGFloat {
    if kind == .tabs {
        if let windows, !windows.isEmpty {
            let maximum = min(workspacePreviewMaximumWidth, availableWidth * 0.92)
            let rows = workspacePreviewWindowRows(windows, availableWidth: maximum)
            let width = rows.map(workspacePreviewWindowRowWidth).max() ?? workspacePreviewWindowWidth
            return min(width + workspacePreviewPanelPadding * 2 + workspacePreviewRingInset * 2, maximum)
        }
        return workspacePreviewPanelWidth(itemCount: 1, availableWidth: availableWidth, windowCount: windowCount)
    }
    let maximum = min(workspacePreviewMaximumWidth, availableWidth * 0.92)
    let columns = workspacePreviewWorkspaceColumnCount(itemCount: workspaceCount, availableWidth: maximum, workspaceAspectRatio: workspaceAspectRatio)
    let width = workspacePreviewWorkspaceSize(aspectRatio: workspaceAspectRatio).width * CGFloat(columns) + workspacePreviewColumnSpacing * CGFloat(columns - 1)
    return min(width + workspacePreviewPanelPadding * 2 + workspacePreviewRingInset * 2, maximum)
}

func workspacePreviewModeHeight(kind: WorkspacePreviewKind, workspaceCount: Int, windowCount: Int, panelWidth: CGFloat, availableHeight: CGFloat, workspaceAspectRatio: CGFloat, windows: [WorkspacePreviewWindowItem]? = nil) -> CGFloat {
    if kind == .tabs {
        if let windows {
            let rows = workspacePreviewWindowRows(windows, availableWidth: panelWidth)
            return workspacePreviewPanelHeight(maximumWindowCount: windowCount, availableHeight: availableHeight, workspaceCount: 0, stackRowCount: max(rows.count, 1))
        }
        let columns = workspacePreviewColumnCount(windowCount: windowCount, workspaceCount: 1, availableWidth: panelWidth)
        return workspacePreviewPanelHeight(maximumWindowCount: windowCount, availableHeight: availableHeight, workspaceCount: 0, columns: columns)
    }
    let columns = workspacePreviewWorkspaceColumnCount(itemCount: workspaceCount, availableWidth: panelWidth, workspaceAspectRatio: workspaceAspectRatio)
    let rows = max((workspaceCount + columns - 1) / columns, 1)
    let tileHeight = workspacePreviewWorkspaceSize(aspectRatio: workspaceAspectRatio).height + workspacePreviewCaptionSpacing + standardGap * 5
    let height = workspacePreviewPanelPadding * 1.25 + CGFloat(rows) * tileHeight + CGFloat(rows - 1) * workspacePreviewColumnSpacing + workspacePreviewRingInset * 1.5
    return min(height, workspacePreviewMaximumHeight, availableHeight * 0.8)
}

private struct WorkspacePreviewView: View {
    let items: [WorkspacePreviewItem]
    var kind: WorkspacePreviewKind = .workspaces
    let currentIndex: Int
    let selectedIndex: Int
    let selectedWindowId: UInt32?
    let onSelect: (Int) -> Void
    let onWindowSelect: (UInt32) -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let current = items[currentIndex]
        let palette = WinMuxOverlayPalette(colorScheme: colorScheme)
        GeometryReader { geometry in
            let gridWidth = max(geometry.size.width - workspacePreviewPanelPadding * 2, 1)
            let rows = workspacePreviewWindowRows(current.windows, availableWidth: geometry.size.width)
            let workspaceColumns = workspacePreviewWorkspaceColumnCount(itemCount: items.count, availableWidth: geometry.size.width, workspaceAspectRatio: current.workspaceAspectRatio)
            let workspaceRows = workspacePreviewBalancedRows(Array(items.indices), maximumColumns: workspaceColumns)
            ScrollViewReader { proxy in
                ScrollView(kind == .tabs ? [.horizontal, .vertical] : .vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if kind == .workspaces {
                            VStack(spacing: workspacePreviewColumnSpacing) {
                                ForEach(Array(workspaceRows.enumerated()), id: \.offset) { _, row in
                                    HStack(spacing: workspacePreviewColumnSpacing) {
                                        ForEach(row, id: \.self) { index in
                                            WorkspacePreviewLegacyCard(item: items[index], isSelected: index == selectedIndex)
                                                .id("workspace-\(index)")
                                                .contentShape(Rectangle())
                                                .onTapGesture { onSelect(index) }
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding([.top, .horizontal], workspacePreviewRingInset)
                            .padding(.bottom, workspacePreviewRingInset / 2)
                        }
                        if kind == .tabs {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                if index > 0 {
                                    Spacer(minLength: 0)
                                        .frame(height: standardGap * 4.125)
                                }
                                HStack(alignment: .center, spacing: workspacePreviewColumnSpacing) {
                                    ForEach(row) { window in
                                        VStack(spacing: workspacePreviewCaptionSpacing) {
                                            WorkspacePreviewWindowTile(window: window)
                                                .frame(width: workspacePreviewWindowSize(window).width, height: workspacePreviewWindowHeight)
                                                .overlay {
                                                    if window.id == selectedWindowId {
                                                        RoundedRectangle(cornerRadius: workspacePreviewCornerRadius + workspacePreviewFocusRingWidth, style: .continuous)
                                                            .strokeBorder(palette.workspacePreviewFocusRing, lineWidth: workspacePreviewFocusRingWidth)
                                                            .padding(-workspacePreviewFocusRingWidth)
                                                    }
                                                }
                                            Text(window.title)
                                                .font(.system(size: 16, weight: window.id == selectedWindowId ? .semibold : .medium))
                                                .foregroundStyle(palette.workspacePreviewForeground(0.98))
                                                .lineLimit(1)
                                                .multilineTextAlignment(.center)
                                                .frame(width: workspacePreviewWindowSize(window).width, height: standardGap * 5)
                                        }
                                        .frame(width: workspacePreviewWindowSize(window).width, height: workspacePreviewTileHeight)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onWindowSelect(window.id) }
                                        .help(window.title)
                                        .id(window.id)
                                    }
                                }
                                .padding([.top, .horizontal], workspacePreviewRingInset)
                                .padding(.bottom, index == rows.count - 1 ? workspacePreviewRingInset / 2 : workspacePreviewRingInset)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(width: kind == .tabs ? max(gridWidth, (rows.map(workspacePreviewWindowRowWidth).max() ?? 0) + workspacePreviewRingInset * 2) : gridWidth)
                }
                .onChange(of: selectedIndex) { index in
                    if selectedWindowId == nil {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) { proxy.scrollTo("workspace-\(index)", anchor: .center) }
                    }
                }
                .onChange(of: selectedWindowId) { id in
                    if let id {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            .padding([.top, .horizontal], workspacePreviewPanelPadding)
            .padding(.bottom, workspacePreviewPanelPadding / 4)
        }
        .background { WorkspacePreviewSwitcherSurface() }
        .clipShape(RoundedRectangle(cornerRadius: standardGap * 8, style: .continuous))
        .onExitCommand(perform: onDismiss)
    }
}

private struct WorkspacePreviewLegacyCard: View {
    let item: WorkspacePreviewItem
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let palette = WinMuxOverlayPalette(colorScheme: colorScheme)
        let size = workspacePreviewWorkspaceSize(aspectRatio: item.workspaceAspectRatio)
        VStack(spacing: workspacePreviewCaptionSpacing) {
            WorkspacePreviewLayoutCanvas(windows: item.legacyWindows, workspaceAspectRatio: item.workspaceAspectRatio)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: workspacePreviewCornerRadius, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: workspacePreviewCornerRadius + workspacePreviewFocusRingWidth, style: .continuous)
                            .strokeBorder(palette.workspacePreviewFocusRing, lineWidth: workspacePreviewFocusRingWidth)
                            .padding(-workspacePreviewFocusRingWidth)
                    }
                }
            Text(item.displayName)
                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(palette.workspacePreviewForeground(isSelected ? 0.98 : 0.76))
                .lineLimit(1)
                .frame(width: size.width, height: standardGap * 5)
        }
        .frame(width: size.width)
    }
}

private struct WorkspacePreviewSwitcherSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: standardGap * 8, style: .continuous)
        ZStack {
            VisualEffectBlur(
                material: .hudWindow,
                blendingMode: .behindWindow,
                opacity: 0.95
            )
            if colorScheme == .light {
                shape.fill(GeistColorTokens.previewBlack.swiftUIColor.opacity(0.05))
            }
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
