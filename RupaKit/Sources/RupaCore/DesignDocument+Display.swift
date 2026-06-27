import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func setCurveCurvatureDisplay(
        target: SelectionTarget,
        isVisible: Bool? = nil,
        combScale: Double? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let componentID = try DesignDisplayComponentResolver().curveCurvatureComponentID(
            for: target,
            in: self
        )
        let existing = productMetadata.curveCurvatureDisplays[componentID]
        let shouldShow = isVisible ?? (existing == nil)
        if shouldShow {
            let display = CurveCurvatureDisplay(
                componentID: componentID,
                combScale: combScale ?? existing?.combScale ?? CurveCurvatureDisplay.defaultCombScale
            )
            try display.validate(against: cadDocument)
            productMetadata.curveCurvatureDisplays[componentID] = display
        } else {
            productMetadata.curveCurvatureDisplays.removeValue(forKey: componentID)
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setPointDisplay(
        target: SelectionTarget,
        isVisible: Bool? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let componentID = try DesignDisplayComponentResolver().pointComponentID(
            for: target,
            in: self
        )
        let existing = productMetadata.pointDisplays[componentID]
        let nextVisibility: Bool
        if let isVisible {
            nextVisibility = isVisible
        } else if let existing {
            nextVisibility = !existing.isVisible
        } else {
            nextVisibility = false
        }
        let display = PointDisplay(componentID: componentID, isVisible: nextVisibility)
        try display.validate(against: cadDocument)
        productMetadata.pointDisplays[componentID] = display
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setSurfaceControlPointDisplay(
        target: SelectionReference,
        isVisible: Bool? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let displayID = try SurfaceControlPointDisplayID(selectionReference: target)
        let existing = productMetadata.surfaceControlPointDisplays[displayID]
        let nextVisibility: Bool
        if let isVisible {
            nextVisibility = isVisible
        } else if let existing {
            nextVisibility = !existing.isVisible
        } else {
            nextVisibility = true
        }
        let display = try SurfaceControlPointDisplay(target: target, isVisible: nextVisibility)
        try display.validate(against: cadDocument)
        productMetadata.surfaceControlPointDisplays[displayID] = display
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setSurfaceFrameDisplay(
        query: SurfaceFrameQuery,
        isVisible: Bool? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let displayID = try SurfaceFrameDisplayID(query: query)
        let existing = productMetadata.surfaceFrameDisplays[displayID]
        let nextVisibility: Bool
        if let isVisible {
            nextVisibility = isVisible
        } else if let existing {
            nextVisibility = !existing.isVisible
        } else {
            nextVisibility = true
        }
        guard nextVisibility else {
            productMetadata.surfaceFrameDisplays.removeValue(forKey: displayID)
            try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
            return
        }
        _ = try SurfaceFrameService().resolve(
            document: self,
            queries: [query]
        )
        let display = try SurfaceFrameDisplay(query: query, isVisible: nextVisibility)
        try display.validate()
        productMetadata.surfaceFrameDisplays[displayID] = display
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }
}
