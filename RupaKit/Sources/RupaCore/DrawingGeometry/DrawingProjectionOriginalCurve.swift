import SwiftCAD
import RupaCoreTypes

/// Historical original law and provenance retained by the wire drawing result.
public struct DrawingProjectionOriginalCurve: Codable, Equatable, Sendable {
    public let source: Curve3D
    public let origin: Point3D
    public let horizontal: Vector3D
    public let vertical: Vector3D
    public let normal: Vector3D
    public let occurrenceID: SceneOccurrenceID
    public let sceneNodeID: SceneNodeID
    public let sourceSceneNodeID: SceneNodeID
    public let featureID: FeatureID
    public let bodyID: BodyID
    public let faceID: FaceID
    public let loopID: LoopID
    public let edgeID: EdgeID
    public let startParameter: Double
    public let endParameter: Double
    public let maximumProjectedDeviationMeters: Double

    init(use: DrawingOccurrenceProjectedUse, maximumDeviation: Double) {
        source = use.curve.source
        let frame = use.curve.frame
        origin = frame.origin; horizontal = frame.horizontal; vertical = frame.vertical; normal = frame.normal
        occurrenceID = use.occurrenceID; sceneNodeID = use.sceneNodeID; sourceSceneNodeID = use.sourceSceneNodeID
        featureID = use.featureID; bodyID = use.original.bodyID; faceID = use.original.faceID
        loopID = use.original.loopID; edgeID = use.original.edge.edgeID
        startParameter = use.startParameter; endParameter = use.endParameter
        maximumProjectedDeviationMeters = maximumDeviation
    }
}
