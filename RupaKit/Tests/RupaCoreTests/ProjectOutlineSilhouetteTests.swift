import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Project Outline keeps the silhouette: edges inside the body's shadow are left out, and edges
/// of any curve kind on it are projected.
@MainActor
@Suite struct ProjectOutlineSilhouetteTests {
    private func bodyNode(_ document: DesignDocument, _ featureID: FeatureID) throws -> SceneNodeID {
        try #require(document.productMetadata.sceneNodes.first { $0.value.reference == .body(featureID) }?.key)
    }

    private func outline(_ document: DesignDocument, _ featureID: FeatureID) throws -> Sketch {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The outline sketch is missing.")
        }
        return sketch
    }

    /// Seen along a diagonal, a box's outline is a hexagon: the three edges at the nearest corner
    /// and the three at the farthest lie inside it.
    @Test func aBoxSeenAlongADiagonalOutlinesAHexagon() throws {
        var document = DesignDocument.empty()
        let boxID = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(10, .millimeter), height: .length(10, .millimeter),
            depth: .length(10, .millimeter), direction: .normal
        )
        let plane = SketchPlane.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: -0.05), normal: Vector3D(x: 1, y: 1, z: 1) * (1 / 3.0.squareRoot())))
        let outlineID = try document.projectBodyOutlinesToConstructionPlane(
            targets: [SelectionTarget(sceneNodeID: try bodyNode(document, boxID))], plane: plane
        )
        let entities = try outline(document, outlineID).entities.values
        #expect(entities.count == 6)
        #expect(entities.allSatisfy { if case .line = $0 { true } else { false } })
    }

    /// A smooth loft's lateral edges are B-splines: its side outline projects them.
    @Test func bSplineEdgesOnTheOutlineAreProjected() throws {
        var document = DesignDocument.empty()
        var sections: [LoftSectionReference] = []
        for (index, (x, z)) in [(0.0, 0.0), (3.0, 5.0), (0.0, 10.0)].enumerated() {
            let width = index == 1 ? 5.0 : 4.0
            let plane: SketchPlane = (x == 0 && z == 0)
                ? .xy
                : .plane(Plane3D(origin: Point3D(x: x / 1000, y: 0, z: z / 1000), normal: .unitZ))
            let profile = try document.createRectangleSketch(
                name: "Section \(index)", plane: plane,
                width: .length(width, .millimeter), height: .length(width / 2, .millimeter)
            )
            sections.append(LoftSectionReference(profile: ProfileReference(featureID: profile)))
        }
        let loftID = try document.createLoft(
            name: "Loft", sections: sections, options: LoftOptions(resultKind: .solid, surfaceMode: .smooth)
        )
        let outlineID = try document.projectBodyOutlinesToConstructionPlane(
            targets: [SelectionTarget(sceneNodeID: try bodyNode(document, loftID))], plane: .zx
        )
        let entities = try outline(document, outlineID).entities.values
        #expect(entities.contains { if case .spline = $0 { true } else { false } })
    }
}
