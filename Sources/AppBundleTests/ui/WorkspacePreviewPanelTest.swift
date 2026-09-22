@testable import AppBundle
import XCTest

final class WorkspacePreviewPanelTest: XCTestCase {
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
