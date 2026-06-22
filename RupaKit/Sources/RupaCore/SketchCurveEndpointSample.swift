import SwiftCAD

struct SketchCurveEndpointSample: Equatable, Sendable {
    enum EndpointKind: Equatable, Sendable {
        case line(SketchEntityID)
        case arc(SketchEntityID)
        case spline(SketchSplineEndpointReference?)
    }

    var entityID: SketchEntityID
    var kind: EndpointKind
    var referenceDescription: String
    var reference: SketchReference
    var pointReference: SketchReference?
    var sample: CurveEvaluationSample
    var outgoingTangent: CADCore.Point2D
}
