import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Section Analysis sectioning at a selected face and highlighting bodies that interfere.
@Suite struct SectionAnalysisCommandTests {
    /// Boxes 0.1 m across, the second moved along X by `offsets`.
    private func boxes(offsets: [Double]) throws -> (DesignDocument, [SceneNodeID]) {
        var document = DesignDocument.empty()
        var nodes: [SceneNodeID] = []
        for (index, offset) in ([0.0] + offsets).enumerated() {
            let featureID = try document.createExtrudedRectangle(
                name: "Box \(index)", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
                depth: .length(0.1, .meter), direction: .normal
            )
            let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID }).id
            if offset != 0 {
                try document.transformSceneNodes(ids: [node], worldDelta: try .translation(Vector3D(x: offset, y: 0, z: 0)))
            }
            nodes.append(node)
        }
        return (document, nodes)
    }

    private func midSection(of document: DesignDocument) throws -> SectionAnalysisResult {
        let result = try SectionAnalysisService().analyze(
            document: document,
            query: SectionAnalysisQuery(source: .sketchPlane(.xy), offsetMeters: 0.05),
            activeConstructionPlaneID: nil,
            displayUnit: .millimeter
        )
        #expect(result.bodies.allSatisfy { $0.classification == .intersects }, "The mid plane cuts every box.")
        return result
    }

    @Test func aSelectedFaceSectionsAtThatFaceOfTheMovedObject() throws {
        let (document, nodes) = try boxes(offsets: [0.5])
        let topology = try TopologySnapshotService().snapshot(document: document)
        let top = try #require(topology.entries.first { entry in
            guard entry.kind == .face, entry.sceneNodeID == nodes[1].description, let normal = entry.normal else { return false }
            return normal.z > 0.99
        })
        let target = try #require(top.selectionTarget())
        let topZ = try #require(top.center?.z)

        let result = try SectionAnalysisService().analyze(
            document: document,
            query: SectionAnalysisQuery(source: .face(target), offsetMeters: -0.03),
            activeConstructionPlaneID: nil,
            displayUnit: .millimeter
        )
        #expect(result.plane.sourceKind == .face)
        #expect(abs(result.plane.normal.z - 1) < 1e-9, "The plane faces out of the body.")
        #expect(abs(result.plane.origin.z - (topZ - 0.03)) < 1e-9)
        #expect(abs(result.plane.origin.x - ((top.center?.x ?? 0) + 0.5)) < 1e-9, "The plane sits at the moved occurrence.")
        let areas = result.intersectionContours.filter(\.isClosed).map { abs($0.signedAreaSquareMeters) }
        #expect(areas.count == 2)
        #expect(areas.allSatisfy { abs($0 - 0.01) < 1e-9 })

        #expect(throws: EditorError.self, "A whole object is not a face to section at.") {
            _ = try SectionAnalysisService().analyze(
                document: document,
                query: SectionAnalysisQuery(source: .face(SelectionTarget(sceneNodeID: nodes[1]))),
                activeConstructionPlaneID: nil,
                displayUnit: .millimeter
            )
        }
    }

    @Test func overlappingBodiesInterfereWhileTouchingAndSeparateOnesDoNot() throws {
        let overlapping = try midSection(of: try boxes(offsets: [0.05]).0)
        #expect(overlapping.interferences.count == 1)
        let contourIDs = Set(overlapping.intersectionContours.filter(\.isClosed).map(\.id))
        #expect(overlapping.interferingContourIDs == contourIDs)

        let inside = try midSection(of: try boxes(offsets: [0.0]).0)
        #expect(inside.interferences.count == 1, "Coincident copies occupy the same space.")

        #expect(try midSection(of: try boxes(offsets: [0.1]).0).interferences.isEmpty)
        #expect(try midSection(of: try boxes(offsets: [0.3]).0).interferences.isEmpty)
    }

    @Test func resultsSavedBeforeInterferenceDecodeWithNone() throws {
        let result = try midSection(of: try boxes(offsets: [0.05]).0)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        #expect(object["interferences"] != nil)
        object.removeValue(forKey: "interferences")
        let decoded = try JSONDecoder().decode(SectionAnalysisResult.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.interferences.isEmpty)
        #expect(decoded.intersectionContours == result.intersectionContours)
    }
}
