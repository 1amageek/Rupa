import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Plasticity's Offset Edge chain across a top and a slope: the edges between the front wall and
/// the top, and between the front wall and the slope, run over the top and the slope on one side
/// and over the front wall on the other.
@Suite struct EdgeOffsetSideResolverTests {
    private func meters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    @Test(.timeLimit(.minutes(1)))
    func aChainAcrossATopAndASlopeRunsOverBoth() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A prism along +y over a section with a flat top (x 0…0.06) and a slope down to x = 0.1;
        // on the ZX plane sketch x is world z and sketch y world x.
        let corners: [(x: Double, z: Double)] = [(0, 0), (0.1, 0), (0.1, 0.05), (0.06, 0.1), (0, 0.1)]
        let profile = try builder.sketch(on: .zx) { sketch in
            for k in corners.indices {
                let (a, b) = (corners[k], corners[(k + 1) % corners.count])
                _ = sketch.line(from: SketchPoint(x: meters(a.z), y: meters(a.x)), to: SketchPoint(x: meters(b.z), y: meters(b.x)))
            }
        }
        _ = try builder.extrude(profile, distance: meters(0.1))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        func edge(from a: (x: Double, z: Double), to b: (x: Double, z: Double)) throws -> EdgeID {
            try #require(model.edges.first { _, edge in
                guard let start = model.vertices[edge.startVertexID]?.point, let end = model.vertices[edge.endVertexID]?.point,
                      abs(start.y) < 1e-9, abs(end.y) < 1e-9 else { return false }
                func at(_ p: Point3D, _ q: (x: Double, z: Double)) -> Bool { abs(p.x - q.x) < 1e-9 && abs(p.z - q.z) < 1e-9 }
                return (at(start, a) && at(end, b)) || (at(start, b) && at(end, a))
            }?.key)
        }
        func face(normal: Vector3D) throws -> FaceID {
            try #require(model.faces.first { _, face in
                guard case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else { return false }
                let outward = face.orientation == .forward ? plane.normal : plane.normal * -1
                return (outward - normal).length < 1e-6
            }?.key)
        }
        let topEdge = try edge(from: (0, 0.1), to: (0.06, 0.1))
        let slopeEdge = try edge(from: (0.06, 0.1), to: (0.1, 0.05))
        let top = try face(normal: Vector3D(x: 0, y: 0, z: 1))
        let slope = try face(normal: try Vector3D(x: 0.05, y: 0, z: 0.04).normalized(tolerance: 1e-12))
        let sides = try EdgeOffsetSideResolver(model: model).sides(of: [topEdge, slopeEdge], startingOn: top, operationName: "Offset Edge")
        #expect(sides.map(\.support) == [top, slope])
        // The front wall (the section's own face, at y = 0) lies across both.
        let front = try #require(model.faces.first { _, face in
            guard case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else { return false }
            return abs(abs(plane.normal.y) - 1) < 1e-9 && abs(plane.origin.y) < 1e-9
        }?.key)
        #expect(sides.map(\.across) == [front, front])
        // Started on the front wall, both run over it.
        let other = try EdgeOffsetSideResolver(model: model).sides(of: [slopeEdge, topEdge], startingOn: front, operationName: "Offset Edge")
        #expect(other.map(\.support) == [front, front])
        // An edge off the chain is refused.
        let far = try edge(from: (0, 0), to: (0.1, 0))
        #expect(throws: EditorError.self) {
            _ = try EdgeOffsetSideResolver(model: model).sides(of: [topEdge, far], startingOn: top, operationName: "Offset Edge")
        }
    }
}
