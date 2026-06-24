import RupaCore

struct PatternArrayCurvePathPickState: Equatable, Sendable {
    var sourceID: PatternArraySourceID?

    static var inactive: PatternArrayCurvePathPickState {
        PatternArrayCurvePathPickState(sourceID: nil)
    }

    var isActive: Bool {
        sourceID != nil
    }

    func isPicking(sourceID: PatternArraySourceID) -> Bool {
        self.sourceID == sourceID
    }

    mutating func start(sourceID: PatternArraySourceID) {
        self.sourceID = sourceID
    }

    mutating func cancel() {
        sourceID = nil
    }
}
