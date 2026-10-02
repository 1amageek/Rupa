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
}
