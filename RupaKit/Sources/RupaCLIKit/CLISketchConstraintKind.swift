import ArgumentParser

public enum CLISketchConstraintKind: String, CaseIterable, ExpressibleByArgument {
    case coincident
    case horizontal
    case vertical
    case parallel
    case perpendicular
    case equalLength
    case tangent
    case concentric
    case equalRadius
    case smoothSplineControlPoint
    case splineEndpointTangent
    case tangentSplineEndpoints
    case smoothSplineEndpoints
    case fixed
}
