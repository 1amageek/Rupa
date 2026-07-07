import ArgumentParser
import Foundation
import RupaCore

enum CLISketchPlaneReferenceParser {
    static func reference(
        plane: CLISketchPlane?,
        constructionPlaneID: String?
    ) throws -> SketchPlaneReference? {
        guard !(plane != nil && constructionPlaneID != nil) else {
            throw ValidationError("--plane and --construction-plane-id cannot be combined.")
        }
        if let plane {
            return .sketchPlane(plane.sketchPlane)
        }
        guard let constructionPlaneID else {
            return nil
        }
        guard let uuid = UUID(uuidString: constructionPlaneID) else {
            throw ValidationError("--construction-plane-id must be a UUID.")
        }
        return .constructionPlane(ConstructionPlaneSourceID(uuid))
    }
}
