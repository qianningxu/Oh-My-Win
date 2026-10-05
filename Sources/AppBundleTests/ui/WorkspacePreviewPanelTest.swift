@testable import AppBundle
import XCTest
import AppKit

final class WorkspacePreviewPanelTest: XCTestCase {
    func testPreviewWaitsForOptionReleaseAndCommitsOnlyOnce() {
        var cycle = WorkspacePreviewShortcutCycle()
        cycle.select(modifier: .option)
        XCTAssertFalse(cycle.updateModifiers([.option, .command]))
        XCTAssertFalse(cycle.updateModifiers(.option))
        cycle.select(modifier: .option)
        XCTAssertFalse(cycle.updateModifiers(.option))
        XCTAssertTrue(cycle.updateModifiers([]))
        XCTAssertFalse(cycle.updateModifiers([]))
    }

    func testCancellingPreviewPreventsSwitchOnOptionRelease() {
        var cycle = WorkspacePreviewShortcutCycle()
        cycle.select(modifier: .option)
        cycle.cancel()
        XCTAssertFalse(cycle.updateModifiers([]))
    }

    func testModifierPressOpensBothPreviewKindsSymmetrically() {
        XCTAssertEqual(workspacePreviewKindOnModifierPress(previous: [], current: .option), .tabs)
        XCTAssertEqual(workspacePreviewKindOnModifierPress(previous: [], current: .control), .workspaces)
        for kind in [WorkspacePreviewKind.workspaces, .tabs] {
            XCTAssertEqual(workspacePreviewKindOnModifierPress(previous: [], current: kind.modifier), kind)
            XCTAssertNil(workspacePreviewKindOnModifierPress(previous: kind.modifier, current: kind.modifier))
            XCTAssertNil(workspacePreviewKindOnModifierPress(previous: kind.modifier, current: []))
            var cycle = WorkspacePreviewShortcutCycle()
            cycle.select(modifier: kind.modifier)
            XCTAssertFalse(cycle.updateModifiers(kind.modifier))
            XCTAssertTrue(cycle.updateModifiers([]))
            XCTAssertFalse(cycle.updateModifiers([]))
        }
    }

    func testControlPreviewCommitsOnlyWhenControlIsReleased() {
        var cycle = WorkspacePreviewShortcutCycle()
        cycle.select(modifier: .control)
        XCTAssertFalse(cycle.updateModifiers([.control, .option]))
        XCTAssertFalse(cycle.updateModifiers([.control]))
        XCTAssertTrue(cycle.updateModifiers([]))
        XCTAssertFalse(cycle.updateModifiers([]))
    }

    func testSeparatePreviewSizing() {
        XCTAssertEqual(workspacePreviewModeWidth(kind: .workspaces, workspaceCount: 5, windowCount: 15, availableWidth: 2000, workspaceAspectRatio: 1.6), 1208)
        XCTAssertEqual(workspacePreviewModeHeight(kind: .workspaces, workspaceCount: 5, windowCount: 15, panelWidth: 1208, availableHeight: 2000, workspaceAspectRatio: 1.6), 602)
        XCTAssertEqual(workspacePreviewModeWidth(kind: .tabs, workspaceCount: 5, windowCount: 1, availableWidth: 2000, workspaceAspectRatio: 1.6), 355)
        XCTAssertEqual(workspacePreviewModeHeight(kind: .tabs, workspaceCount: 5, windowCount: 1, panelWidth: 355, availableHeight: 2000, workspaceAspectRatio: 1.6), 365)
    }

    func testOptionTabCyclesWindowsInDisplayedRowOrder() {
        func item(_ id: UInt32, _ stack: UInt32?) -> WorkspacePreviewWindowItem {
            WorkspacePreviewWindowItem(id: id, title: "Window", appName: "App", appIcon: nil, thumbnail: nil, stackId: stack)
        }
        let windows = [item(1, 1), item(2, 2), item(3, 1)]
        XCTAssertEqual(workspacePreviewNextWindowId(windows, selectedWindowId: 1, direction: 1), 2)
        XCTAssertEqual(workspacePreviewNextWindowId(windows, selectedWindowId: 3, direction: 1), 1)
        XCTAssertEqual(workspacePreviewNextWindowId(windows, selectedWindowId: 2, direction: 1), 3)
        XCTAssertEqual(workspacePreviewNextWindowId(windows, selectedWindowId: 1, direction: -1), 3)
        XCTAssertEqual(workspacePreviewNextWindowId(windows, selectedWindowId: nil, direction: 1), 1)
        XCTAssertNil(workspacePreviewNextWindowId([], selectedWindowId: nil, direction: 1))
    }

