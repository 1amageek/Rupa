import RupaCore

struct EdgeOffsetCommandState: Equatable {
    enum InputMode: Equatable {
        case inactive
        case distance
    }

    var inputMode: InputMode
    var usesLockedDistance: Bool

    init(
        inputMode: InputMode = .inactive,
        usesLockedDistance: Bool = false
    ) {
        self.inputMode = inputMode
        self.usesLockedDistance = usesLockedDistance
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
        usesLockedDistance = false
    }

    mutating func toggleLockedDistance() {
        usesLockedDistance.toggle()
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
