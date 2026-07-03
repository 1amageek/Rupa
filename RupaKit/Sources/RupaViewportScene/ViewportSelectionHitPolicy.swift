import RupaCore

public enum ViewportSelectionHitPolicy: Equatable, Sendable {
    case all
    case object
    case face
    case edge
    case vertex
    case region
    case sketchEntity

    public var allowsObjectHits: Bool {
        self == .all || self == .object
    }

    public var allowsFaceHits: Bool {
        self == .all || self == .face
    }

    public var allowsEdgeHits: Bool {
        self == .all || self == .edge
    }

    public var allowsVertexHits: Bool {
        self == .all || self == .vertex
    }

    public var allowsRegionHits: Bool {
        self == .all || self == .region
    }

    public var allowsSketchEntityHits: Bool {
        self == .all || self == .sketchEntity
    }

    public func allows(geometry: ViewportIdentityPickGeometry) -> Bool {
        switch geometry {
        case .body:
            return allowsObjectHits
        case .sketchEntity:
            return allowsObjectHits || allowsSketchEntityHits
        case .sketchControlPoint:
            return allowsSketchEntityHits
        case .sketchRegion:
            return allowsRegionHits
        case .generatedFace,
             .projectedBodyFace:
            return allowsFaceHits
        case .generatedEdge,
             .projectedBodyEdge:
            return allowsEdgeHits
        case .generatedVertex,
             .surfaceKnot,
             .surfaceSpan,
             .surfaceTrimKnot,
             .surfaceTrimSpan,
             .projectedBodyVertex:
            return allowsVertexHits
        }
    }

    public func allows(component: SelectionComponent) -> Bool {
        switch component {
        case .object:
            return allowsObjectHits
        case .face:
            return allowsFaceHits
        case .edge:
            return allowsEdgeHits
        case .vertex:
            return allowsVertexHits
        case .region:
            return allowsRegionHits
        case .sketchEntity:
            return allowsSketchEntityHits
        case .constructionPlane:
            return allowsObjectHits
        }
    }

    public func allows(hit: ViewportHit) -> Bool {
        if hit.selectionReference != nil {
            return allowsVertexHits
        }
        if let component = hit.selectionComponent {
            return allows(component: component)
        }

        switch hit.kind {
        case .body:
            if hit.bodyFace != nil {
                return allowsFaceHits
            }
            if hit.bodyEdge != nil {
                return allowsEdgeHits
            }
            if hit.bodyVertex != nil {
                return allowsVertexHits
            }
            return allowsObjectHits
        case .sketch:
            guard hit.sketchEntityID != nil else {
                return false
            }
            if hit.sketchPointHandle != nil || hit.sketchControlPointIndex != nil {
                return allowsSketchEntityHits
            }
            return allowsObjectHits || allowsSketchEntityHits
        }
    }
}
