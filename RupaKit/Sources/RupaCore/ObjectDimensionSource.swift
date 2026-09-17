import Foundation
import SwiftCAD

package struct ObjectDimensionSource: Equatable, Sendable {
    enum Shape: String, Equatable, Sendable {
        case box
        case cylinder
    }

    var target: SelectionTarget
    package var featureID: FeatureID
    var sceneNodeID: SceneNodeID
    var shape: Shape
    package var sizeX: Double
    package var sizeY: Double
    package var sizeZ: Double
    package var radius: Double?
    var radiusExpression: CADExpression?
    var depthExpression: CADExpression
}
