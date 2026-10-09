@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceDefaultNamingTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testLegacyAndAutomaticSlotsShareSequentialDisplayNumbers() {
        let legacy = Workspace.get(byName: "2")
        let automatic = Workspace.get(byName: "4")
        automatic.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 701, parent: legacy.rootTilingContainer)
        _ = TestWindow.new(id: 702, parent: automatic.rootTilingContainer)
        _ = legacy.focusWorkspace()

        let workspaces = monitorScopedAutomaticDisplayWorkspacesInExactProject(
            projectId: legacy.projectId,
            monitor: legacy.workspaceMonitor,
            focusedWorkspace: legacy
        )
        XCTAssertTrue(workspaces.contains(legacy))
        XCTAssertTrue(workspaces.contains(automatic))
        XCTAssertEqual(workspaces.map { workspaceDisplayName($0.name) },
                       workspaces.indices.map { "Workspace \($0 + 1)" })
    }

    func testCustomNamesAndLabelsRemainVisible() {
        let named = Workspace.get(byName: "Research")
        XCTAssertEqual(workspaceDisplayName(named.name), "Research")
        let numeric = Workspace.get(byName: "2")
        config.workspaceSidebar.workspaceLabels[numeric.name] = "Applications"
        XCTAssertEqual(workspaceDisplayName(numeric.name), "Applications")
    }
}
