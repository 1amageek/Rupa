import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func viewportSceneBuilderBuildsRevolvedCircleWithinTheAgentReadBudget() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createCircleSketch(
        name: "Viewport Torus Profile",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.72, .meter),
            y: .length(0.0, .meter)
        ),
        radius: .length(0.04, .meter)
    )
    let revolveID = try document.createRevolve(
        name: "Viewport Torus",
        profile: ProfileReference(featureID: profileID),
        axis: RevolveAxis(origin: .origin, direction: .unitY)
    )

    let start = ContinuousClock.now
    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .meter)
    )
    let elapsed = start.duration(to: ContinuousClock.now).components
    let elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1.0e18

    #expect(elapsedSeconds < 15.0)
    #expect(scene.items.contains { $0.featureID == revolveID })
    #expect(scene.items.allSatisfy { item in
        guard case .body(let component) = item.kind else {
            return true
        }
        return component.surfaceKnotDisplays.isEmpty
            && component.surfaceSpanDisplays.isEmpty
    })
}
