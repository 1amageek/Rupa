import SwiftCAD
import Testing
@testable import RupaCore

@Suite("Expanded body operation measurement")
struct ExpandedBodyOperationMeasurementTests {
    private let boxVolume = 0.040 * 0.020 * 0.010

    @Test(.timeLimit(.minutes(1)))
    func measuresEveryPrimitiveDefinitionFromItsEvaluatedBodyOutput() throws {
        let primitives: [(name: String, definition: PrimitiveDefinition, volume: Double)] = [
            (
                name: "Box",
                definition: .box(BoxPrimitive(
                    width: .constant(.length(2.0, unit: .millimeter)),
                    depth: .constant(.length(3.0, unit: .millimeter)),
                    height: .constant(.length(4.0, unit: .millimeter))
                )),
                volume: 24.0e-9
            ),
            (
                name: "Cylinder",
                definition: .cylinder(CylinderPrimitive(
                    radius: .constant(.length(1.25, unit: .millimeter)),
                    height: .constant(.length(3.0, unit: .millimeter))
                )),
                volume: Double.pi * 0.00125 * 0.00125 * 0.003
            ),
            (
                name: "Cone",
                definition: .cone(ConePrimitive(
                    baseRadius: .constant(.length(1.5, unit: .millimeter)),
                    height: .constant(.length(3.0, unit: .millimeter))
                )),
                volume: Double.pi * 0.0015 * 0.0015 * 0.003 / 3.0
            ),
            (
                name: "Sphere",
                definition: .sphere(SpherePrimitive(
                    radius: .constant(.length(2.0, unit: .millimeter))
                )),
                volume: 4.0 * Double.pi * 0.002 * 0.002 * 0.002 / 3.0
            ),
            (
                name: "Torus",
                definition: .torus(TorusPrimitive(
                    majorRadius: .constant(.length(4.0, unit: .meter)),
                    minorRadius: .constant(.length(1.0, unit: .meter))
                )),
                volume: 8.0 * Double.pi * Double.pi
            ),
        ]

        for primitive in primitives {
            var cadDocument = CADDocument(units: .meters)
            let featureID = FeatureID()
            let node = try FeatureNodeFactory.make(
                operation: .primitive(PrimitiveFeature(definition: primitive.definition)),
                id: featureID,
                name: primitive.name,
                in: cadDocument,
                tolerance: .standard
            )
            cadDocument.designGraph.nodes[featureID] = node
            cadDocument.designGraph.order = [featureID]
            cadDocument.designGraph.revision = cadDocument.designGraph.revision.advanced()
            // Keep the presentation mesh bounded; solid volume remains exact B-rep data.
            let document = DesignDocument(
                cadDocument: cadDocument,
                modelingSettings: DocumentModelingSettings(
                    tolerance: .standard,
                    tessellationOptions: TessellationOptions(
                        linearTolerance: 1.0e-3,
                        angularTolerance: 0.25
                    )
                )
            )

            let result = try MeasurementService().measure(
                document: document,
                ruler: .standard(for: .millimeter)
            )
            let solid = try #require(
                result.solids.first,
                Comment(rawValue: "\(primitive.name): \(result.diagnostics)")
            )
            #expect(result.counts.solids == 1)
            #expect(solid.featureID == featureID.description)
            #expect(solid.sourceFeatureID == featureID.description)
            #expect(solid.volumeMethod == .exactBRep)
            #expect(solid.surfaceAreaMethod == .tessellatedMesh)
            #expect(solid.boundsMethod == .tessellatedMesh)
            #expect(
                abs(solid.volume.value - primitive.volume) <= max(
                    primitive.volume * 1.0e-10,
                    1.0e-18
                )
            )
        }
    }

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
