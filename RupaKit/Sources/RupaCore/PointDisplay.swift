import Foundation
import SwiftCAD

public struct PointDisplay: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable {
        case visible
        case hidden
    }

    public var componentID: SelectionComponentID
    public var mode: Mode

    public var isVisible: Bool {
        mode == .visible
    }

    public init(
        componentID: SelectionComponentID,
        mode: Mode
    ) {
        self.componentID = componentID
        self.mode = mode
    }

    public init(
        componentID: SelectionComponentID,
        isVisible: Bool
    ) {
        self.init(componentID: componentID, mode: isVisible ? .visible : .hidden)
    }

    public func validate(against cadDocument: CADDocument) throws {
        guard let reference = componentID.sketchEntityReference,
              let feature = cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID] else {
            throw DocumentValidationError.invalidProductMetadata(
                "Point displays must point to existing source sketch entities."
            )
        }
        switch entity {
        case .line,
             .circle,
             .arc,
             .spline:
            return
        case .point:
            throw DocumentValidationError.invalidProductMetadata(
                "Point displays require source curve entities, not standalone points."
            )
        }
    }
}
