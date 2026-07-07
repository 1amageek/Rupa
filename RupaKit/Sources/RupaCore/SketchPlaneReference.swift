import Foundation
import SwiftCAD

public enum SketchPlaneReference: Equatable, Hashable, Sendable {
    case active
    case sketchPlane(SketchPlane)
    case constructionPlane(ConstructionPlaneSourceID)
}

extension SketchPlaneReference: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case sketchPlane
        case constructionPlaneID
    }

    private enum Kind: String, Codable {
        case active
        case sketchPlane
        case constructionPlane
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .active:
            self = .active
        case .sketchPlane:
            self = .sketchPlane(try container.decode(SketchPlane.self, forKey: .sketchPlane))
        case .constructionPlane:
            self = .constructionPlane(
                try container.decode(ConstructionPlaneSourceID.self, forKey: .constructionPlaneID)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .active:
            try container.encode(Kind.active, forKey: .kind)
        case .sketchPlane(let plane):
            try container.encode(Kind.sketchPlane, forKey: .kind)
            try container.encode(plane, forKey: .sketchPlane)
        case .constructionPlane(let id):
            try container.encode(Kind.constructionPlane, forKey: .kind)
            try container.encode(id, forKey: .constructionPlaneID)
        }
    }
}

public extension SketchPlaneReference {
    static let xy = SketchPlaneReference.sketchPlane(.xy)
    static let yz = SketchPlaneReference.sketchPlane(.yz)
    static let zx = SketchPlaneReference.sketchPlane(.zx)

    init(sketchPlane: SketchPlane) {
        self = .sketchPlane(sketchPlane)
    }
}

public extension DesignDocument {
    func resolveSketchPlane(
        _ reference: SketchPlaneReference?,
        fallback: SketchPlane = .xy
    ) throws -> SketchPlane {
        let plane: SketchPlane
        switch reference {
        case nil, .some(.active):
            plane = activeConstructionPlane?.plane ?? fallback
        case .some(.sketchPlane(let explicitPlane)):
            plane = explicitPlane
        case .some(.constructionPlane(let id)):
            guard let source = productMetadata.constructionPlanes[id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Sketch plane reference requires an existing construction plane source."
                )
            }
            plane = source.plane
        }
        try ConstructionPlaneSource.validatePlane(plane)
        return plane
    }
}
