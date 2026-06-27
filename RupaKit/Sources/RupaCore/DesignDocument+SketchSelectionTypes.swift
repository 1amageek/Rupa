import SwiftCAD

extension DesignDocument {
    typealias EditableProfileRegionSelection = (
        featureID: FeatureID,
        profileIndex: Int,
        feature: FeatureNode,
        sketch: Sketch,
        profile: Profile
    )
    typealias PlannedOffsetRegionFeature = (
        name: String,
        result: OffsetRegionBuilder.Result
    )
    typealias EditableSketchEntitySelection = (
        featureID: FeatureID,
        entityID: SketchEntityID,
        feature: FeatureNode,
        sketch: Sketch,
        entity: SketchEntity
    )

    struct LineEndpoint {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .lineStart(entityID) : .lineEnd(entityID)
        }

        var oppositeReference: SketchReference {
            isStart ? .lineEnd(entityID) : .lineStart(entityID)
        }
    }

    struct ArcEndpoint {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .arcStart(entityID) : .arcEnd(entityID)
        }

        var oppositeReference: SketchReference {
            isStart ? .arcEnd(entityID) : .arcStart(entityID)
        }
    }

    enum SketchCurveEndpoint {
        case line(LineEndpoint)
        case arc(ArcEndpoint)

        var entityID: SketchEntityID {
            switch self {
            case .line(let endpoint):
                endpoint.entityID
            case .arc(let endpoint):
                endpoint.entityID
            }
        }

        var isStart: Bool {
            switch self {
            case .line(let endpoint):
                endpoint.isStart
            case .arc(let endpoint):
                endpoint.isStart
            }
        }

        var reference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.reference
            case .arc(let endpoint):
                endpoint.reference
            }
        }

        var oppositeReference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.oppositeReference
            case .arc(let endpoint):
                endpoint.oppositeReference
            }
        }
    }
}
