import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// A saved measurement is not copied as an empty annotation node; copying it is refused.
@Suite struct SceneCopyMeasurementRefusalTests {
    @Test func aSavedMeasurementAndItsGroupAreRefusedWhileOtherObjectsCopy() throws {
        var document = DesignDocument.empty()
        let box = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
        let measurementID = try document.addMeasurementAnnotation(MeasurementAnnotation(
            name: "Gap", kind: .distance,
            anchors: [
                .worldPoint(Point3D(x: 0, y: 0, z: 0), role: .start),
                .worldPoint(Point3D(x: 0.1, y: 0, z: 0), role: .end),
            ]
        ))
        let metadata = document.productMetadata
        let annotationNode = try #require(metadata.measurements[measurementID]?.sceneNodeID)
        let group = try #require(metadata.sceneNodes.values.first { $0.childIDs.contains(annotationNode) }).id
        let boxNode = try #require(metadata.sceneNodes.values.first { $0.reference?.featureID == box }).id

        #expect(metadata.sceneCopyRefusal(for: [annotationNode]) != nil)
        #expect(metadata.sceneCopyRefusal(for: [group]) != nil, "The Measurements group carries the measurement too.")
        #expect(metadata.sceneCopyRefusal(for: [boxNode]) == nil)
        #expect(throws: EditorError.self) { try document.duplicateSceneNodes(ids: [annotationNode]) }
    }
}
