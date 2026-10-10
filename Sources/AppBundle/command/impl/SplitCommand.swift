import AppKit
import Common

struct SplitCommand: Command {
    let args: SplitCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        if let leftFraction = args.arg.val.leftFraction {
            guard let target = args.resolveTargetOrReportError(env, io) else { return false }
            guard let window = target.windowOrNil else { return true }
            guard let root = twoPaneHorizontalSplit(for: window) else {
                if let direction = args.singlePaneDirection {
                    splitFocusedTabFromSinglePane(window, direction: direction)
                }
                return true
            }
            let total = root.children.reduce(CGFloat.zero) { $0 + $1.getWeight(.h) }
            root.children[0].setWeight(.h, total * leftFraction)
            root.children[1].setWeight(.h, total * (1 - leftFraction))
            return true
        }
        if config.enableNormalizationFlattenContainers {
            return io.err("'split' has no effect when 'enable-normalization-flatten-containers' normalization enabled. My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.")
        }
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        guard let parent = window.parent else { return false }
        switch parent.cases {
            case .workspace:
                // Nothing to do for floating and macOS native fullscreen windows
                return io.err("Can't split floating windows")
            case .tilingContainer(let parent):
                let orientation: Orientation = switch args.arg.val {
                    case .vertical: .v
                    case .horizontal: .h
                    case .opposite: parent.orientation.opposite
                    case .oneToTwo, .oneToOne, .twoToOne: .h // Ratios are handled above.
                }
                if parent.children.count == 1 {
                    parent.changeOrientation(orientation)
                } else {
                    let data = window.unbindFromParent()
                    let newParent = TilingContainer(
                        parent: parent,
                        adaptiveWeight: data.adaptiveWeight,
                        orientation,
                        .tiles,
                        index: data.index,
                    )
                    window.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
                }
                return true
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
                return io.err("Can't split macos fullscreen, minimized windows and windows of hidden apps. This behavior may change in the future")
            case .macosPopupWindowsContainer:
                return false // Impossible
        }
    }
}

// A stacked window counts as one pane; a nested tile split contains extra panes.
@MainActor
func twoPaneHorizontalSplit(for window: Window) -> TilingContainer? {
    guard let root = window.nodeWorkspace?.rootTilingContainer,
          root.layout == .tiles, root.orientation == .h, root.children.count == 2,
          window.parentsWithSelf.contains(where: { $0 === root }),
          root.children.allSatisfy({ child in
              child is Window || (child as? TilingContainer)?.layout == .tabGroup
          })
    else { return nil }
    return root
}

@MainActor
func splitFocusedTabFromSinglePane(_ window: Window, direction: CardinalDirection) {
    guard let workspace = window.nodeWorkspace else { return }
    let oldRoot = workspace.rootTilingContainer
    var pane = oldRoot
    while pane.layout == .tiles, pane.children.count == 1,
          let child = pane.children.first as? TilingContainer {
        pane = child
    }
    guard pane.layout == .tabGroup, pane.children.count > 1,
          pane.children.allSatisfy({ $0 is Window }), window.parent === pane
    else { return }

    window.unbindFromParent()
    oldRoot.unbindFromParent()
    let newRoot = TilingContainer(parent: workspace, adaptiveWeight: WEIGHT_AUTO, .h, .tiles, index: 0)
    let remaining: TreeNode = pane.children.count == 1 ? pane.children[0] : pane
    remaining.bind(to: newRoot, adaptiveWeight: 1, index: 0)
    window.bind(to: newRoot, adaptiveWeight: 1, index: direction == .left ? 0 : INDEX_BIND_LAST)
    window.markAsMostRecentChild()
    _ = window.focusWindow()
}
