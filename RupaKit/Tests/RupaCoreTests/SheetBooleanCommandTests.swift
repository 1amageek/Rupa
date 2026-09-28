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
}
