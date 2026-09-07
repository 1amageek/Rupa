import Foundation
import RupaCADIntegration
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaViewportScene
import SwiftCAD

enum ProjectGeometryExport {
    static func data(from snapshot: ProjectViewSnapshot, format: ProjectGeometryFileFormat, unit: LengthDisplayUnit) throws -> Data {
        try Task.checkCancellation()
        let tolerance = snapshot.document.document.modelingSettings.tolerance
        let sink = DataByteSink()
        if format == .step {
            let document = snapshot.document.document
            guard document.authoredMeshAssets.isEmpty else {
                throw unsupported("STEP export requires exact CAD-only source. Use STL/OBJ for Authored Mesh geometry.")
            }
            let evaluated: EvaluatedDocument
            do {
                evaluated = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
                    document: document, currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration,
                    failurePrefix: "Exact STEP export evaluation failed"
                )
            } catch {
                try Task.checkCancellation()
                throw error
            }
            try Task.checkCancellation()
            var bodies = Set<BodyID>()
            for item in snapshot.viewport.items {
                guard item.worldTransform == .identity,
                      case .cad(_, let outputID) = item.reference,
                      let body = CADGeometryExchange.resolvedBodyID(outputID: outputID, in: evaluated),
                      bodies.insert(body).inserted else {
                    throw unsupported("Exact STEP source export cannot represent scene placement or repeated body occurrences. Use STL/OBJ to export world placement.")
                }
            }
            guard !bodies.isEmpty, bodies == Set(evaluated.brep.bodies.keys) else {
                throw unsupported("STEP source export requires every exact body to be visible exactly once.")
            }
            try STEPExchange(tolerance: tolerance).write(
                brep: evaluated.brep,
                units: UnitSystem(length: unit.swiftCADLengthUnit, angle: .radian), to: sink
            )
        } else {
            guard !snapshot.viewport.items.isEmpty else { throw ExportError.emptyMesh }
            let limit = EvaluationResourceLimits.standard
            guard snapshot.viewport.items.count <= limit.maximumSourceCount else {
                throw unsupported("Geometry export exceeds the occurrence limit.")
            }
            var meshes: [BodyID: Mesh] = [:]
            var retainedBytes = 0
            for item in snapshot.viewport.items {
                try Task.checkCancellation()
                if format == .obj, let nodeID = snapshot.sceneNodeIDByOccurrenceID[item.id],
                   snapshot.document.document.productMetadata.sceneNodes[nodeID]?.materialID != nil {
                    throw unsupported("OBJ material export is unavailable. Save .rupa to retain materials, or use geometry-only STL.")
                }
                meshes[BodyID()] = try mesh(item, format: format, tolerance: tolerance, retainedBytes: &retainedBytes)
            }
            if format == .stl {
                try STLExporter(tolerance: tolerance).writeBinary(meshes: meshes, options: STLExportOptions(lengthUnit: unit.swiftCADLengthUnit), to: sink)
            } else {
                try OBJExchange(tolerance: tolerance).write(meshes: meshes, unit: unit.swiftCADLengthUnit, to: sink)
            }
        }
        try Task.checkCancellation()
        return sink.bytes
    }

    private static func mesh(
        _ item: UniversalViewportSceneItem, format: ProjectGeometryFileFormat,
        tolerance: ModelingTolerance, retainedBytes: inout Int
    ) throws -> Mesh {
        let source = item.mesh
        let usage = try source.resourceUsage()
        let limits = EvaluationResourceLimits.standard
        guard usage.vertexCount <= limits.maximumVertexCount,
              usage.triangleCount <= limits.maximumTriangleCount,
              usage.vertexCount <= Int(UInt32.max), usage.triangleCount > 0 else {
            throw unsupported("Geometry export exceeds Mesh limits or contains no surface faces.")
        }
        let indexCount = try multiply(usage.triangleCount, 3)
        let vertexStride = MemoryLayout<Point3D>.stride + MemoryLayout<Vector3D>.stride + MemoryLayout<Point2D>.stride
        let derivedBytes = try add(multiply(usage.vertexCount, vertexStride), multiply(indexCount, MemoryLayout<UInt32>.stride))
        let maxFace = source.faceCornerRanges.lazy.map(\.count).max() ?? 0
        guard maxFace <= MeshTriangulationLimits.standard.maxFaceCornerCount else {
            throw unsupported("Geometry export face exceeds the triangulation limit.")
        }
        let scratch = try add(MeshSourceTriangulationIndex.storageReservation(vertexCount: usage.vertexCount), multiply(maxFace, 256))
        let retained = try add(retainedBytes, derivedBytes)
        guard try add(add(retained, scratch), ExchangeResourceLimits.standard.maximumBytes) <= limits.maximumByteCount else {
            throw unsupported("Geometry export exceeds the working-memory limit.")
        }
        retainedBytes = retained
        let values = item.worldTransform.values
        guard values[12] == 0, values[13] == 0, values[14] == 0, values[15] == 1 else {
            throw unsupported("Geometry export requires affine scene placement.")
        }
        let x = Vector3D(x: values[0], y: values[4], z: values[8])
        let y = Vector3D(x: values[1], y: values[5], z: values[9])
        let z = Vector3D(x: values[2], y: values[6], z: values[10])
        let determinant = x.dot(y.cross(z))
        guard determinant.isFinite, determinant != 0 else { throw unsupported("Geometry export requires non-singular placement.") }
        let normalX = y.cross(z) / determinant
        let normalY = z.cross(x) / determinant
        let normalZ = x.cross(y) / determinant
        let index = try source.makeTriangulationIndex()
        var result = Mesh()
        result.positions.reserveCapacity(usage.vertexCount)
        result.indices.reserveCapacity(indexCount)
        for (offset, point) in source.vertexPositions.enumerated() {
            if offset.isMultiple(of: 1_024) { try Task.checkCancellation() }
            let transformed = try item.worldTransform.applying(to: point)
            result.positions.append(Point3D(x: transformed.x, y: transformed.y, z: transformed.z))
        }
        var telemetry = MeshTriangulationTelemetry()
        func positionIndex(_ id: MeshVertexID) throws -> UInt32 {
            guard let position = index.positionIndex(for: id) else {
                throw EditorError(code: .exportFailed, message: "An export triangle references a missing vertex.")
            }
            return UInt32(position)
        }
        for face in source.faceIDs.indices {
            try Task.checkCancellation()
            for triangle in try source.triangulate(faceIndex: face, using: index, tolerance: tolerance.distance, telemetry: &telemetry) {
                result.indices.append(try positionIndex(triangle.vertexIDs.0))
                result.indices.append(try positionIndex(determinant < 0 ? triangle.vertexIDs.2 : triangle.vertexIDs.1))
                result.indices.append(try positionIndex(determinant < 0 ? triangle.vertexIDs.1 : triangle.vertexIDs.2))
            }
        }
        if format == .obj {
            for layer in source.attributes.sortedLayers() {
                guard layer.descriptor.domain == .vertex, !layer.descriptor.isSparse,
                      layer.indices == nil, layer.values.count == usage.vertexCount else {
                    throw unsupported("OBJ export cannot preserve sparse or non-vertex attributes. Save .rupa to retain them.")
                }
                switch (layer.descriptor.id.rawValue, layer.values) {
                case ("cad.normal", .vector3(let normals)):
                    result.normals.reserveCapacity(normals.count)
                    for normal in normals {
                        try Task.checkCancellation()
                        // Inverse transpose preserves normals under nonuniform scale.
                        let transformed = normalX * normal.x + normalY * normal.y + normalZ * normal.z
                        guard transformed.isFinite else {
                            throw EditorError(
                                code: .exportFailed,
                                message: "OBJ export contains a non-finite transformed normal."
                            )
                        }
                        let scale = max(abs(transformed.x), max(abs(transformed.y), abs(transformed.z)))
                        guard scale.isFinite, scale > 0.0 else {
                            throw EditorError(
                                code: .exportFailed,
                                message: "OBJ export contains a zero transformed normal."
                            )
                        }
                        result.normals.append(
                            try (transformed / scale).normalized(tolerance: Double.ulpOfOne)
                        )
                    }
                case ("cad.uv", .vector2(let coordinates)):
                    result.textureCoordinates.reserveCapacity(coordinates.count)
                    for coordinate in coordinates {
                        try Task.checkCancellation()
                        result.textureCoordinates.append(Point2D(x: coordinate.x, y: coordinate.y))
                    }
                default:
                    throw unsupported("OBJ export cannot preserve attribute \(layer.descriptor.id.rawValue). Save .rupa to retain it.")
                }
            }
        }
        try result.validate(tolerance: tolerance)
        return result
    }

    private static func multiply(_ a: Int, _ b: Int) throws -> Int {
        let result = a.multipliedReportingOverflow(by: b)
        guard !result.overflow else { throw unsupported("Geometry export size overflow.") }
        return result.partialValue
    }

    private static func add(_ a: Int, _ b: Int) throws -> Int {
        let result = a.addingReportingOverflow(b)
        guard !result.overflow else { throw unsupported("Geometry export size overflow.") }
        return result.partialValue
    }

    private static func unsupported(_ message: String) -> EditorError {
        EditorError(code: .commandUnsupported, message: message)
    }
}
