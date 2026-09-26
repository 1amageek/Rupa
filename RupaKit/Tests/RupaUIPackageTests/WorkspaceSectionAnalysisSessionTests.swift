import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// Section Analysis's plane sources, distance and flip, and the fixed slice a confirmation leaves.
@Suite struct WorkspaceSectionAnalysisSessionTests {
    private let face = SelectionTarget(sceneNodeID: SceneNodeID(), component: .face(SelectionComponentID(rawValue: "face")))

    @Test func theSelectedFaceIsTheDefaultPlaneAndOtherwiseTheConstructionPlane() throws {
        let withFace = WorkspaceSectionAnalysisSession(selectedFace: face, previousPlane: nil)
        #expect(withFace.planeSource == .selection)
        #expect(withFace.query(constructionPlane: .xy).source == .face(face))

        var plain = WorkspaceSectionAnalysisSession(selectedFace: nil, previousPlane: nil)
        #expect(plain.planeSource == .constructionPlane)
        #expect(plain.query(constructionPlane: .yz).source == .sketchPlane(.yz))
        #expect(throws: EditorError.self) { try plain.choose(.selection) }
        #expect(throws: EditorError.self) { try plain.choose(.previous) }
        #expect(plain.planeSource == .constructionPlane)
    }

    @Test func distanceAndFlipShapeTheQueryAndPreviousRestoresThePlacedPlane() throws {
        let placed = SketchPlane.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.2), normal: .unitX))
        var section = WorkspaceSectionAnalysisSession(selectedFace: nil, previousPlane: placed)
        section.distanceMeters = 0.03
        section.toggleFlip()
        let query = section.query(constructionPlane: .xy)
        #expect(query.offsetMeters == 0.03)
        #expect(query.flipsNormal)
        #expect(query.clipping?.retainedSide == .behind)

        try section.choose(.previous)
        #expect(section.distanceMeters == 0, "Choosing a plane starts the distance and direction over.")
        #expect(!section.flipsNormal)
        #expect(section.query(constructionPlane: .xy).source == .sketchPlane(placed))
    }
}
