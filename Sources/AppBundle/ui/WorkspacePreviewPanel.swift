import AppKit
import SwiftUI

private let workspacePreviewPanelId = "WinMux.workspacePreview"

private struct WorkspacePreviewItem: Identifiable {
    let id: String
    let workspace: Workspace
    let displayName: String
    let workspaceAspectRatio: CGFloat
    let windows: [WorkspacePreviewWindowItem]
}

struct WorkspacePreviewWindowItem: Identifiable {
    let id: UInt32
    let title: String
    let appName: String
    let appIcon: NSImage?
    let thumbnail: NSImage?
    let layoutFrame: CGRect
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
            let workspaceRect = workspacePreviewRect(for: workspace)
            return WorkspacePreviewItem(
                id: workspace.name,
                workspace: workspace,
                displayName: workspaceDisplayName(workspace.name),
                workspaceAspectRatio: workspacePreviewAspectRatio(for: workspaceRect),
                windows: workspacePreviewWindowItems(for: workspace, workspaceRect: workspaceRect),
            )
        }
        let currentIndex = items.firstIndex { $0.workspace == current } ?? 0
        selectedIndex = (currentIndex + direction + items.count) % items.count
        isPreviewActive = true
        let frame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        setFrame(frame, display: true, animate: false)
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
        .filter { $0.workspaceMonitor.rect.topLeftCorner == current.workspaceMonitor.rect.topLeftCorner }
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
        case "alt-1":
            WorkspacePreviewPanel.shared.select(index: 0)
            return true
        case "alt-2":
            WorkspacePreviewPanel.shared.select(index: 1)
            return true
        case "alt-3":
            WorkspacePreviewPanel.shared.select(index: 2)
            return true
        default:
            return false
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
) -> [WorkspacePreviewPlacedWindow] {
    let canvasRect = workspacePreviewCanvasRect(
        workspaceAspectRatio: workspaceAspectRatio,
        in: size,
        inset: inset,
    )
    return windows.map { window in
        WorkspacePreviewPlacedWindow(
            window: window,
            frame: workspacePreviewFrame(for: window.layoutFrame, in: canvasRect),
        )
    }
}

func workspacePreviewCanvasRect(
    workspaceAspectRatio: CGFloat,
    in size: CGSize,
    inset: CGFloat = 8,
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
                let contentWidth = CGFloat(items.count) * 300 + CGFloat(max(items.count - 1, 0)) * 14 + 48
                let panelWidth = min(max(contentWidth, 380), geometry.size.width * 0.92)

                ScrollViewReader { proxy in
                    VStack {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    WorkspacePreviewCard(
                                        item: item,
                                        isSelected: index == selectedIndex,
                                    )
                                    .id(index)
                                    .onTapGesture { onSelect(index) }
                                }
                            }
                            .padding(24)
                        }
                        .frame(width: panelWidth)
                        .background { WorkspacePreviewSwitcherSurface() }
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
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
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WinMuxOverlayPalette { WinMuxOverlayPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkspacePreviewLayoutCanvas(windows: item.windows, workspaceAspectRatio: item.workspaceAspectRatio)
                .frame(width: 284, height: 178)
                .padding(8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(palette.isDark ? 0.30 : 0.16))
                    }
                }

            HStack(spacing: 7) {
                Text(item.displayName)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(palette.workspacePreviewForeground(isSelected ? 0.98 : 0.76))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 2)
        }
        .frame(width: 300)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isSelected)
    }
}

private struct WorkspacePreviewSwitcherSurface: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        ZStack {
            WorkspacePreviewNativeMaterial()
                .opacity(0.8)
            shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.20), radius: 30, x: 0, y: 16)
        .allowsHitTesting(false)
    }
}

private struct WorkspacePreviewNativeMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.isDark ? Color(red: 0.08, green: 0.09, blue: 0.10) : Color(red: 0.90, green: 0.91, blue: 0.92))
            if let thumbnail = refreshedThumbnail ?? window.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                WorkspacePreviewWindowFallback(window: window)
            }
        }
        .overlay(alignment: .top) {
            Text(window.appName)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Color.black.opacity(palette.isDark ? 0.82 : 0.58))
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: palette.workspacePreviewShadow(0.24, lightOpacity: 0.14), radius: 5, x: 0, y: 2)
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
            let tint = Color(hue: hue, saturation: 0.42, brightness: 0.50)

            ZStack {
                LinearGradient(
                    colors: [
                        tint.opacity(0.58),
                        Color(hue: hue, saturation: 0.28, brightness: 0.22).opacity(0.94),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                )

                if let appIcon = window.appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(max(6, minDimension * 0.24))
                } else {
                    Text(workspacePreviewFallbackInitials(for: window))
                        .font(.system(size: max(12, minDimension * 0.34), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(palette.isDark ? 0.88 : 0.92))
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

private extension WinMuxOverlayPalette {
    func workspacePreviewForeground(_ opacity: Double) -> Color {
        (isDark ? Color.white : Color.black).opacity(opacity)
    }

    func workspacePreviewContrastingFill(
        darkOpacity: Double,
        lightOpacity: Double? = nil
    ) -> Color {
        workspacePreviewForeground(isDark ? darkOpacity : (lightOpacity ?? darkOpacity))
    }

    func workspacePreviewShadow(_ darkOpacity: Double, lightOpacity: Double? = nil) -> Color {
        Color.black.opacity(isDark ? darkOpacity : (lightOpacity ?? darkOpacity * 0.65))
    }
}
