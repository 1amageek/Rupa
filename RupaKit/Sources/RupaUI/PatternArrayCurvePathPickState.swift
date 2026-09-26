import RupaCore

/// The Curve Array path pick in progress: either replacing an existing array's path or choosing
/// the path of a new array made from selected objects.
struct PatternArrayCurvePathPickState: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case existing(PatternArraySourceID)
        case newArray(rootSceneNodeIDs: [SceneNodeID])
    }

    var target: Target?

    static var inactive: PatternArrayCurvePathPickState {
        PatternArrayCurvePathPickState(target: nil)
    }

    var isActive: Bool {
        target != nil
    }

    /// The existing array whose path is being replaced, if any.
    var sourceID: PatternArraySourceID? {
        if case .existing(let sourceID) = target {
            return sourceID
        }
        return nil
    }

    func isPicking(sourceID: PatternArraySourceID) -> Bool {
        self.sourceID == sourceID
    }

    mutating func start(sourceID: PatternArraySourceID) {
        target = .existing(sourceID)
    }

    mutating func startNewArray(rootSceneNodeIDs: [SceneNodeID]) {
        target = .newArray(rootSceneNodeIDs: rootSceneNodeIDs)
    }

    mutating func cancel() {
        target = nil
    }
}
