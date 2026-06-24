import RupaCore

struct PatternArrayCurvePathCandidate: Equatable, Sendable {
    var target: SelectionTarget
    var featureID: FeatureID
    var entityID: SketchEntityID
    var title: String

    init?(
        target: SelectionTarget,
        featureID: FeatureID,
        entityID: SketchEntityID,
        sourceFeatureName: String?,
        entityKind: String
    ) {
        guard Self.supports(entityKind: entityKind) else {
            return nil
        }
        self.target = target
        self.featureID = featureID
        self.entityID = entityID
        self.title = Self.title(
            sourceFeatureName: sourceFeatureName,
            entityKind: entityKind
        )
    }

    var path: PatternArrayCurvePath {
        .sketchEntity(featureID: featureID, entityID: entityID)
    }

    func matches(_ path: PatternArrayCurvePath) -> Bool {
        self.path == path
    }

    static func supports(entityKind: String) -> Bool {
        switch entityKind {
        case "line", "circle", "arc", "spline":
            true
        default:
            false
        }
    }

    private static func title(
        sourceFeatureName: String?,
        entityKind: String
    ) -> String {
        let kindTitle = entityKind.prefix(1).uppercased() + entityKind.dropFirst()
        guard let sourceFeatureName,
              sourceFeatureName.isEmpty == false else {
            return kindTitle
        }
        return "\(sourceFeatureName) \(kindTitle)"
    }
}
