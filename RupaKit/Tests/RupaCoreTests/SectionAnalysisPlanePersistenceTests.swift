import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Section Analysis's Previous plane is kept with the document.
@Suite struct SectionAnalysisPlanePersistenceTests {
    @Test func thePlaneSurvivesEncodingAndOlderDocumentsHaveNone() throws {
        var document = DesignDocument.empty()
        let plane = SketchPlane.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.2), normal: .unitX))
        try document.setSectionAnalysisPlane(plane)
        let data = try JSONEncoder().encode(document.productMetadata)
        let decoded = try JSONDecoder().decode(ProductMetadata.self, from: data)
        #expect(decoded.sectionAnalysisPlane == plane)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "sectionAnalysisPlane")
        let older = try JSONDecoder().decode(ProductMetadata.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.sectionAnalysisPlane == nil)

        try document.setSectionAnalysisPlane(nil)
        #expect(document.productMetadata.sectionAnalysisPlane == nil)
    }

    @Test @MainActor func settingThePlaneIsAnUndoableSourceCommand() throws {
        let session = EditorSession()
        let plane = SketchPlane.xy
        _ = try session.execute(.setSectionAnalysisPlane(plane))
        #expect(session.document.productMetadata.sectionAnalysisPlane == plane)
        _ = try session.undo()
        #expect(session.document.productMetadata.sectionAnalysisPlane == nil)
    }
}
