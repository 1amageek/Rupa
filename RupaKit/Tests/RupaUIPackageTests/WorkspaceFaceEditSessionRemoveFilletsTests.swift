import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

/// Remove Fillets' Max radius applies only while its checkbox is on, as Plasticity's does.
@Suite("Face edit session remove fillets")
struct WorkspaceFaceEditSessionRemoveFilletsTests {
    @Test func theMaximumRadiusAppliesOnlyWhileChecked() throws {
        var session = WorkspaceFaceEditSession(kind: .removeFillets(object: SceneNodeID()))
        #expect(session.limitsRadius == false)
        session.maximumRadiusMeters = 0.003
        guard case let .removeFillets(_, unlimited, _)? = session.commands().first else {
            Issue.record("Expected Remove Fillets.")
            return
        }
        #expect(unlimited == nil)
        session.limitsRadius = true
        guard case let .removeFillets(_, limited, _)? = session.commands().first else {
            Issue.record("Expected Remove Fillets.")
            return
        }
        #expect(limited == .length(0.003, .meter))
    }

    @Test func polySplinesConvertsTheMeshAndRemovesItWithPlasticitysDefaults() throws {
        let object = SceneNodeID()
        let mesh = Mesh(positions: [], indices: [])
        let session = WorkspaceFaceEditSession(kind: .polySplines(object: object, mesh: mesh))
        let commands = session.commands()
        guard commands.count == 2, case let .createPolySplineSurface(_, _, options) = commands[0],
              case let .deleteSceneNodes(ids) = commands[1] else {
            Issue.record("Expected the conversion and the mesh's removal.")
            return
        }
        #expect(options.roundedCorners == false && options.mergePatches && options.interpolateBoundaryExactly == false)
        #expect(ids == [object])
    }
}
