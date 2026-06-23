import RupaCore

public struct ViewportSketchControlPointHitPolicy: Equatable, Sendable {
    public struct Target: Equatable, Hashable, Sendable {
        public var featureID: FeatureID
        public var entityID: SketchEntityID

        public init(featureID: FeatureID, entityID: SketchEntityID) {
            self.featureID = featureID
            self.entityID = entityID
        }
    }

    private enum Mode: Equatable, Sendable {
        case all
        case none
        case only(Set<Target>)
    }

    public static let all = ViewportSketchControlPointHitPolicy(mode: .all)
    public static let none = ViewportSketchControlPointHitPolicy(mode: .none)

    private var mode: Mode

    public static func only(_ targets: Set<Target>) -> ViewportSketchControlPointHitPolicy {
        if targets.isEmpty {
            return .none
        }
        return ViewportSketchControlPointHitPolicy(mode: .only(targets))
    }

    public func allows(featureID: FeatureID, entityID: SketchEntityID) -> Bool {
        switch mode {
        case .all:
            return true
        case .none:
            return false
        case .only(let targets):
            return targets.contains(Target(featureID: featureID, entityID: entityID))
        }
    }

    private init(mode: Mode) {
        self.mode = mode
    }
}
