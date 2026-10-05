import SwiftCAD
import RupaCoreTypes

/// Original circular source retained independently from projected dimension proposals.
public struct DrawingRadialDimensionMeasurement: Sendable {
    public let annotation: DrawingProjectionResult.Annotation
    public let original: OriginalCircularMeasurement
    public let occurrenceID: SceneOccurrenceID?
    public let bodyID: BodyID?
    public let sourceFeatureID: FeatureID?
    public let sourceSketchEntityID: SketchEntityID?
    public let projectedCenter: CoordinateEnclosure2D
    public let projectedBoundary: CoordinateEnclosure2D
}
