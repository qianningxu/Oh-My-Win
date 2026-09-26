@testable import AppBundle
import XCTest

final class NativeOverlayWindowTest: XCTestCase {
    func testChatGPTMainWindowTilesDespiteMissingFullscreenControlOrStandardSubrole() {
        let mainWindow = ChatGPTWindowAxMock(isMain: true, subrole: "AXUnknown")
        for id in [KnownBundleId.chatgpt, .codex] {
            XCTAssertEqual(mainWindow.getWindowType(axApp: mainWindow, id, .regular, .normalWindow), .window)
            XCTAssertEqual(mainWindow.getWindowType(axApp: mainWindow, id, .regular, .alwaysOnTopWindow), .popup)
        }

        let dialog = ChatGPTWindowAxMock(isMain: true, subrole: kAXDialogSubrole)
        XCTAssertEqual(dialog.getWindowType(axApp: dialog, .codex, .regular, .normalWindow), .dialog)
        let secondary = ChatGPTWindowAxMock(isMain: false, subrole: kAXStandardWindowSubrole)
        XCTAssertEqual(secondary.getWindowType(axApp: secondary, .codex, .regular, .normalWindow), .dialog)
    }

    func testChatGPTCompanionsStayUnmanagedWithoutExcludingMainWindows() {
        for id in [KnownBundleId.chatgpt, .codex] {
            XCTAssertTrue(isNativeOverlayWindow(level: .alwaysOnTopWindow, appId: id))
            XCTAssertFalse(isNativeOverlayWindow(level: .normalWindow, appId: id))
            XCTAssertFalse(isNativeOverlayWindow(level: nil, appId: id))
        }
        XCTAssertFalse(isNativeOverlayWindow(level: .alwaysOnTopWindow, appId: .vscode))
        XCTAssertFalse(isNativeOverlayWindow(level: .alwaysOnTopWindow, appId: nil))
        XCTAssertTrue(isNativeOverlayWindow(level: .unknown(windowLevel: 1001), appId: nil))
    }

    @MainActor
    func testRestoredTiledCompanionIsRemovedFromWorkspace() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "companion")
        let window = Window(id: 9123, CompanionApp(), lastFloatingSize: nil,
                            parent: workspace.rootTilingContainer, adaptiveWeight: 1, index: 0)
        XCTAssertTrue(normalizeSystemOverlayWindow(window, level: .alwaysOnTopWindow))
        XCTAssertTrue(window.parent === macosPopupWindowsContainer)
        XCTAssertFalse(window.participatesInWorkspaceFocus)
        XCTAssertFalse(workspace.allLeafWindowsRecursive.contains(window))
        window.unbindFromParent()
    }
}

private struct ChatGPTWindowAxMock: AxUiElementMock {
    let isMain: Bool
    let subrole: String?

    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        switch attr.key {
            case kAXMainAttribute: isMain as? Attr.T
            case kAXSubroleAttribute: subrole as? Attr.T
            default: nil
        }
    }

    func containingWindowId() -> CGWindowID? { nil }
}

private final class CompanionApp: AbstractApp {
    let pid: Int32 = 0
    let rawAppBundleId: String? = "com.openai.codex"
    let name: String? = "ChatGPT"
    let execPath: String? = nil
    let bundlePath: String? = nil
    var windows: [Window] = []
    @MainActor func getFocusedWindow() -> Window? { nil }
}
