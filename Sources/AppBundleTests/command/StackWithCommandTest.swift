@testable import AppBundle
import Common
import XCTest

@MainActor
final class StackWithCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testStackWithOtherFromEitherPane() async throws {
        for focusedId: UInt32 in [1, 2] {
            setUpWorkspacesForTests()
            let root = Workspace.get(byName: name).rootTilingContainer
            let left = TestWindow.new(id: 1, parent: root)
            let right = TestWindow.new(id: 2, parent: root)
            _ = (focusedId == 1 ? left : right).focusWindow()
            let command = try parseCommand("stack-with other").cmdOrDie
            let result = try await command.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertEqual(root.children.count, 1)
            let stack = try XCTUnwrap(root.children.first as? TilingContainer)
            XCTAssertEqual(stack.layout, .tabGroup)
            XCTAssertEqual(stack.children.count, 2)
            XCTAssertEqual(stack.mostRecentWindowRecursive?.windowId, focusedId)
        }
    }

    func testStackWithOtherKeepsSourceStackRemainingTabs() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let sourceStack = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tabGroup, index: INDEX_BIND_LAST)
        let staying = TestWindow.new(id: 1, parent: sourceStack)
        let moving = TestWindow.new(id: 2, parent: sourceStack)
        let target = TestWindow.new(id: 3, parent: root)
        _ = moving.focusWindow()
        let result = try await parseCommand("stack-with other").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(staying.parent === sourceStack)
        XCTAssertTrue(moving.parent === target.parent)
        XCTAssertFalse(moving.parent === sourceStack)
    }

    func testStackWithOtherDoesNothingWithOneOrThreePanes() async throws {
        for count in [1, 3] {
            setUpWorkspacesForTests()
            let root = Workspace.get(byName: name).rootTilingContainer
            for id in 1...count {
                let window = TestWindow.new(id: UInt32(id), parent: root)
                if id == 1 { _ = window.focusWindow() }
            }
            let before = root.layoutDescription
            _ = try await parseCommand("stack-with other").cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(root.layoutDescription, before)
        }
    }

    func testStackWithRightCreatesTabGroupContainer() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        try await StackWithCommand(args: StackWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tab_group([
                .window(2),
                .window(1),
            ]),
        ]))
    }

    func testStackWithLeftSplitsFocusedWindowOutOfTabGroup() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer(parent: $0, adaptiveWeight: 1, .v, .tabGroup, index: INDEX_BIND_LAST).apply {
                TestWindow.new(id: 0, parent: $0)
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }
        }
        try await StackWithCommand(args: StackWithCmdArgs(rawArgs: [], direction: .left)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .h_tiles([
            .window(1),
            .window(0),
        ]))
    }
}
