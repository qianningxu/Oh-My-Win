public struct SplitCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .split,
        allowInConfig: true,
        help: split_help_generated,
        flags: [
            "--window-id": optionalWindowIdFlag(),
            "--single-pane-direction": ArgParser(\.singlePaneDirection, upcastArgParserFun(parseSinglePaneDirection)),
        ],
        posArgs: [newMandatoryPosArgParser(\.arg, parseSplitArg, placeholder: SplitArg.unionLiteral)],
    )

    public var arg: Lateinit<SplitArg> = .uninitialized
    public var singlePaneDirection: CardinalDirection? = nil

    public init(rawArgs: [String], _ arg: SplitArg) {
        self.commonState = .init(rawArgs.slice)
        self.arg = .initialized(arg)
    }

    public enum SplitArg: String, CaseIterable, Sendable {
        case horizontal, vertical, opposite
        case oneToTwo = "1:2"
        case oneToOne = "1:1"
        case twoToOne = "2:1"

        public var leftFraction: Double? {
            switch self {
                case .oneToTwo: 1.0 / 3.0
                case .oneToOne: 0.5
                case .twoToOne: 2.0 / 3.0
                default: nil
            }
        }
    }
}

func parseSplitCmdArgs(_ args: StrArrSlice) -> ParsedCmd<SplitCmdArgs> {
    parseSpecificCmdArgs(SplitCmdArgs(rawArgs: args), args)
}

private func parseSplitArg(i: PosArgParserInput) -> ParsedCliArgs<SplitCmdArgs.SplitArg> {
    .init(parseEnum(i.arg, SplitCmdArgs.SplitArg.self), advanceBy: 1)
}

private func parseSinglePaneDirection(i: SubArgParserInput) -> ParsedCliArgs<CardinalDirection> {
    guard let raw = i.nonFlagArgOrNil(), let direction = CardinalDirection(rawValue: raw),
          direction == .left || direction == .right
    else { return .fail("Single-pane direction must be left or right", advanceBy: 0) }
    return .succ(direction, advanceBy: 1)
}
