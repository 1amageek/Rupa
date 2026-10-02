import RupaCore
import SwiftCAD

/// Align Surface's Analysis drawn along each aligned edge while its dialog is open (Plasticity's
/// Analysis: one continuity checked at its scale): at every sampled point of the reference edge,
/// G0 draws the gap to the sheet magnified by its scale, G1 the turn between the two normals
/// (their difference, `unit` long per radian) and G2 both surfaces' curvature combs across the
/// edge (`unit`² long per m⁻¹), each times its scale; each edge carries its worst value as a label.
public struct ViewportEdgeAlignmentAnalysis: Equatable, Sendable {
    public enum Measure: String, CaseIterable, Sendable {
        case position = "G0"
        case tangent = "G1"
        case curvature = "G2"
    }

    /// One analysed point of a reference edge, in the world.
    public struct Sample: Equatable, Sendable {
        public let edgePoint: Point3D
        public let sheetPoint: Point3D
        public let sheetNormal: Vector3D
        public let referenceNormal: Vector3D
        public let sheetCurvature: Double
        public let referenceCurvature: Double

        public init(edgePoint: Point3D, sheetPoint: Point3D, sheetNormal: Vector3D, referenceNormal: Vector3D,
                    sheetCurvature: Double, referenceCurvature: Double) {
            self.edgePoint = edgePoint
            self.sheetPoint = sheetPoint
            self.sheetNormal = sheetNormal
            self.referenceNormal = referenceNormal
            self.sheetCurvature = sheetCurvature
            self.referenceCurvature = referenceCurvature
        }
    }

    /// One aligned edge: its samples in order along it, and its worst value of the measure,
    /// formatted, with whether it is within the measure's limit.
    public struct Edge: Equatable, Sendable {
        public let samples: [Sample]
        public let label: String
        public let isWithin: Bool

        public init(samples: [Sample], label: String, isWithin: Bool) {
            self.samples = samples
            self.label = label
            self.isWithin = isWithin
        }
    }

    /// A drawn polyline: a hair (two points) or a comb's outline through its teeth's tips.
    public struct Stroke: Equatable, Sendable {
        public enum Role: Equatable, Sendable { case gap, turn, sheetComb, referenceComb }
        public let points: [Point3D]
        public let role: Role
    }

    public var measure: Measure
    /// The measure's scale, Plasticity's G0, G1 or G2 Scale.
    public var scale: Double
    public var edges: [Edge]

    public init(measure: Measure, scale: Double, edges: [Edge]) {
        self.measure = measure
        self.scale = scale
        self.edges = edges
    }

    /// The hairs and comb outlines of every edge, with `unit` the length a radian of turn draws
    /// (and its square a m⁻¹ of curvature).
    public func strokes(unit: Double) -> [Stroke] {
        func moved(_ point: Point3D, _ vector: Vector3D, _ length: Double) -> Point3D {
            Point3D(x: point.x + vector.x * length, y: point.y + vector.y * length, z: point.z + vector.z * length)
        }
        var strokes: [Stroke] = []
        for edge in edges {
            switch measure {
            case .position:
                for sample in edge.samples {
                    let gap = sample.sheetPoint - sample.edgePoint
                    strokes.append(Stroke(points: [sample.edgePoint, moved(sample.edgePoint, gap, scale)], role: .gap))
                }
            case .tangent:
                for sample in edge.samples {
                    let turn = sample.sheetNormal - sample.referenceNormal
                    strokes.append(Stroke(points: [sample.edgePoint, moved(sample.edgePoint, turn, unit * scale)], role: .turn))
                }
            case .curvature:
                let length = unit * unit * scale
                for (role, normal, curvature) in [(Stroke.Role.sheetComb, \Sample.sheetNormal, \Sample.sheetCurvature),
                                                  (.referenceComb, \.referenceNormal, \.referenceCurvature)] {
                    let tips = edge.samples.map { moved($0.edgePoint, $0[keyPath: normal], $0[keyPath: curvature] * length) }
                    for (sample, tip) in zip(edge.samples, tips) {
                        strokes.append(Stroke(points: [sample.edgePoint, tip], role: role))
                    }
                    if tips.count >= 2 { strokes.append(Stroke(points: tips, role: role)) }
                }
            }
        }
        return strokes
    }
}
