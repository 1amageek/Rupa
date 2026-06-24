import RupaCore

struct PatternArrayCurvePathCandidate: Equatable, Sendable {
    enum EntityKind: String, Equatable, Sendable {
        case line
        case circle
        case arc
        case spline

        var title: String {
            rawValue.prefix(1).uppercased() + String(rawValue.dropFirst())
        }
    }

    var target: SelectionTarget
    var featureID: FeatureID
    var entityID: SketchEntityID
    var title: String

    init?(
        target: SelectionTarget,
        document: DesignDocument
    ) {
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityBaseReference,
              let sceneNode = document.productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              sceneNode.reference?.featureID == reference.featureID,
              let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID],
              let entityKind = Self.entityKind(for: entity) else {
            return nil
        }
        self.init(
            target: target,
            featureID: reference.featureID,
            entityID: reference.entityID,
            sourceFeatureName: feature.name,
            entityKind: entityKind
        )
    }

    init?(
        target: SelectionTarget,
        featureID: FeatureID,
        entityID: SketchEntityID,
        sourceFeatureName: String?,
        entityKind: String
    ) {
        guard let kind = EntityKind(rawValue: entityKind) else {
            return nil
        }
        self.init(
            target: target,
            featureID: featureID,
            entityID: entityID,
            sourceFeatureName: sourceFeatureName,
            entityKind: kind
        )
    }

    private init(
        target: SelectionTarget,
        featureID: FeatureID,
        entityID: SketchEntityID,
        sourceFeatureName: String?,
        entityKind: EntityKind
    ) {
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
        EntityKind(rawValue: entityKind) != nil
    }

    private static func title(
        sourceFeatureName: String?,
        entityKind: EntityKind
    ) -> String {
        guard let sourceFeatureName,
              sourceFeatureName.isEmpty == false else {
            return entityKind.title
        }
        return "\(sourceFeatureName) \(entityKind.title)"
    }

    private static func entityKind(for entity: SketchEntity) -> EntityKind? {
        switch entity {
        case .point:
            nil
        case .line:
            .line
        case .circle:
            .circle
        case .arc:
            .arc
        case .spline:
            .spline
        }
    }
}
