@testable import AppBundle
import Common
import XCTest

@MainActor
final class SplitCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testRatiosUseLeftRightOrderWithRightPaneFocused() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let left = TestWindow.new(id: 1, parent: root, adaptiveWeight: 300)
        let right = TestWindow.new(id: 2, parent: root, adaptiveWeight: 300)
        _ = right.focusWindow()
        config.enableNormalizationFlattenContainers = true
        for (ratio, expectedLeft) in [("1:2", 200.0), ("1:1", 300.0), ("2:1", 400.0)] {
            let result = try await parseCommand("split \(ratio)").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode, 0)
            XCTAssertEqual(left.hWeight, CGFloat(expectedLeft), accuracy: 0.001)
            XCTAssertEqual(right.hWeight, CGFloat(600 - expectedLeft), accuracy: 0.001)
        }
    }

    func testRatioLeavesOtherLayoutsUnchanged() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let left = TestWindow.new(id: 1, parent: root, adaptiveWeight: 300)
        let right = TestWindow.new(id: 2, parent: root, adaptiveWeight: 300)
        _ = left.focusWindow()
        root.changeOrientation(.v)
        _ = try await parseCommand("split 1:2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(left.getWeight(.v), right.getWeight(.v))
        root.changeOrientation(.h)
        TestWindow.new(id: 3, parent: root, adaptiveWeight: 300)
        let before = root.children.map { $0.getWeight(.h) }
        _ = try await parseCommand("split 2:1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(root.children.map { $0.getWeight(.h) }, before)
    }

    func testRatiosIgnoreNestedThirdPane() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let nested = TilingContainer.newVTiles(parent: root, adaptiveWeight: 300)
        let focused = TestWindow.new(id: 1, parent: nested)
        TestWindow.new(id: 2, parent: nested)
        TestWindow.new(id: 3, parent: root, adaptiveWeight: 300)
        _ = focused.focusWindow()
        XCTAssertNil(twoPaneHorizontalSplit(for: focused))
        let before = root.children.map { $0.hWeight }
        _ = try await parseCommand("split 1:2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(root.children.map { $0.hWeight }, before)
    }

    func testRatiosResizeWholeStackWithEitherTabFocused() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let stack = TilingContainer(parent: root, adaptiveWeight: 300, .v, .tabGroup, index: INDEX_BIND_LAST)
        let first = TestWindow.new(id: 1, parent: stack)
        let second = TestWindow.new(id: 2, parent: stack)
        let right = TestWindow.new(id: 3, parent: root, adaptiveWeight: 300)
        for focused in [first, second] {
            _ = focused.focusWindow()
            for (ratio, expectedLeft) in [("1:2", 200.0), ("1:1", 300.0), ("2:1", 400.0)] {
                _ = try await parseCommand("split \(ratio)").cmdOrDie.run(.defaultEnv, .emptyStdin)
                XCTAssertEqual(stack.getWeight(.h), CGFloat(expectedLeft), accuracy: 0.001)
                XCTAssertEqual(right.getWeight(.h), CGFloat(600 - expectedLeft), accuracy: 0.001)
                XCTAssertTrue(first.parent === stack)
                XCTAssertTrue(second.parent === stack)
                XCTAssertEqual(root.children.count, 2)
            }
        }
    }

    func testSinglePanePullsOnlyFocusedTabLeftOrRight() async throws {
        for direction in ["left", "right"] {
            for wrapped in [false, true] {
                setUpWorkspacesForTests()
                let workspace = Workspace.get(byName: name)
                let root = workspace.rootTilingContainer
                let stack: TilingContainer
                if wrapped {
                    stack = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tabGroup, index: INDEX_BIND_LAST)
                } else {
                    root.layout = .tabGroup
                    stack = root
                }
                let first = TestWindow.new(id: 1, parent: stack)
                let moving = TestWindow.new(id: 2, parent: stack)
                let last = TestWindow.new(id: 3, parent: stack)
                _ = moving.focusWindow()
                _ = try await parseCommand("split --single-pane-direction \(direction) 1:2").cmdOrDie.run(.defaultEnv, .emptyStdin)
                let result = workspace.rootTilingContainer
                XCTAssertEqual(result.children.count, 2)
                XCTAssertEqual(result.orientation, .h)
                XCTAssertTrue(result.children[direction == "left" ? 0 : 1] === moving)
                XCTAssertTrue(first.parent === stack)
                XCTAssertTrue(last.parent === stack)
                XCTAssertEqual(stack.children.count, 2)
                XCTAssertEqual(result.children[0].getWeight(.h), result.children[1].getWeight(.h))
            }
        }
    }

    func testSingleWindowCannotCreateEmptyPane() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let window = TestWindow.new(id: 1, parent: root)
        _ = window.focusWindow()
        let before = root.layoutDescription
        _ = try await parseCommand("split --single-pane-direction left 1:2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(root.layoutDescription, before)
    }

    func testSplit() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        try await SplitCommand(args: SplitCmdArgs(rawArgs: [], .vertical)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([
                .window(1),
            ]),
            .window(2),
        ]))
    }

    func testSplitOppositeOrientation() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        try await SplitCommand(args: SplitCmdArgs(rawArgs: [], .opposite)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([
                .window(1),
            ]),
            .window(2),
        ]))
    }

    func testChangeOrientation() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }
            TestWindow.new(id: 2, parent: $0)
        }

        try await SplitCommand(args: SplitCmdArgs(rawArgs: [], .horizontal)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .h_tiles([
                .window(1),
            ]),
            .window(2),
        ]))
    }

    func testToggleOrientation() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }
            TestWindow.new(id: 2, parent: $0)
        }

        try await SplitCommand(args: SplitCmdArgs(rawArgs: [], .opposite)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .h_tiles([
                .window(1),
            ]),
            .window(2),
        ]))
    }
}
