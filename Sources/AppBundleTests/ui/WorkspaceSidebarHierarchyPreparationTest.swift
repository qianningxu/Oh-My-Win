@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceSidebarHierarchyPreparationTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testDefaultFolderMetadataDoesNotResurrectPrunedEmptyProject() throws {
        config.workspaceSidebar.folderLabels[workspaceFolderDefaultId.rawValue] = "Unfolded"
        config.workspaceSidebar.folderColors[workspaceFolderDefaultId.rawValue] = "#777777"
        let project = createWorkspaceProject(displayName: "Occupied")
        let workspace = try XCTUnwrap(projectWorkspaces(projectId: project.id).first)
        TestWindow.new(id: 8121, parent: workspace.rootTilingContainer)
        XCTAssertTrue(workspace.focusWorkspace())
        Workspace.reconcileWorkspaceState()

        for _ in 0..<3 {
            let hierarchy = prepareWorkspaceSidebarHierarchyInputs()
            XCTAssertEqual(hierarchy.projects.map(\.id), [project.id])
            XCTAssertEqual(hierarchy.orderedWorkspaces, [workspace])
            XCTAssertNil(winMuxWorkspaceState.projectsById[workspaceProjectDefaultId])
            XCTAssertNil(winMuxWorkspaceState.workspaceFoldersById[workspaceFolderDefaultId])
            _ = FrozenSidebarState(restorableWorkspaces: [workspace])
        }
    }

    func testNewTabDoesNotRetainRecreatedDefaultProject() throws {
        let project = createWorkspaceProject(displayName: "Occupied")
        let occupied = try XCTUnwrap(projectWorkspaces(projectId: project.id).first)
        TestWindow.new(id: 8122, parent: occupied.rootTilingContainer)
        XCTAssertTrue(occupied.focusWorkspace())
        Workspace.reconcileWorkspaceState()
        XCTAssertNil(winMuxWorkspaceState.projectsById[workspaceProjectDefaultId])

        for _ in 0..<3 {
            let blank = createFreshAdjacentBlankWorkspace(
                folderId: occupied.folderId, monitor: mainMonitor, after: occupied
            )
            XCTAssertTrue(blank.focusWorkspace())
            let hierarchy = prepareWorkspaceSidebarHierarchyInputs()
            XCTAssertEqual(hierarchy.projects.map(\.id), [project.id])
            XCTAssertTrue(Workspace.existing(byName: blank.name) === blank)
            XCTAssertTrue(occupied.focusWorkspace())
            XCTAssertNil(Workspace.existing(byName: blank.name))
            XCTAssertEqual(prepareWorkspaceSidebarHierarchyInputs().orderedWorkspaces, [occupied])
            _ = FrozenSidebarState(restorableWorkspaces: [occupied])
            XCTAssertNil(winMuxWorkspaceState.projectsById[workspaceProjectDefaultId])
        }

        let background = createWorkspaceProject(displayName: "New project")
        XCTAssertTrue(prepareWorkspaceSidebarHierarchyInputs().projects.contains { $0.id == background.id })
    }

    func testPreparationMaterializesNormalizesAndIsIdempotent() {
        let focusedWorkspace = focus.workspace
        config.workspaceSidebar.projectLabels["client"] = "Client"

        var defaultProject = winMuxWorkspaceState.projectsById[workspaceProjectDefaultId]!
        defaultProject.folderOrder = [workspaceFolderDefaultId, workspaceFolderDefaultId]
        winMuxWorkspaceState.projectsById[workspaceProjectDefaultId] = defaultProject

        var defaultFolder = winMuxWorkspaceState.workspaceFoldersById[workspaceFolderDefaultId]!
        defaultFolder.workspaceOrder = []
        winMuxWorkspaceState.workspaceFoldersById[workspaceFolderDefaultId] = defaultFolder

        let first = prepareWorkspaceSidebarHierarchyInputs()
        let workspaceIdsAfterFirstPreparation = Set(Workspace.all.map(\.id))
        let second = prepareWorkspaceSidebarHierarchyInputs()

        XCTAssertEqual(first.projects.map(\.id), [workspaceProjectDefaultId, WorkspaceProjectId("client")])
        XCTAssertEqual(
            first.folders.map(\.id),
            [workspaceFolderDefaultId, WorkspaceFolderId("unfolded-client")]
        )
        XCTAssertEqual(
            winMuxWorkspaceState.projectsById[workspaceProjectDefaultId]?.folderOrder,
            [workspaceFolderDefaultId]
        )
        XCTAssertEqual(
            winMuxWorkspaceState.workspaceFoldersById[workspaceFolderDefaultId]?.workspaceOrder,
            [focusedWorkspace.id]
        )
        XCTAssertEqual(Set(first.orderedWorkspaces.map(\.id)), workspaceIdsAfterFirstPreparation)
        XCTAssertEqual(Set(second.orderedWorkspaces.map(\.id)), workspaceIdsAfterFirstPreparation)
        XCTAssertEqual(Set(Workspace.all.map(\.id)), workspaceIdsAfterFirstPreparation)
    }
}
