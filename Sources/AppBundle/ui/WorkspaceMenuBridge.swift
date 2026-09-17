import Foundation

private let workspaceRenameNotification = Notification.Name("com.qianningxu.oh-my-win.workspace.rename")

@MainActor
final class WorkspaceMenuBridge {
    static let shared = WorkspaceMenuBridge()

    private var observer: NSObjectProtocol?

    private init() {}

    func install() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: workspaceRenameNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let workspaceName = notification.userInfo?["workspaceName"] as? String,
                  let displayName = notification.userInfo?["displayName"] as? String
            else { return }
            Task { @MainActor in
                try? renameWorkspaceForSidebar(
                    workspaceName: workspaceName,
                    displayName: displayName
                )
            }
        }
    }
}
