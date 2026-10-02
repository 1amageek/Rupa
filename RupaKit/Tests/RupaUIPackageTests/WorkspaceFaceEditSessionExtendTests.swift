import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

/// Extend Sheet's dialog offers the shapes Plasticity offers for the sheet: a planar sheet Linear,
/// Soft and Reflective from Linear, a curved one Natural too, from Natural, without Modify while
/// Natural extends the surface itself.
@Suite("Face edit session extend")
struct WorkspaceFaceEditSessionExtendTests {
    @Test func aPlanarSheetOffersTheStraightShapesFromLinear() throws {
        let edge = SelectionTarget(sceneNodeID: SceneNodeID())
        var session = WorkspaceFaceEditSession(extendingPlanarSheetEdges: [edge], limit: nil)
        #expect(session.extensionShape == .linear && session.extensionShapes.contains(.natural) == false)
        #expect(session.offersModify)
        // The distance opens at 0, and Tab never reaches Natural.
        #expect(session.missingInput == "Extend Sheet: set the Distance." && session.commands().isEmpty)
        for _ in 0..<6 {
            session.stepGrow()
            #expect(session.extensionShape != .natural)
        }
    }

    @Test func aCurvedSheetOpensOnNaturalWithoutModify() throws {
        let edge = SelectionTarget(sceneNodeID: SceneNodeID())
        var session = WorkspaceFaceEditSession(kind: .extendSheet(edges: [edge], limit: nil))
        #expect(session.extensionShape == .natural && session.extensionShapes == SheetExtensionShape.allCases)
        #expect(session.offersModify == false)
        session.modifies = false
        session.distanceMeters = 0.01
        // Natural extends the sheet's own surface, so the extension joins it.
        guard case let .extendSheet(_, _, shape, modifies, _, _)? = session.commands().first else {
            Issue.record("Expected an extension.")
            return
        }
        #expect(shape == .natural && modifies)
    }
}
