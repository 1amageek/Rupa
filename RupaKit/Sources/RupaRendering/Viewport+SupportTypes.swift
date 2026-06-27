import Foundation
import RupaCore
import SwiftUI
import RupaViewportScene

enum TransformHandleStyle {
    case vertex
    case faceCenter
    case axisEndScale(ViewportCoordinateAxis)
    case axisCenterScale(ViewportCoordinateAxis)
}

enum ViewportTheme {
    static let background = Color(red: 0.105, green: 0.112, blue: 0.118)
    static let gridMinor = Color.white.opacity(0.055)
    static let gridMajor = Color.white.opacity(0.135)
    static let bodySurface = Color(red: 0.62, green: 0.64, blue: 0.62)
    static let selection = Color(red: 0.14, green: 0.66, blue: 0.95)
    static let hover = Color(red: 0.24, green: 0.88, blue: 0.82)
    static let sketch = Color(red: 0.34, green: 0.62, blue: 1.0)
    static let dimensionLabelBackground = Color(red: 0.08, green: 0.09, blue: 0.10).opacity(0.90)
    static let dimensionLabelBackgroundHighlighted = Color(red: 0.11, green: 0.18, blue: 0.21).opacity(0.96)
    static let dimensionText = Color(red: 0.88, green: 0.94, blue: 0.98)
    static let surfaceContinuityDisconnected = Color(red: 0.95, green: 0.22, blue: 0.18)
    static let surfaceContinuityPosition = Color(red: 0.97, green: 0.60, blue: 0.16)
    static let surfaceContinuityTangent = Color(red: 0.26, green: 0.82, blue: 0.47)
    static let surfaceContinuityCurvature = Color(red: 0.27, green: 0.73, blue: 1.0)
    static let surfaceContinuitySolveRequired = Color(red: 0.98, green: 0.78, blue: 0.18)
    static let surfaceAnalysisU = Color(red: 0.28, green: 0.86, blue: 0.64)
    static let surfaceAnalysisV = Color(red: 0.95, green: 0.46, blue: 0.78)
    static let surfaceAnalysisPrincipalMinimum = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let surfaceAnalysisPrincipalMaximum = Color(red: 0.34, green: 0.68, blue: 1.0)
    static let surfaceAnalysisBoundaryOuter = Color(red: 1.0, green: 0.82, blue: 0.24)
    static let surfaceAnalysisBoundaryInner = Color(red: 0.95, green: 0.36, blue: 0.76)
    static let surfaceEdit = Color(red: 1.0, green: 0.78, blue: 0.28)
}

struct ViewportFaceSelectionTarget: Hashable {
    var featureID: FeatureID
    var face: ViewportBodyFace
}

struct ViewportEdgeSelectionTarget: Hashable {
    var featureID: FeatureID
    var edge: ViewportBodyEdge
    var target: SelectionTarget
}

struct ViewportVertexSelectionTarget: Hashable {
    var featureID: FeatureID
    var vertex: ViewportBodyVertex
}

struct ViewportSketchRegionSelectionTarget: Hashable {
    var featureID: FeatureID
    var componentID: SelectionComponentID
    var target: SelectionTarget
}

struct ViewportSlotWidthSourceTarget: Hashable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
}

struct ViewportSketchVertexOffsetSourceTarget: Hashable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var handle: SketchEntityPointHandle
    var target: SelectionTarget
}

struct ViewportFaceAccessibilityMarker: Identifiable {
    var id: String
    var face: ViewportBodyFace
    var hit: ViewportHit
    var point: CGPoint
    var modelPoint: Point2D
    var sketchPlane: SketchPlane
}

struct ViewportEdgeAccessibilityMarker: Identifiable {
    var id: String
    var edge: ViewportBodyEdge
    var hit: ViewportHit
    var point: CGPoint
    var modelPoint: Point2D
    var sketchPlane: SketchPlane
}

enum ViewportFaceHighlightStyle {
    case selected
    case hovered

    var color: Color {
        switch self {
        case .selected:
            return ViewportTheme.selection
        case .hovered:
            return ViewportTheme.hover
        }
    }

    var fillOpacity: Double {
        switch self {
        case .selected:
            return 0.30
        case .hovered:
            return 0.18
        }
    }

    var strokeOpacity: Double {
        switch self {
        case .selected:
            return 0.96
        case .hovered:
            return 0.76
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .selected:
            return 2.8
        case .hovered:
            return 2.0
        }
    }
}

extension ViewportBodyFace {
    static var editableCases: [ViewportBodyFace] {
        [.front, .back, .top, .bottom, .left, .right]
    }
}
