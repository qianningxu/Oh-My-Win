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

    func testOptionTabCyclesWindowsInDisplayedStackOrder() {
        func item(_ id: UInt32, _ stack: UInt32?) -> WorkspacePreviewWindowItem {
            WorkspacePreviewWindowItem(id: id, title: "Window", appName: "App", appIcon: nil, thumbnail: nil, stackId: stack)
        }
        let windows = [item(1, 1), item(2, 2), item(3, 1)]
        XCTAssertEqual(workspacePreviewNextWindowId(windows, selectedWindowId: 1, direction: 1), 3)
        XCTAssertEqual(workspacePreviewNextWindowId(windows, selectedWindowId: 3, direction: 1), 2)
        XCTAssertEqual(workspacePreviewNextWindowId(windows, selectedWindowId: 2, direction: 1), 1)
        XCTAssertEqual(workspacePreviewNextWindowId(windows, selectedWindowId: 1, direction: -1), 2)
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
        XCTAssertEqual(workspacePreviewSelectionIndex(for: "alt-1"), 0)
        XCTAssertEqual(workspacePreviewSelectionIndex(for: "alt-4"), 3)
        XCTAssertEqual(workspacePreviewSelectionIndex(for: "alt-9"), 8)
        XCTAssertEqual(workspacePreviewSelectionIndex(for: "alt-0"), 9)
        XCTAssertNil(workspacePreviewSelectionIndex(for: "alt-shift-4"))
    }

    func testOptionWorkspaceIndexSupportsNumberRowAndKeypad() {
        XCTAssertEqual(optionWorkspaceIndex(for: 21), 3)
        XCTAssertEqual(optionWorkspaceIndex(for: 86), 3)
        XCTAssertEqual(optionWorkspaceIndex(for: 29), 9)
        XCTAssertEqual(optionWorkspaceIndex(for: 82), 9)
    }

    func testPreviewRowsKeepStacksSeparateAndLimitEachRowToFive() {
        func item(_ id: UInt32, _ stack: UInt32?) -> WorkspacePreviewWindowItem {
            WorkspacePreviewWindowItem(id: id, title: "Window", appName: "App", appIcon: nil, thumbnail: nil, stackId: stack)
        }
        let windows = [item(1, 1), item(2, 2), item(3, 1), item(4, nil)]
        XCTAssertEqual(workspacePreviewStackRows(windows).map { $0.map(\.id) }, [[1, 3], [2], [4]])
        let largeStack = (1...20).map { item(UInt32($0), 1) }
        XCTAssertEqual(workspacePreviewStackRows(largeStack).map(\.count), [5, 5, 5])
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
        XCTAssertEqual(workspacePreviewWorkspaceSize(aspectRatio: 1.6), CGSize(width: 352, height: 220))
        XCTAssertEqual(workspacePreviewWorkspaceSize(aspectRatio: 0.625), CGSize(width: 220, height: 352))
        XCTAssertEqual(workspacePreviewWorkspaceSize(aspectRatio: 0), CGSize(width: 220, height: 220))
    }

    func testPreviewColumnWidthAdaptsAndReservesWorkspaceColumn() {
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 2, availableWidth: 2000, windowCount: 1), 708.5)
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 6, availableWidth: 2000, windowCount: 3), 1220.5)
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 6, availableWidth: 2000, windowCount: 15), 1732.5)
        XCTAssertEqual(workspacePreviewColumnCount(windowCount: 15, workspaceCount: 6, availableWidth: 1220.5), 3)
        XCTAssertLessThanOrEqual(workspacePreviewPanelWidth(itemCount: 100, availableWidth: 600), 552)
    }

    func testPreviewHeightFitsBothColumnsWithinScreen() {
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 1, availableHeight: 2000, workspaceCount: 1), 376)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 15, availableHeight: 2000, workspaceCount: 1), 985)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 15, availableHeight: 2000, workspaceCount: 6), 1000)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 100, availableHeight: 600, workspaceCount: 100), 480)
        XCTAssertEqual(workspacePreviewMaximumWindows, 15)
        XCTAssertEqual(workspacePreviewCornerRadius, 7)
    }
}
