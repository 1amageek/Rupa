import Foundation
import Testing
import RupaCore
import RupaRendering
import SwiftCAD
@testable import RupaUI

/// Align Surface's Analysis on a previewed alignment: the edges the preview adds measured on its
/// evaluation, labelled within or beyond their limits, and drawn as gaps, turns or combs at scale.
@Suite("Workspace align analysis")
struct WorkspaceAlignAnalysisTests {
    /// A flat sheet aligned to an arch z = x(1 − x/0.1) at its x = 0.1 edge (slope −1 there, bending
    /// by 20/2^{3/2} m⁻¹ across), before and after.
    private func aligned(_ continuity: SurfaceContinuityLevel) throws -> (base: DesignDocument, preview: DesignDocument) {
        let session = EditorSession()
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: 0.05, y: y, z: 0.05), Point3D(x: 0.1, y: y, z: 0)] }
        _ = try session.execute(.createBSplineSurface(name: "Arch", surface: BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(0.1)]
        )))
        _ = try session.execute(.createBSplineSurface(name: "Flat", surface: .bilinearPatch(
            bottomLeft: Point3D(x: 0.12, y: 0, z: 0), bottomRight: Point3D(x: 0.2, y: 0, z: 0),
            topRight: Point3D(x: 0.2, y: 0.1, z: 0), topLeft: Point3D(x: 0.12, y: 0.1, z: 0))))
        let nodes = session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }
        let arch = try #require(nodes.first { $0.name.hasPrefix("Arch") }).id
        let flat = try #require(nodes.first { $0.name.hasPrefix("Flat") }).id
        func edge(atX x: Double, of node: SceneNodeID) throws -> SelectionTarget {
            try #require(try TopologySnapshotService().snapshot(document: session.document).entries.first {
                $0.kind == .edge && $0.sceneNodeID == node.description
                    && abs(($0.start?.x ?? -1) - x) < 1e-9 && abs(($0.end?.x ?? -1) - x) < 1e-9
            }?.selectionTarget())
        }
        let base = session.document
        _ = try session.execute(.alignSurface(targets: [try edge(atX: 0.12, of: flat), try edge(atX: 0.1, of: arch)],
                                              continuity: continuity, tension: 1, blendRows: 1))
        return (base, session.document)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCurvatureAlignmentIsWithinEveryMeasureAndCombsMatch() throws {
        let (base, preview) = try aligned(.curvature)
        let analysis = try #require(try WorkspaceAlignAnalysis.evaluate(preview: preview, base: base, current: nil))
        #expect(analysis.edges.count == 1 && analysis.edges[0].samples.count == 32)
        for measure in ViewportEdgeAlignmentAnalysis.Measure.allCases {
            let drawn = analysis.drawn(measure: measure, scale: 10, displayUnit: .millimeter)
            #expect(drawn.edges.allSatisfy { $0.isWithin }, "\(measure) \(drawn.edges.map(\.label))")
        }
        let combs = analysis.drawn(measure: .curvature, scale: 10, displayUnit: .millimeter)
        let strokes = combs.strokes(unit: 0.01)
        // Two combs of 32 teeth, each with its outline through the tips.
        #expect(strokes.count == 2 * 33)
        let bend = 20 / pow(2, 1.5)
        for tooth in strokes where tooth.points.count == 2 {
            // A tooth is the curvature times unit² times the scale long: the arch's bend at both sides.
            #expect(abs((tooth.points[1] - tooth.points[0]).length - bend * 0.01 * 0.01 * 10) < 1e-5)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aPositionalAlignmentTurnsAcrossTheEdge() throws {
        let (base, preview) = try aligned(.positional)
        let analysis = try #require(try WorkspaceAlignAnalysis.evaluate(preview: preview, base: base, current: nil))
        #expect(analysis.drawn(measure: .position, scale: 10, displayUnit: .millimeter).edges.allSatisfy { $0.isWithin })
        let turns = analysis.drawn(measure: .tangent, scale: 2, displayUnit: .millimeter)
        #expect(turns.edges.allSatisfy { !$0.isWithin })
        // The flat sheet meets the arch's 45° slope: each hair is the normals' difference,
        // 2 sin(22.5°) long per unit, times the scale.
        for hair in turns.strokes(unit: 0.01) {
            #expect(abs((hair.points[1] - hair.points[0]).length - 2 * sin(Double.pi / 8) * 0.01 * 2) < 1e-3 * 0.02)
        }
        // A preview adding no alignment has nothing to analyse.
        #expect(try WorkspaceAlignAnalysis.evaluate(preview: base, base: base, current: nil) == nil)
    }
}
