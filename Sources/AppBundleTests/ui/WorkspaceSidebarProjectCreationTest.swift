@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceSidebarProjectCreationTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testNewProjectIsSelectedAndFocusedImmediately() async throws {
        let previousWorkspace = focus.workspace
        let previousProjects = Set(workspaceProjects().map(\.id))

        await createWorkspaceSidebarProject()?.value

        let project = try XCTUnwrap(workspaceProjects().first { !previousProjects.contains($0.id) })
        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), project.id)
        XCTAssertEqual(TrayMenuModel.shared.workspaceSidebarActiveProjectId, project.id)
        XCTAssertEqual(focus.workspace.projectId, project.id)
        XCTAssertFalse(focus.workspace === previousWorkspace)
        XCTAssertTrue(focus.workspace.isOrdinaryEmptySlot)
    }

    func testNamedProjectIsSelectedAfterCreation() async throws {
        await createWorkspaceSidebarProject(displayName: "  Writing  ")?.value

        let project = try XCTUnwrap(workspaceProjects().first { $0.name == "Writing" })
        XCTAssertEqual(focus.workspace.projectId, project.id)
        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), project.id)
    }
}
