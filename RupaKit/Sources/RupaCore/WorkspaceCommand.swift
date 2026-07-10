import SwiftCAD
import RupaCoreTypes

public enum WorkspaceCommand: Sendable {
    case setDisplayUnit(LengthDisplayUnit)
    case setRulerConfiguration(RulerConfiguration)
    case setViewportGridSettings(ViewportGridSettings)
    case setActiveConstructionPlane(ConstructionPlaneSourceID?)
    case setCurveCurvatureDisplay(
        target: SelectionTarget,
        isVisible: Bool?,
        combScale: Double?
    )
    case setPointDisplay(target: SelectionTarget, isVisible: Bool?)
    case setSurfaceControlPointDisplay(
        target: SelectionReference,
        isVisible: Bool?
    )
    case setSurfaceFrameDisplay(query: SurfaceFrameQuery, isVisible: Bool?)

    public var name: String {
        switch self {
        case .setDisplayUnit:
            "setDisplayUnit"
        case .setRulerConfiguration:
            "setRulerConfiguration"
        case .setViewportGridSettings:
            "setViewportGridSettings"
        case .setActiveConstructionPlane:
            "setActiveConstructionPlane"
        case .setCurveCurvatureDisplay:
            "setCurveCurvatureDisplay"
        case .setPointDisplay:
            "setPointDisplay"
        case .setSurfaceControlPointDisplay:
            "setSurfaceControlPointDisplay"
        case .setSurfaceFrameDisplay:
            "setSurfaceFrameDisplay"
        }
    }
}
