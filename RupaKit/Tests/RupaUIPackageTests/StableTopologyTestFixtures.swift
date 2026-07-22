import RupaCore
import SwiftCAD

func workspaceTestFaceComponent(role: String) throws -> SelectionComponentID {
    try .stableTopology(StableSubshapeReference(
        subshapeID: SubshapeID(featureID: FeatureID(), role: role, ordinal: 0),
        geometrySignature: .face(FaceGeometrySignature(
            surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            orientation: .forward,
            loops: []
        ))
    ))
}

func workspaceTestEdgeComponent(role: String) throws -> SelectionComponentID {
    try .stableTopology(StableSubshapeReference(
        subshapeID: SubshapeID(featureID: FeatureID(), role: role, ordinal: 0),
        geometrySignature: .edge(CurveSpanGeometrySignature(
            curve: .line(Line3D(origin: .origin, direction: .unitX)),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: .origin,
            endPoint: Point3D(x: 1.0, y: 0.0, z: 0.0)
        ))
    ))
}

func workspaceTestVertexComponent(role: String) throws -> SelectionComponentID {
    try .stableTopology(StableSubshapeReference(
        subshapeID: SubshapeID(featureID: FeatureID(), role: role, ordinal: 0),
        geometrySignature: .vertex(point: .origin)
    ))
}
