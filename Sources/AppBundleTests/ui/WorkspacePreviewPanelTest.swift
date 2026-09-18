@testable import AppBundle
import XCTest

final class WorkspacePreviewPanelTest: XCTestCase {
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
