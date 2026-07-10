import SwiftCAD
import RupaCoreTypes

extension WorkspaceState {
    mutating func setCurveCurvatureDisplay(
        target: SelectionTarget,
        isVisible: Bool?,
        combScale: Double?,
        document: DesignDocument
    ) throws {
        let componentID = try DesignDisplayComponentResolver().curveCurvatureComponentID(
            for: target,
            in: document
        )
        let existing = curveCurvatureDisplays[componentID]
        let shouldShow = isVisible ?? (existing == nil)
        if shouldShow {
            let display = CurveCurvatureDisplay(
                componentID: componentID,
                combScale: combScale ?? existing?.combScale ?? CurveCurvatureDisplay.defaultCombScale
            )
            try display.validate(against: document.cadDocument)
            curveCurvatureDisplays[componentID] = display
        } else {
            curveCurvatureDisplays.removeValue(forKey: componentID)
        }
    }

    mutating func setPointDisplay(
        target: SelectionTarget,
        isVisible: Bool?,
        document: DesignDocument
    ) throws {
        let componentID = try DesignDisplayComponentResolver().pointComponentID(
            for: target,
            in: document
        )
        let existing = pointDisplays[componentID]
        let nextVisibility = isVisible ?? !(existing?.isVisible ?? true)
        let display = PointDisplay(componentID: componentID, isVisible: nextVisibility)
        try display.validate(against: document.cadDocument)
        pointDisplays[componentID] = display
    }

    mutating func setSurfaceControlPointDisplay(
        target: SelectionReference,
        isVisible: Bool?,
        document: DesignDocument
    ) throws {
        let displayID = try SurfaceControlPointDisplayID(selectionReference: target)
        let existing = surfaceControlPointDisplays[displayID]
        let nextVisibility = isVisible ?? !(existing?.isVisible ?? false)
        let display = try SurfaceControlPointDisplay(
            target: target,
            isVisible: nextVisibility
        )
        try display.validate(against: document.cadDocument)
        surfaceControlPointDisplays[displayID] = display
    }

    mutating func setSurfaceFrameDisplay(
        query: SurfaceFrameQuery,
        isVisible: Bool?,
        document: DesignDocument
    ) throws {
        let displayID = try SurfaceFrameDisplayID(query: query)
        let existing = surfaceFrameDisplays[displayID]
        let nextVisibility = isVisible ?? !(existing?.isVisible ?? false)
        guard nextVisibility else {
            surfaceFrameDisplays.removeValue(forKey: displayID)
            return
        }
        _ = try SurfaceFrameService().resolveFrames(document: document, queries: [query])
        let display = try SurfaceFrameDisplay(query: query, isVisible: true)
        try display.validate()
        surfaceFrameDisplays[displayID] = display
    }
}
