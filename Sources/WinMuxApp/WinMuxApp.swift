import AppBundle
import AppKit
import SwiftUI

// This file is shared between SPM and xcode project

@MainActor
final class WinMuxAppDelegate: NSObject, NSApplicationDelegate {
    private var isTerminating = false
    private var terminationCoordinator: TerminationPreparationCoordinator?
    private var menuBarController: NativeMenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = NativeMenuBarController(viewModel: .shared)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true
        terminationCoordinator = TerminationPreparationCoordinator { [weak self] shouldTerminate in
            sender.reply(toApplicationShouldTerminate: shouldTerminate)
            if shouldTerminate {
                self?.terminationCoordinator = nil
            }
        }
        terminationCoordinator?.start()
        return .terminateLater
    }
}

@main
struct WinMuxApp: App {
    @NSApplicationDelegateAdaptor(WinMuxAppDelegate.self) var appDelegate
    @StateObject var messageModel = MessageModel.shared
    @Environment(\.openWindow) var openWindow: OpenWindowAction

    init() {
        initAppBundle()
    }

    var body: some Scene {
        getMessageWindow(messageModel: messageModel)
            .onChange(of: messageModel.message) { message in
                if message != nil {
                    openWindow(id: messageWindowId)
                }
            }
    }
}
