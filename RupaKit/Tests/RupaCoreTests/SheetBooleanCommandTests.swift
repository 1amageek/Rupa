import SwiftCAD
import Testing
@testable import RupaCore

/// Booleans take sheets as operands: a sheet tool cuts a solid on the side behind its normals,
/// a solid tool trims a sheet target, and the result is shown as a solid or a surface as its
/// output says.
@Suite struct SheetBooleanCommandTests {
    private let cube = 0.1 * 0.1 * 0.1

    /// A 100 mm cube on the XY plane and a large horizontal sheet 25 mm up facing +z.
    @MainActor
    private func operands() throws -> (EditorSession, box: FeatureID, sheet: FeatureID) {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        ))
        _ = try session.execute(.createBSplineSurface(name: "Sheet", surface: .bilinearPatch(
            bottomLeft: Point3D(x: -1, y: -1, z: 0.025), bottomRight: Point3D(x: 1, y: -1, z: 0.025),
            topRight: Point3D(x: 1, y: 1, z: 0.025), topLeft: Point3D(x: -1, y: 1, z: 0.025)
        )))
        let nodes = session.document.productMetadata.sceneNodes.values
        let box = try #require(nodes.first { $0.name.hasPrefix("Box") && $0.reference?.kind == .body }?.reference?.featureID)
        let sheet = try #require(nodes.first { $0.name.hasPrefix("Sheet") }?.reference?.featureID)
        return (session, box, sheet)
    }

    private func volume(_ document: DesignDocument) throws -> Double {
        try MeasurementService().measure(document: document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
    }

    private func resultNode(_ session: EditorSession, _ result: CommandExecutionResult) throws -> SceneNode {
        let feature = try #require(result.generatedIdentities.featureIDs.last)
        return try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference == .body(feature) })
    }

    @MainActor
    @Test func aSheetToolCutsASolid() throws {
        let (session, box, sheet) = try operands()
        let result = try session.execute(.createBoolean(
            name: "Cut", targets: [BooleanTargetReference(featureID: box)],
            tools: [BooleanToolReference(featureID: sheet)], operation: .difference, keepTools: false
        ))
        #expect(abs(try volume(session.document) - 0.75 * cube) < 1e-9)
        #expect(try resultNode(session, result).object?.geometryRole == .solid)
        #expect(session.evaluationStatus == .valid)
        // The result takes over the box's object; the sheet's object goes with the sheet.
        #expect(session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }.count == 1)
        try expectEveryBodyObjectPresentsAnEvaluatedBody(session.document)
    }

    @MainActor
    @Test func outsideMaterialKeepsTheOtherSide() throws {
        let (session, box, sheet) = try operands()
        _ = try session.execute(.createBoolean(
            name: "Cut", targets: [BooleanTargetReference(featureID: box)],
            tools: [BooleanToolReference(featureID: sheet)], operation: .difference, keepTools: false,
            toolMaterial: .outside
        ))
        #expect(abs(try volume(session.document) - 0.25 * cube) < 1e-9)
    }

    @MainActor
    @Test func aSolidToolTrimsASheetTargetIntoASurface() throws {
        let (session, box, sheet) = try operands()
        let result = try session.execute(.createBoolean(
            name: "Trim", targets: [BooleanTargetReference(featureID: sheet)],
            tools: [BooleanToolReference(featureID: box)], operation: .intersect, keepTools: false
        ))
        let node = try resultNode(session, result)
        #expect(node.object?.geometryRole == .surface)
        let feature = try #require(result.generatedIdentities.featureIDs.last)
        #expect(session.document.cadDocument.designGraph.nodes[feature]?.outputs.map(\.role) == [.sheet])
        #expect(session.evaluationStatus == .valid)
    }

    /// A slice publishes each piece as its own object, through one extraction per piece.
    @MainActor
    @Test func aSliceShowsEachPieceAsItsOwnObject() throws {
        let (session, box, sheet) = try operands()
        _ = try session.execute(.createBoolean(
            name: "Slice", targets: [BooleanTargetReference(featureID: box)],
            tools: [BooleanToolReference(featureID: sheet)], operation: .slice, keepTools: false
        ))
        let pieces = session.document.productMetadata.sceneNodes.values.filter { $0.name.hasPrefix("Slice ") }
        #expect(pieces.count == 2)
        #expect(pieces.allSatisfy { $0.object?.geometryRole == .solid })
        let extractions = try pieces.map { node -> ExtractFeature in
            let feature = try #require(node.reference?.featureID)
            guard case let .extract(extract) = session.document.cadDocument.designGraph.nodes[feature]?.operation else {
                throw EditorError(code: .referenceUnresolved, message: "Not an extraction.")
            }
            return extract
        }
        #expect(Set(extractions.map(\.selection)) == [.component(index: 0, count: 2), .component(index: 1, count: 2)])
        // The pieces are measured, not the slice they came from.
        #expect(abs(try volume(session.document) - cube) < 1e-9)
        #expect(session.evaluationStatus == .valid)
        try expectEveryBodyObjectPresentsAnEvaluatedBody(session.document)
    }

    /// Extraction copies: one extracted component of a two-piece slice leaves the slice measured,
    /// the piece measured beside it.
    @MainActor
    @Test func aSingleExtractedComponentLeavesItsSourceMeasured() throws {
        let (session, box, sheet) = try operands()
        var document = session.document
        let slice = try document.appendBooleanFeature(
            name: "Slice", targets: [box], tools: [sheet], operation: .slice, keepTools: false,
            targetMaterial: .default, toolMaterial: .default
        )
        let piece = FeatureID()
        try document.appendFeature(FeatureNode(
            id: piece, name: "Piece",
            operation: .extract(ExtractFeature(
                target: PatternTargetReference(featureID: slice.featureID),
                selection: .component(index: 0, count: 2)
            )),
            inputs: [FeatureInput(featureID: slice.featureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        ))
        let extra = try volume(document) - cube
        #expect(abs(extra - 0.25 * cube) < 1e-9 || abs(extra - 0.75 * cube) < 1e-9, "measured \(extra / cube) cubes beyond the slice")
    }

    /// A region shows each cell the operands enclose as its own object; the sheet's parts outside
    /// the box enclose nothing and go.
    @MainActor
    @Test func aRegionShowsEachCellAsItsOwnObject() throws {
        let (session, box, sheet) = try operands()
        _ = try session.execute(.createBoolean(
            name: "Region", targets: [BooleanTargetReference(featureID: box)],
            tools: [BooleanToolReference(featureID: sheet)], operation: .region, keepTools: false
        ))
        let pieces = session.document.productMetadata.sceneNodes.values.filter { $0.name.hasPrefix("Region ") }
        #expect(pieces.count == 2)
        #expect(pieces.allSatisfy { $0.object?.geometryRole == .solid })
        #expect(abs(try volume(session.document) - cube) < 1e-9)
        #expect(session.evaluationStatus == .valid)
    }
}
