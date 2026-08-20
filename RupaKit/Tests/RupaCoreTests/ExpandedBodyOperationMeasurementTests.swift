import SwiftCAD
import Testing
@testable import RupaCore

@Suite("Expanded body operation measurement")
struct ExpandedBodyOperationMeasurementTests {
    private let boxVolume = 0.040 * 0.020 * 0.010

    @Test(.timeLimit(.minutes(1)))
    func mirrorMeasuresTheReplacementBodyInsteadOfTheConsumedSource() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let sourceID = try appendBox(to: &builder, centerX: 0.0)
        let mirrorID = try builder.mirror(
            sourceID,
            planeOrigin: Point3D(x: 0.05, y: 0.0, z: 0.0),
            planeNormal: .unitX
        )
        let document = DesignDocument(
            cadDocument: try builder.build(name: "Mirror measurement")
        )

        let result = try MeasurementService().measure(
            document: document,
            ruler: .standard(for: .millimeter)
        )

        #expect(
            result.counts.solids == 1,
            "Measurement diagnostics: \(result.diagnostics)"
        )
        #expect(result.solids.first?.featureID == mirrorID.description)
        #expect(result.solids.first?.volumeMethod == .exactBRep)
        #expect(result.solids.first?.surfaceAreaMethod == .tessellatedMesh)
        #expect(result.solids.first?.boundsMethod == .tessellatedMesh)
        #expect(result.solids.contains { $0.featureID == sourceID.description } == false)
        #expect(abs(result.totals.solidVolumeCubicMeters - 2.0 * boxVolume) <= 1.0e-12)
        #expect(result.diagnostics.contains {
            $0.message.contains("tessellatedMesh are approximations")
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func joinMeasuresOneMultiShellReplacementBody() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let firstBoxID = try appendBox(to: &builder, centerX: 0.0)
        let secondBoxID = try appendBox(to: &builder, centerX: 100.0)
        let joinID = try builder.joinBodies([firstBoxID, secondBoxID])
        let document = DesignDocument(
            cadDocument: try builder.build(name: "Join measurement")
        )

        let result = try MeasurementService().measure(
            document: document,
            ruler: .standard(for: .millimeter)
        )

        #expect(result.counts.solids == 1)
        #expect(result.solids.first?.featureID == joinID.description)
        #expect(result.solids.first?.volumeMethod == .exactBRep)
        #expect(abs(result.totals.solidVolumeCubicMeters - 2.0 * boxVolume) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func unjoinMeasuresEverySplitReplacementBody() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let firstBoxID = try appendBox(to: &builder, centerX: 0.0)
        let secondBoxID = try appendBox(to: &builder, centerX: 100.0)
        let joinID = try builder.joinBodies([firstBoxID, secondBoxID])
        let unjoinID = try builder.unjoinBody(joinID)
        let document = DesignDocument(
            cadDocument: try builder.build(name: "Unjoin measurement")
        )

        let result = try MeasurementService().measure(
            document: document,
            ruler: .standard(for: .millimeter)
        )

        #expect(result.counts.solids == 2)
        #expect(result.solids.allSatisfy { $0.featureID == unjoinID.description })
        #expect(result.solids.allSatisfy { $0.volumeMethod == .exactBRep })
        #expect(abs(result.totals.solidVolumeCubicMeters - 2.0 * boxVolume) <= 1.0e-12)
    }

    private func appendBox(
        to builder: inout DocumentBuilder,
        centerX: Double
    ) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            appendRectangle(
                to: &sketch,
                centerX: centerX,
                width: 40.0,
                height: 20.0
            )
        }
        return try builder.extrude(
            profile,
            distance: .constant(.length(10.0, unit: .millimeter))
        )
    }

    private func appendRectangle(
        to sketch: inout SketchBuilder,
        centerX: Double,
        width: Double,
        height: Double
    ) {
        func millimeters(_ value: Double) -> CADExpression {
            .constant(.length(value, unit: .millimeter))
        }
        let left = millimeters(centerX - width / 2.0)
        let right = millimeters(centerX + width / 2.0)
        let bottom = millimeters(-height / 2.0)
        let top = millimeters(height / 2.0)
        let bottomLeft = SketchPoint(x: left, y: bottom)
        let bottomRight = SketchPoint(x: right, y: bottom)
        let topRight = SketchPoint(x: right, y: top)
        let topLeft = SketchPoint(x: left, y: top)
        _ = sketch.line(from: bottomLeft, to: bottomRight)
        _ = sketch.line(from: bottomRight, to: topRight)
        _ = sketch.line(from: topRight, to: topLeft)
        _ = sketch.line(from: topLeft, to: bottomLeft)
    }
}
