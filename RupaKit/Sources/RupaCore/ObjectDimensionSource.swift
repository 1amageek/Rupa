import Foundation
import SwiftCAD

struct ObjectDimensionSource: Equatable, Sendable {
    enum Shape: String, Equatable, Sendable {
        case box
        case cylinder
    }

    var target: SelectionTarget
    var featureID: FeatureID
    var sceneNodeID: SceneNodeID
    var shape: Shape
    var sizeX: Double
    var sizeY: Double
    var sizeZ: Double
    var radius: Double?
    var radiusExpression: CADExpression?
    var depthExpression: CADExpression
}
