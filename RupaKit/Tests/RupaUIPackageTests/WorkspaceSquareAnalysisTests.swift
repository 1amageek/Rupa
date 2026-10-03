import Testing
import RupaCore
import RupaRendering
import SwiftCAD
@testable import RupaUI

/// Square's Analysis labels: each side's value at the checked continuity, ✓ within its limit, ⊘
/// beyond it, ⚠ where the side asks for less than the check; a side beside no face is checked at G0.
@Suite("Square analysis labels")
struct WorkspaceSquareAnalysisTests {
    private let analysis = WorkspaceSquareAnalysis(sides: [
        // A G2 side beside a face, within every limit.
        .init(analysis: SquareSideAnalysis(side: 0, position: 0, positionLimit: 1e-6, angle: 0, angleLimit: 1e-6,
                                           curvature: 0, curvatureLimit: 1e-3, point: Point3D(x: 1, y: 0, z: 0)), order: 2),
        // A G1 side whose angle runs past its allowance.
        .init(analysis: SquareSideAnalysis(side: 1, position: 0, positionLimit: 1e-6, angle: 0.1, angleLimit: 1e-6,
                                           point: Point3D(x: 2, y: 0, z: 0)), order: 1),
        // A Free curve side 1.5 mm off its curve.
        .init(analysis: SquareSideAnalysis(side: 2, position: 0.0015, positionLimit: 1e-6, point: Point3D(x: 3, y: 0, z: 0)), order: nil),
    ])

    @Test func eachSideIsJudgedAtTheCheckedContinuity() {
        let g2 = analysis.drawn(level: 2, displayUnit: .millimeter)
        #expect(g2.map(\.verdict) == [.within, .unconstrained, .unconstrained])
        #expect(g2[0].text.hasPrefix("G2 ✓"))
        #expect(g2[1].text.hasPrefix("G1 ⚠"))
        #expect(g2[2].text.hasPrefix("G0 ⚠"))
        #expect(g2.map(\.anchor) == [Point3D(x: 1, y: 0, z: 0), Point3D(x: 2, y: 0, z: 0), Point3D(x: 3, y: 0, z: 0)])
        let g1 = analysis.drawn(level: 1, displayUnit: .millimeter)
        #expect(g1.map(\.verdict) == [.within, .beyond, .unconstrained])
        #expect(g1[1].text.hasPrefix("G1 ⊘"))
        let g0 = analysis.drawn(level: 0, displayUnit: .millimeter)
        #expect(g0.map(\.verdict) == [.within, .within, .unconstrained])
        #expect(g0[2].text.hasPrefix("G0 ⚠ 1.5"))
    }
}
