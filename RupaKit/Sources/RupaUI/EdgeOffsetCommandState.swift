import RupaCore

struct EdgeOffsetCommandState: Equatable {
    enum InputMode: Equatable {
        case inactive
        case distance
    }

    var inputMode: InputMode

    init(inputMode: InputMode = .inactive) {
        self.inputMode = inputMode
    }

    static var inactive: EdgeOffsetCommandState {
        EdgeOffsetCommandState()
    }

    var isActive: Bool {
        inputMode != .inactive
    }

    var inputModeTitle: String {
        switch inputMode {
        case .inactive:
            return "Inactive"
        case .distance:
            return "Distance"
        }
    }

    mutating func activateDistanceInput() {
        inputMode = .distance
    }

    mutating func deactivate() {
        inputMode = .inactive
    }

    func gapFill(after current: OffsetCurveGapFill) -> OffsetCurveGapFill {
        switch current {
        case .round:
            return .linear
        case .linear:
            return .natural
        case .natural:
            return .round
        }
    }
}
