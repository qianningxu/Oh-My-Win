public struct StackWithCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .stackWith,
        allowInConfig: true,
        help: stack_with_help_generated,
        flags: [
            "--window-id": optionalWindowIdFlag(),
        ],
        posArgs: [newMandatoryPosArgParser(\.direction, parseStackDirection, placeholder: StackDirection.unionLiteral)],
    )

    public var direction: Lateinit<StackDirection> = .uninitialized

    public init(rawArgs: [String], direction: CardinalDirection) {
        self.commonState = .init(rawArgs.slice)
        self.direction = .initialized(StackDirection(rawValue: direction.rawValue)!)
    }
}

public enum StackDirection: String, CaseIterable, Sendable {
    case left, down, up, right, other

    public var cardinalDirection: CardinalDirection? { CardinalDirection(rawValue: rawValue) }
}

private func parseStackDirection(i: PosArgParserInput) -> ParsedCliArgs<StackDirection> {
    .init(parseEnum(i.arg, StackDirection.self), advanceBy: 1)
}
