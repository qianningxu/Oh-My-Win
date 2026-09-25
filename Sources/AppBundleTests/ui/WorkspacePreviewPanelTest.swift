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
            standardGap * 87
        )
    }

    func testWorkspacePanelWidthIncludesSpacingBetweenCards() {
        XCTAssertEqual(
            workspacePreviewPanelWidth(itemCount: 2, availableWidth: 1_000),
            standardGap * 165.5
        )
    }

    func testWorkspacePanelWidthStaysWithinScreen() {
        XCTAssertEqual(
            workspacePreviewPanelWidth(itemCount: 3, availableWidth: 600),
            552
        )
    }
}
