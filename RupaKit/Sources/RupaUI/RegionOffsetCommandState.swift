import RupaCore

struct RegionOffsetCommandState: Equatable {
    enum InputMode: Equatable {
        case inactive
        case arrowDrag
        case distance
    }

    var inputMode: InputMode
    var usesLockedDistance: Bool
    var usesCombinedRegions: Bool

    init(
        inputMode: InputMode = .inactive,
        usesLockedDistance: Bool = false,
        usesCombinedRegions: Bool = false
    ) {
        self.inputMode = inputMode
        self.usesLockedDistance = usesLockedDistance
        self.usesCombinedRegions = usesCombinedRegions
    }

    static var inactive: RegionOffsetCommandState {
        RegionOffsetCommandState()
    }

    var isActive: Bool {
        inputMode != .inactive
    }

    var inputModeTitle: String {
        switch inputMode {
        case .inactive:
            return "Inactive"
        case .arrowDrag:
            return "Arrow"
        case .distance:
            return "Distance"
        }
    }

    mutating func activateArrowDrag() {
        inputMode = .arrowDrag
    }

    mutating func activateDistanceInput() {
        inputMode = .distance
    }

    mutating func deactivate() {
        inputMode = .inactive
        usesLockedDistance = false
        usesCombinedRegions = false
    }

    mutating func toggleLockedDistance() {
        usesLockedDistance.toggle()
    }

    mutating func toggleCombinedRegions() {
        usesCombinedRegions.toggle()
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
