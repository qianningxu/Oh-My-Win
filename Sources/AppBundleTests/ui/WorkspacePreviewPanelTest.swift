@testable import AppBundle
import XCTest

final class WorkspacePreviewPanelTest: XCTestCase {
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

    func testSingleWorkspacePanelUsesEqualTopAndHorizontalPadding() {
        XCTAssertEqual(
            workspacePreviewPanelWidth(itemCount: 1, availableWidth: 1_000),
            920
        )
    }

    func testWorkspacePanelWidthIncludesSpacingBetweenCards() {
        XCTAssertEqual(
            workspacePreviewPanelWidth(itemCount: 2, availableWidth: 1_000),
            920
        )
    }

    func testPreviewHasMaximumDimensionsEvenWithManyWorkspacesAndWindows() {
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 100, availableWidth: 3_000), 996)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 100, availableHeight: 2_000), 670.5)
    }

    func testPreviewHeightStaysWithinSmallScreenAndUsesFixedRows() {
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 1, availableHeight: 1_000), 382.5)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 2, availableHeight: 1_000), 382.5)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 3, availableHeight: 1_000), 382.5)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 100, availableHeight: 600), 480)
    }

    func testPreviewUsesFiveColumnsAndCapsAtThreeRows() {
        XCTAssertEqual(workspacePreviewColumns, 5)
        XCTAssertEqual(workspacePreviewMaximumWindows, 15)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 5, availableHeight: 2_000), 382.5)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 6, availableHeight: 2_000), 526.5)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 15, availableHeight: 2_000), 670.5)
        XCTAssertEqual(workspacePreviewPanelHeight(maximumWindowCount: 16, availableHeight: 2_000), 670.5)
    }

    func testPreviewWidthAdaptsToActualWindowsAndLegacyWorkspaces() {
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 2, availableWidth: 2_000, windowCount: 1), 228)
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 2, availableWidth: 2_000, windowCount: 3), 612)
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 6, availableWidth: 2_000, windowCount: 1), 996)
        XCTAssertEqual(workspacePreviewPanelWidth(itemCount: 2, availableWidth: 2_000, windowCount: 15), 996)
    }

    func testWorkspacePanelWidthStaysWithinScreen() {
        XCTAssertEqual(
            workspacePreviewPanelWidth(itemCount: 3, availableWidth: 600),
            552
        )
    }
}
