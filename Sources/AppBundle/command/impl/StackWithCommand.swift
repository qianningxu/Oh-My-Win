import AppKit
import Common

struct StackWithCommand: Command {
    let args: StackWithCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        if args.direction.val == .other {
            guard let split = twoPaneHorizontalSplit(for: currentWindow),
            let sourceIndex = split.children.firstIndex(where: { child in
                currentWindow.parentsWithSelf.contains(where: { $0 === child })
            }),
            let otherWindow = split.children[1 - sourceIndex].mostRecentWindowRecursive
            else { return true }
            createOrAppendWindowTabStack(sourceWindow: currentWindow, onto: otherWindow)
            return true
        }
        guard let direction = args.direction.val.cardinalDirection else { return false }

        if let parent = currentWindow.parent as? TilingContainer, parent.layout == .tabGroup {
            guard removeWindowFromTabStack(currentWindow) else {
                return io.err("Failed to remove workspace window from stacked window")
            }
            let moveArgs = MoveCmdArgs(rawArgs: [], direction)
            return MoveCommand(args: moveArgs).run(env, io)
        }

        guard let (parent, ownIndex) = currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) else {
            return io.err("No windows in the specified direction")
        }
        guard let targetWindow = parent.children[ownIndex + direction.focusOffset].findLeafWindowRecursive(snappedTo: direction.opposite) else {
            return io.err("No windows in the specified direction")
        }
        createOrAppendWindowTabStack(sourceWindow: currentWindow, onto: targetWindow)
        return true
    }
}