    @MainActor
    func testOptionPreviewOnlyShowsWorkspacesInFocusedProject() {
        setUpWorkspacesForTests()
        let current = focus.workspace
        _ = TestWindow.new(id: 401, parent: current.rootTilingContainer)
        let sibling = Workspace.get(byName: "preview-sibling")
        sibling.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 402, parent: sibling.rootTilingContainer)

        let otherProject = createWorkspaceProject(displayName: "Other")
        let other = projectWorkspaces(projectId: otherProject.id).first.orDie()
        _ = TestWindow.new(id: 403, parent: other.rootTilingContainer)

        let candidates = workspacePreviewCandidateWorkspaces(current: current)
        XCTAssertTrue(candidates.contains(current))
        XCTAssertTrue(candidates.contains(sibling))
        XCTAssertFalse(candidates.contains(other))
        XCTAssertTrue(candidates.allSatisfy { $0.projectId == current.projectId })
    }

    @MainActor
    func testPreviewIncludesInactiveTabsNestedStacksAndOffscreenFloatingWindows() {
        setUpWorkspacesForTests()
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let stack = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 411, parent: stack)
        _ = TestWindow.new(id: 412, parent: stack)
        let nested = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .h, .tiles, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 413, parent: nested)
        _ = TestWindow.new(id: 414, parent: workspace, rect: Rect(topLeftX: -10000, topLeftY: -10000, width: 400, height: 300))

        XCTAssertEqual(workspacePreviewWindowItems(for: workspace).map(\.id), [411, 412, 413, 414])
    }

    @MainActor
    func testPreviewIncludesEveryWindowWhenWorkspaceRootIsTabbed() {
        setUpWorkspacesForTests()
        let workspace = focus.workspace
        workspace.rootTilingContainer.layout = .tabGroup
        _ = TestWindow.new(id: 421, parent: workspace.rootTilingContainer)
        _ = TestWindow.new(id: 422, parent: workspace.rootTilingContainer)

        XCTAssertEqual(workspacePreviewWindowItems(for: workspace).map(\.id), [421, 422])
    }

    @MainActor
    func testPreviewIncludesOnlyMinimizedWindowsOwnedByThisWorkspace() {
        setUpWorkspacesForTests()
        let workspace = focus.workspace
        let minimized = TestWindow.new(id: 431, parent: workspace.rootTilingContainer)
        minimized.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name)
        minimized.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        let other = TestWindow.new(id: 432, parent: macosMinimizedWindowsContainer)
        other.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: "other-workspace")

        XCTAssertEqual(workspacePreviewWindowItems(for: workspace).map(\.id), [431])
    }

    @MainActor
    func testPreviewWindowNavigationResolvesTargetWithoutSwitchingFocus() {
        setUpWorkspacesForTests()
        let workspace = focus.workspace
        let first = TestWindow.new(id: 441, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 442, parent: workspace.rootTilingContainer)
        _ = first.focusWindow()
        let before = focus.windowOrNil
        let target = LiveFocus(windowOrNil: first, workspace: workspace)
        XCTAssertTrue(workspacePreviewRelativeWindow(target, .wrapAroundTheWorkspace, .paneNext) === second)
        XCTAssertTrue(focus.windowOrNil === before)
        XCTAssertTrue(workspacePreviewRelativeWindow(LiveFocus(windowOrNil: second, workspace: workspace), .wrapAroundTheWorkspace, .paneNext) === first)
        XCTAssertTrue(focus.windowOrNil === before)
    }

    @MainActor
    func testPreviewStackNavigationStaysInsideItsStack() {
        setUpWorkspacesForTests()
        let workspace = focus.workspace
        let stack = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .h, .tabGroup, index: INDEX_BIND_LAST)
        let first = TestWindow.new(id: 451, parent: stack)
        let second = TestWindow.new(id: 452, parent: stack)
        _ = TestWindow.new(id: 453, parent: workspace.rootTilingContainer)
        XCTAssertTrue(workspacePreviewRelativeWindow(LiveFocus(windowOrNil: first, workspace: workspace), .wrapAroundTheWorkspace, .stackNext) === second)
        XCTAssertTrue(workspacePreviewRelativeWindow(LiveFocus(windowOrNil: second, workspace: workspace), .wrapAroundTheWorkspace, .stackNext) === first)
    }

    func testWorkspacePreviewSelectionSupportsEveryNumericShortcut() {
        XCTAssertEqual(workspacePreviewSelectionIndex(for: "ctrl-1"), 0)
        XCTAssertEqual(workspacePreviewSelectionIndex(for: "ctrl-4"), 3)
        XCTAssertEqual(workspacePreviewSelectionIndex(for: "ctrl-9"), 8)
        XCTAssertEqual(workspacePreviewSelectionIndex(for: "ctrl-0"), 9)
        XCTAssertNil(workspacePreviewSelectionIndex(for: "ctrl-shift-4"))
    }

    func testOptionWorkspaceIndexSupportsNumberRowAndKeypad() {
        XCTAssertEqual(optionWorkspaceIndex(for: 21), 3)
        XCTAssertEqual(optionWorkspaceIndex(for: 86), 3)
        XCTAssertEqual(optionWorkspaceIndex(for: 29), 9)
        XCTAssertEqual(optionWorkspaceIndex(for: 82), 9)
    }

    func testPreviewRowsFlowAcrossStacksAndLimitEachRowToFive() {
        func item(_ id: UInt32, _ stack: UInt32?) -> WorkspacePreviewWindowItem {
            WorkspacePreviewWindowItem(id: id, title: "Window", appName: "App", appIcon: nil, thumbnail: nil, stackId: stack)
        }
        let windows = [item(1, 1), item(2, 2), item(3, 1), item(4, nil)]
        XCTAssertEqual(workspacePreviewWindowRows(windows).map { $0.map(\.id) }, [[1, 2, 3, 4]])
        let windowsAcrossStacks = (1...20).map { item(UInt32($0), UInt32($0 % 3)) }
        XCTAssertEqual(workspacePreviewWindowRows(windowsAcrossStacks).map(\.count), [5, 5, 5, 5])
    }

    func testBalancedRowsPreserveEveryItemAndRespectLimits() {
        for limit in [4, 5] {
            for count in 0...100 {
                let items = Array(0..<count)
                let rows = workspacePreviewBalancedRows(items, maximumColumns: limit)
                XCTAssertEqual(rows.flatMap { $0 }, items)
                XCTAssertTrue(rows.allSatisfy { $0.count <= limit })
                let sizes = rows.map(\.count)
                XCTAssertLessThanOrEqual((sizes.max() ?? 0) - (sizes.min() ?? 0), 1)
            }
        }
        XCTAssertEqual(workspacePreviewBalancedRows(Array(0..<6), maximumColumns: 5).map(\.count), [3, 3])
        XCTAssertEqual(workspacePreviewBalancedRows(Array(0..<9), maximumColumns: 4).map(\.count), [3, 3, 3])
    }

    func testWorkspaceArtworkFillsAssignedCanvasBounds() {
        let window = WorkspacePreviewWindowItem(id: 1, title: "Window", appName: "App", appIcon: nil, thumbnail: nil,
                                               layoutFrame: CGRect(x: 0.02, y: 0.04, width: 0.96, height: 0.92))
        let size = CGSize(width: workspacePreviewWindowWidth, height: workspacePreviewWindowHeight)
        let placed = workspacePreviewPlacedWindows(windows: [window], workspaceAspectRatio: 2.5,
                                                   in: size, fillsCanvas: true)
        XCTAssertEqual(placed[0].frame, CGRect(origin: .zero, size: size))
    }

    func testWorkspaceScreenRatioAndSquareWindowsShareScale() {
        XCTAssertEqual(workspacePreviewWindowWidth, workspacePreviewWindowHeight)
        XCTAssertEqual(workspacePreviewWindowWidth, 275)
        XCTAssertEqual(workspacePreviewWorkspaceSize(aspectRatio: 1.6), CGSize(width: 352, height: 220))
        XCTAssertEqual(workspacePreviewWorkspaceSize(aspectRatio: 0.625), CGSize(width: 220, height: 352))
        XCTAssertEqual(workspacePreviewWorkspaceSize(aspectRatio: 0), CGSize(width: 220, height: 220))
    }

    func testPreviewWidthFitsWindowRowsAndOptionalWorkspaceRow() {
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 1, availableWidth: 2000, windowCount: 1), 355)
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 1, availableWidth: 2000, windowCount: 5), 1599)
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 2, availableWidth: 2000, windowCount: 1), 820)
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 6, availableWidth: 2000, windowCount: 3), 1208)
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 6, availableWidth: 2000, windowCount: 15), 1599)
        XCTAssertEqual(workspacePreviewColumnCount(windowCount: 15, workspaceCount: 6, availableWidth: 1220.5), 3)
        XCTAssertEqual(workspacePreviewWorkspaceColumnCount(itemCount: 5, availableWidth: 1596), 3)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 1, availableHeight: 2000, workspaceCount: 5), 961.5)
        XCTAssertLessThanOrEqual(workspacePreviewPanelWidth(itemCount: 100, availableWidth: 600), 552)
    }

    func testPreviewHeightFitsWindowRowsAndOptionalWorkspaceRow() {
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 1, availableHeight: 2000, workspaceCount: 0), 365)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 1, availableHeight: 2000, workspaceCount: 2), 669.5)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 15, availableHeight: 2000, workspaceCount: 2), 1000)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 15, availableHeight: 2000, workspaceCount: 6), 1000)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 100, availableHeight: 600, workspaceCount: 100), 480)
        XCTAssertEqual(workspacePreviewCornerRadius, 7)
    }
}
